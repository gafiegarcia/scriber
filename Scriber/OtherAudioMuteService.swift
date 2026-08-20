import AudioToolbox
import CoreAudio
import Foundation

/// Drives the mute tap without crossing into Swift concurrency or touching the supplied audio.
/// Core Audio invokes this function on a real-time IO thread, so it must remain nonisolated.
private func discardAudioIOProc(
    _ device: AudioObjectID,
    _ now: UnsafePointer<AudioTimeStamp>,
    _ inputData: UnsafePointer<AudioBufferList>,
    _ inputTime: UnsafePointer<AudioTimeStamp>,
    _ outputData: UnsafeMutablePointer<AudioBufferList>,
    _ outputTime: UnsafePointer<AudioTimeStamp>,
    _ clientData: UnsafeMutableRawPointer?
) -> OSStatus {
    noErr
}

/// The result of asking the system-audio mute service to begin silencing other apps.
///
/// An unavailable result is intentionally non-fatal: microphone dictation can continue
/// without changing other apps' audio.
enum OtherAudioMutingOutcome: Equatable, Sendable {
    case muted
    case alreadyMuted
    case unavailable(OSStatus)
}

/// The result of asking the system-audio mute service to restore other apps' audio.
enum OtherAudioUnmutingOutcome: Equatable, Sendable {
    case restored
    case alreadyRestored
    case unavailable(OSStatus)
}

/// A mute that fails to start says nothing: the music carries on playing, which
/// the user can hear, and nothing needs saying about a fact they are listening
/// to. A mute that fails to *end* is the opposite — a Mac that stays silent for
/// no visible reason, with a fix nobody would guess.
enum OtherAudioMuteStatus: Equatable, Sendable {
    case unableToRestore

    var message: String {
        switch self {
        case .unableToRestore:
            "Scriber could not restore other app audio. Quit Scriber if it remains silent."
        }
    }
}

/// A small boundary around the system-wide, temporary audio mute behavior.
///
/// Keeping this protocol independent of recording makes lifecycle behavior testable without
/// creating a Core Audio tap or triggering the System Audio Recording permission flow.
@MainActor
protocol OtherAudioMuting: AnyObject {
    @discardableResult
    func beginMuting() -> OtherAudioMutingOutcome

    @discardableResult
    func endMuting() -> OtherAudioUnmutingOutcome
}

/// Temporarily silences every audio process except Scriber itself.
///
/// Core Audio only drives a process tap after an audio client reads it. The private aggregate
/// device and IOProc below keep that tap active; their callback deliberately ignores every input
/// buffer, so Scriber never inspects, copies, records, or persists another app's audio samples.
///
/// The app's current process object ID and bundle ID are both excluded. The bundle ID makes the
/// exclusion survive Core Audio process-object recreation while `processRestoreEnabled` ensures
/// newly launched non-Scriber apps remain muted for the current session.
@MainActor
final class OtherAudioMuteService: OtherAudioMuting {
    private var tapID: AudioObjectID?
    private var aggregateDeviceID: AudioObjectID?
    private var ioProcID: AudioDeviceIOProcID?
    /// Runs alongside the tap for one thing only: letting go of it ramps other
    /// audio back up over about a second, where the tap can only switch. While
    /// the tap holds everything silent this changes nothing anyone can hear —
    /// including Scriber's own cue lifting the duck, which is inaudible under a
    /// mute the cue is excluded from.
    private var duckingUnit: AudioUnit?

    isolated deinit {
        if let aggregateDeviceID, let ioProcID {
            AudioDeviceStop(aggregateDeviceID, ioProcID)
            AudioDeviceDestroyIOProcID(aggregateDeviceID, ioProcID)
        }
        if let aggregateDeviceID { AudioHardwareDestroyAggregateDevice(aggregateDeviceID) }
        if let tapID { AudioHardwareDestroyProcessTap(tapID) }
        if let duckingUnit {
            AudioOutputUnitStop(duckingUnit)
            AudioUnitUninitialize(duckingUnit)
            AudioComponentInstanceDispose(duckingUnit)
        }
    }

