import AudioToolbox
import CoreAudio
import Foundation

/// The result of asking the service to quiet other apps.
///
/// An unavailable result is intentionally non-fatal: microphone dictation can continue
/// without changing other apps' audio.
enum OtherAudioMutingOutcome: Equatable, Sendable {
    case muted
    case alreadyMuted
    case unavailable(OSStatus)
}

/// The result of asking the service to give other apps their audio back.
enum OtherAudioUnmutingOutcome: Equatable, Sendable {
    case restored
    case alreadyRestored
    case unavailable(OSStatus)
}

/// A mute that fails to start says nothing: the audio carries on playing, which
/// the user can hear, and nothing needs saying about a fact they are listening
/// to. A mute that fails to *end* is the opposite — a Mac that stays quiet for
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

/// A small boundary around the system-wide, temporary audio quieting behavior.
///
/// Keeping this protocol independent of recording makes lifecycle behavior testable without
/// touching Core Audio.
@MainActor
protocol OtherAudioMuting: AnyObject {
    @discardableResult
    func beginMuting() -> OtherAudioMutingOutcome

    @discardableResult
    func endMuting() -> OtherAudioUnmutingOutcome
}

/// Quiets everything that is not voice, for as long as a dictation runs.
///
/// This is Apple's own voice-chat ducking, the same mechanism behind the level
/// ramp macOS's dictation has: `kAUVoiceIOProperty_OtherAudioDuckingConfiguration`
/// on a voice processing unit. Two things follow from that choice, and both are
/// the reason for it.
///
/// It needs no System Audio Recording grant. A process tap can mute, but every
/// tap description delivers audio too, so using one meant asking for a
/// permission whose entire subject — the audio itself — Scriber discarded
/// unread. Nothing here can reach another app's samples, so nothing has to be
/// asked, explained, or reassured about.
///
/// And it ramps. Ducking fades other audio down over about a second and back up
/// on the way out, where a tap could only switch between silent and not.
@MainActor
final class OtherAudioMuteService: OtherAudioMuting {
    private var unit: AudioUnit?

    isolated deinit {
        endMuting()
    }

    @discardableResult
    func beginMuting() -> OtherAudioMutingOutcome {
        if unit != nil { return .alreadyMuted }

        var description = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_VoiceProcessingIO,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        guard let component = AudioComponentFindNext(nil, &description) else {
            return .unavailable(kAudioHardwareUnspecifiedError)
        }

        var created: AudioUnit?
        let instantiateStatus = AudioComponentInstanceNew(component, &created)
        guard instantiateStatus == noErr, let created else {
            return .unavailable(instantiateStatus == noErr ? kAudioHardwareUnspecifiedError : instantiateStatus)
        }

        // Ducking belongs to the voice side of the unit, so input has to be on
        // even though nothing here reads a single sample from it.
        var enableInput: UInt32 = 1
        let enableStatus = AudioUnitSetProperty(
            created, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1,
            &enableInput, UInt32(MemoryLayout<UInt32>.size)
        )
        guard enableStatus == noErr else {
            AudioComponentInstanceDispose(created)
            return .unavailable(enableStatus)
        }

        var configuration = AUVoiceIOOtherAudioDuckingConfiguration(
            mEnableAdvancedDucking: false,
            mDuckingLevel: AUVoiceIOOtherAudioDuckingLevel.max
        )
        let configureStatus = AudioUnitSetProperty(
            created, kAUVoiceIOProperty_OtherAudioDuckingConfiguration, kAudioUnitScope_Global, 0,
            &configuration, UInt32(MemoryLayout<AUVoiceIOOtherAudioDuckingConfiguration>.size)
        )
        guard configureStatus == noErr else {
            AudioComponentInstanceDispose(created)
            return .unavailable(configureStatus)
        }

        let initializeStatus = AudioUnitInitialize(created)
        guard initializeStatus == noErr else {
            AudioComponentInstanceDispose(created)
            return .unavailable(initializeStatus)
        }

        let startStatus = AudioOutputUnitStart(created)
        guard startStatus == noErr else {
            AudioUnitUninitialize(created)
            AudioComponentInstanceDispose(created)
            return .unavailable(startStatus)
        }

        unit = created
        return .muted
    }

    @discardableResult
    func endMuting() -> OtherAudioUnmutingOutcome {
        guard let unit else { return .alreadyRestored }
        self.unit = nil

        var firstFailure: OSStatus?
        let stopStatus = AudioOutputUnitStop(unit)
        if stopStatus != noErr { firstFailure = stopStatus }
        let uninitializeStatus = AudioUnitUninitialize(unit)
        if uninitializeStatus != noErr { firstFailure = firstFailure ?? uninitializeStatus }
        let disposeStatus = AudioComponentInstanceDispose(unit)
        if disposeStatus != noErr { firstFailure = firstFailure ?? disposeStatus }

        if let firstFailure { return .unavailable(firstFailure) }
        return .restored
    }
}
