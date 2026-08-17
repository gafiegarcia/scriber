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

enum OtherAudioMuteStatus: Equatable, Sendable {
    case unavailableToStart
    case unableToRestore

    var message: String {
        switch self {
        case .unavailableToStart:
            "Other app audio could not be muted. Dictation will continue normally. Review System Audio Recording access in Privacy & Security."
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

    deinit {
        if let aggregateDeviceID, let ioProcID {
            AudioDeviceStop(aggregateDeviceID, ioProcID)
            AudioDeviceDestroyIOProcID(aggregateDeviceID, ioProcID)
        }
        if let aggregateDeviceID { AudioHardwareDestroyAggregateDevice(aggregateDeviceID) }
        if let tapID { AudioHardwareDestroyProcessTap(tapID) }
    }

    /// Raises the System Audio Recording prompt, by attempting the one thing
    /// that needs it.
    ///
    /// Core Audio ships no preflight for process taps — creating one is what
    /// asks — so this creates a tap and destroys it again without ever driving
    /// it, which mutes nothing. Deliberately outside the actor and touching no
    /// stored state: macOS blocks the caller while its prompt is on screen, and
    /// on the main thread that is a beachball.
    nonisolated static func requestAccess() -> OSStatus {
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        description.name = "Scriber audio access check"
        description.isPrivate = true
        description.muteBehavior = CATapMuteBehavior.unmuted

        var probeTapID = AudioObjectID(kAudioObjectUnknown)
        let status = AudioHardwareCreateProcessTap(description, &probeTapID)
        if probeTapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(probeTapID)
        }
        return status
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

        if let firstFailure { return .unavailable(firstFailure) }
        return .restored
    }

    /// Whether sound is currently going out over Bluetooth, which is the only
    /// case that needs the settle delay.
    nonisolated static func outputIsBluetooth() -> Bool {
        var deviceAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioObjectID(kAudioObjectUnknown)
        var deviceSize = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &deviceAddress, 0, nil, &deviceSize, &deviceID
        ) == noErr, deviceID != kAudioObjectUnknown else { return false }

        var transportAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var transport = UInt32(0)
        var transportSize = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(
            deviceID, &transportAddress, 0, nil, &transportSize, &transport
        ) == noErr else { return false }

        return transport == kAudioDeviceTransportTypeBluetooth
            || transport == kAudioDeviceTransportTypeBluetoothLE
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