    /// Raises the System Audio Recording prompt, by doing the one thing that
    /// asks for it.
    ///
    /// Creating a tap is not the moment macOS checks — driving one is, which is
    /// why the prompt used to land in the middle of a first dictation. So this
    /// builds the same aggregate device and IOProc the real mute does and starts
    /// it, then takes it all down. Its tap is `.unmuted`, so nothing anyone is
    /// listening to goes quiet while the question is on screen.
    ///
    /// Deliberately outside the actor and touching no stored state: macOS blocks
    /// its caller for as long as the prompt is up, and on the main thread that is
    /// a beachball.
    nonisolated static func requestAccess() -> OSStatus {
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        description.name = "Scriber audio access check"
        description.isPrivate = true
        description.muteBehavior = CATapMuteBehavior.unmuted

        var tapID = AudioObjectID(kAudioObjectUnknown)
        let tapStatus = AudioHardwareCreateProcessTap(description, &tapID)
        guard tapStatus == noErr, tapID != kAudioObjectUnknown else {
            return tapStatus == noErr ? kAudioHardwareUnspecifiedError : tapStatus
        }
        defer { AudioHardwareDestroyProcessTap(tapID) }

        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Scriber audio access check",
            kAudioAggregateDeviceUIDKey: "com.gafiegarcia.scriber.access.\(UUID().uuidString)",
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapUIDKey: description.uuid.uuidString,
                kAudioSubTapDriftCompensationKey: false
            ]]
        ]
        var aggregateID = AudioObjectID(kAudioObjectUnknown)
        let aggregateStatus = AudioHardwareCreateAggregateDevice(
            aggregateDescription as CFDictionary, &aggregateID
        )
        guard aggregateStatus == noErr, aggregateID != kAudioObjectUnknown else {
            return aggregateStatus == noErr ? kAudioHardwareUnspecifiedError : aggregateStatus
        }
        defer { AudioHardwareDestroyAggregateDevice(aggregateID) }

        var ioProcID: AudioDeviceIOProcID?
        let ioProcStatus = AudioDeviceCreateIOProcID(aggregateID, discardAudioIOProc, nil, &ioProcID)
        guard ioProcStatus == noErr, let ioProcID else {
            return ioProcStatus == noErr ? kAudioHardwareUnspecifiedError : ioProcStatus
        }
        defer { AudioDeviceDestroyIOProcID(aggregateID, ioProcID) }

        // The prompt happens here, and this does not return until it is answered.
        let startStatus = AudioDeviceStart(aggregateID, ioProcID)
        if startStatus == noErr { AudioDeviceStop(aggregateID, ioProcID) }
        return startStatus
    }

    @discardableResult
    func beginMuting() -> OtherAudioMutingOutcome {
        if tapID != nil, aggregateDeviceID != nil, ioProcID != nil {
            return .alreadyMuted
        }
        if tapID != nil || aggregateDeviceID != nil || ioProcID != nil,
           case .unavailable(let status) = endMuting() {
            return .unavailable(status)
        }

        let description = CATapDescription(
            stereoGlobalTapButExcludeProcesses: excludedProcessObjectIDs()
        )
        description.name = "Scriber temporary audio mute"
        description.isExclusive = true
        description.isPrivate = true
        description.muteBehavior = CATapMuteBehavior.muted
        description.isProcessRestoreEnabled = true

        // Process-object IDs cover the currently running Scriber process. Bundle IDs cover a
        // freshly recreated Core Audio process object and avoid muting Scriber feedback sounds.
        if let bundleIdentifier = Bundle.main.bundleIdentifier, !bundleIdentifier.isEmpty {
            description.bundleIDs = [bundleIdentifier]
        }

        var createdTapID = AudioObjectID(kAudioObjectUnknown)
        let status = AudioHardwareCreateProcessTap(description, &createdTapID)
        guard status == noErr else {
            return .unavailable(status)
        }
        guard createdTapID != kAudioObjectUnknown else {
            return .unavailable(kAudioHardwareUnspecifiedError)
        }

        let aggregateUID = "com.gafiegarcia.scriber.mute.\(UUID().uuidString)"
        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Scriber temporary audio mute",
            kAudioAggregateDeviceUIDKey: aggregateUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapUIDKey: description.uuid.uuidString,
                kAudioSubTapDriftCompensationKey: false
            ]]
        ]
        var createdAggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
        let aggregateStatus = AudioHardwareCreateAggregateDevice(
            aggregateDescription as CFDictionary,
            &createdAggregateDeviceID
        )
        guard aggregateStatus == noErr, createdAggregateDeviceID != kAudioObjectUnknown else {
            AudioHardwareDestroyProcessTap(createdTapID)
            return .unavailable(aggregateStatus == noErr ? kAudioHardwareUnspecifiedError : aggregateStatus)
        }

        var createdIOProcID: AudioDeviceIOProcID?
        let ioProcStatus = AudioDeviceCreateIOProcID(
            createdAggregateDeviceID,
            discardAudioIOProc,
            nil,
            &createdIOProcID
        )
        guard ioProcStatus == noErr, let createdIOProcID else {
            AudioHardwareDestroyAggregateDevice(createdAggregateDeviceID)
            AudioHardwareDestroyProcessTap(createdTapID)
            return .unavailable(ioProcStatus == noErr ? kAudioHardwareUnspecifiedError : ioProcStatus)
        }

        let startStatus = AudioDeviceStart(createdAggregateDeviceID, createdIOProcID)
        guard startStatus == noErr else {
            AudioDeviceDestroyIOProcID(createdAggregateDeviceID, createdIOProcID)
            AudioHardwareDestroyAggregateDevice(createdAggregateDeviceID)
            AudioHardwareDestroyProcessTap(createdTapID)
            return .unavailable(startStatus)
        }

        tapID = createdTapID
        aggregateDeviceID = createdAggregateDeviceID
        ioProcID = createdIOProcID
        startDucking()
        return .muted
    }

    @discardableResult
    func endMuting() -> OtherAudioUnmutingOutcome {
        guard tapID != nil || aggregateDeviceID != nil || ioProcID != nil else {
            return .alreadyRestored
        }

        var firstFailure: OSStatus?
        if let aggregateDeviceID, let ioProcID {
            let stopStatus = AudioDeviceStop(aggregateDeviceID, ioProcID)
            if stopStatus != noErr { firstFailure = firstFailure ?? stopStatus }
            let destroyIOStatus = AudioDeviceDestroyIOProcID(aggregateDeviceID, ioProcID)
            if destroyIOStatus == noErr {
                self.ioProcID = nil
            } else {
                firstFailure = firstFailure ?? destroyIOStatus
            }
        }
        if let aggregateDeviceID {
            let aggregateStatus = AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
            if aggregateStatus == noErr {
                self.aggregateDeviceID = nil
                self.ioProcID = nil
            } else {
                firstFailure = firstFailure ?? aggregateStatus
            }
        }
        if let tapID {
            let tapStatus = AudioHardwareDestroyProcessTap(tapID)
            if tapStatus == noErr {
                self.tapID = nil
            } else {
                firstFailure = firstFailure ?? tapStatus
            }
        }

        // After the tap, never before: the ramp is only worth anything while
        // the audio it is ramping is audible again.
        stopDucking()

        if let firstFailure { return .unavailable(firstFailure) }
        return .restored
    }

    private func startDucking() {
        var description = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_VoiceProcessingIO,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        guard let component = AudioComponentFindNext(nil, &description) else { return }
        var created: AudioUnit?
        guard AudioComponentInstanceNew(component, &created) == noErr, let created else { return }

        var enableInput: UInt32 = 1
        var configuration = AUVoiceIOOtherAudioDuckingConfiguration(
            mEnableAdvancedDucking: false,
            mDuckingLevel: AUVoiceIOOtherAudioDuckingLevel.max
        )
        let configured = AudioUnitSetProperty(
            created, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1,
            &enableInput, UInt32(MemoryLayout<UInt32>.size)
        ) == noErr
            && AudioUnitSetProperty(
                created, kAUVoiceIOProperty_OtherAudioDuckingConfiguration, kAudioUnitScope_Global, 0,
                &configuration, UInt32(MemoryLayout<AUVoiceIOOtherAudioDuckingConfiguration>.size)
            ) == noErr
            && AudioUnitInitialize(created) == noErr
            && AudioOutputUnitStart(created) == noErr

        // Nothing is reported when this fails. The mute is what the user asked
        // for and it has already happened; the ramp is a courtesy on top.
        if configured {
            duckingUnit = created
        } else {
            AudioComponentInstanceDispose(created)
        }
    }

    private func stopDucking() {
        guard let duckingUnit else { return }
        self.duckingUnit = nil
        AudioOutputUnitStop(duckingUnit)
        AudioUnitUninitialize(duckingUnit)
        AudioComponentInstanceDispose(duckingUnit)
    }

    private func excludedProcessObjectIDs() -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var processID = getpid()
        var objectID = kAudioObjectUnknown
        var byteCount = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = withUnsafePointer(to: &processID) { processIDPointer in
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                UInt32(MemoryLayout<pid_t>.size),
                processIDPointer,
                &byteCount,
                &objectID
            )
        }

        guard status == noErr, objectID != kAudioObjectUnknown else { return [] }
        return [objectID]
    }
}
