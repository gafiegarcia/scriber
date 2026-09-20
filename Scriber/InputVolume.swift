import CoreAudio
import Foundation
import SwiftUI
#if SWIFT_PACKAGE
import ScriberCore
#endif

/// Reads the input volume macOS holds for a capture device, and watches it change.
///
/// This is the setting behind System Settings' **Input volume** slider, not the
/// audio arriving from the device. The distinction is the whole point: macOS does
/// not apply a zero input volume to the built-in audio unit while that unit is
/// awake, so a dictation can receive several seconds of real, transcribable audio
/// from a microphone whose volume is zero. Sample levels lie in that window; this
/// property does not.
enum InputVolume {
    /// The device Scriber would record from for this selection, or nil when it
    /// cannot be resolved.
    ///
    /// Platform: `AVCaptureDevice.uniqueID` and Core Audio's device UID are the
    /// same string for the built-in microphone, verified on this Mac as
    /// `BuiltInMicrophoneDevice`. It is not guaranteed for every device class, so
    /// a translation that finds nothing has to mean unknown rather than zero.
    static func deviceID(for selection: AudioInputSelection) -> AudioDeviceID? {
        switch selection {
        case .automatic:
            return defaultInputDeviceID()
        case .device(let id, _):
            return translate(uid: id)
        }
    }

    static func reading(for selection: AudioInputSelection) -> InputVolumeReading {
        guard let device = deviceID(for: selection) else { return .unknown }
        return InputVolumePolicy.reading(scalar: scalar(of: device))
    }

    /// Measured: one `kAudioHardwarePropertyTranslateUIDToDevice` call, 0.006 ms.
    /// Cheap enough to take on every dictation, which is why no `AudioDeviceID` is
    /// ever stored — those are not stable across reboots or reconnects.
    private static func translate(uid: String) -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslateUIDToDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value = uid as CFString
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                UInt32(MemoryLayout<CFString>.size),
                pointer,
                &size,
                &device
            )
        }
        guard status == noErr, device != AudioDeviceID(kAudioObjectUnknown) else { return nil }
        return device
    }

    private static func defaultInputDeviceID() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device
        )
        guard status == noErr, device != AudioDeviceID(kAudioObjectUnknown) else { return nil }
        return device
    }

    /// Platform: element 0 is the master volume, which many inputs do not
    /// publish — they answer per channel instead. A device that answers on none
    /// of them has no volume for Scriber to read, which is `unknown`.
    private static func scalar(of device: AudioDeviceID) -> Float? {
        for element in volumeElements {
            var address = volumeAddress(element: element)
            guard AudioObjectHasProperty(device, &address) else { continue }
            var value = Float(0)
            var size = UInt32(MemoryLayout<Float>.size)
            if AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr {
                return value
            }
        }
        return nil
    }

    private static let volumeElements: [UInt32] = [0, 1, 2]

    private static func volumeAddress(element: UInt32) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: element
        )
    }
}

enum InputVolumeCopy {
    /// One wording, used by setup and by Settings. Halfway is where macOS puts
    /// unity gain, which is why it suits almost any device — a reason the user
    /// does not need and which is deliberately left out.
    static let recommendation = "Input volume is a macOS setting — halfway along the slider is recommended."
    static let zeroTitle = "Input volume is zero"
}

/// Watches the input volume of the device a selection names, so a view showing it
/// states the present rather than what was true when it appeared.
///
/// Nothing here opens the microphone. Reading and observing a volume is a property
/// operation, which is what lets the onboarding step know the volume is zero
/// without starting a capture session that would draw bars under a message saying
/// the volume is zero.
@MainActor
final class InputVolumeMonitor: ObservableObject {
    @Published private(set) var reading: InputVolumeReading = .unknown
    /// Called on every reading, so an owner that is not a view — the coordinator,
    /// which decides whether the microphone test may open — hears about a change
    /// without observing a nested object.
    var onChange: ((InputVolumeReading) -> Void)?

    private var selection: AudioInputSelection?
    private var observed: [(AudioDeviceID, AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    private var defaultDeviceListener: AudioObjectPropertyListenerBlock?

    func start(selection: AudioInputSelection) {
        stop()
        self.selection = selection
        refresh()
        observe(selection: selection)
    }

    func stop() {
        for (device, address, block) in observed {
            var address = address
            AudioObjectRemovePropertyListenerBlock(device, &address, nil, block)
        }
        observed = []
        if let defaultDeviceListener {
            var address = Self.defaultDeviceAddress
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject), &address, nil, defaultDeviceListener
            )
            self.defaultDeviceListener = nil
        }
        selection = nil
    }

    func refresh() {
        guard let selection else { return }
        reading = InputVolume.reading(for: selection)
        onChange?(reading)
    }

    private func observe(selection: AudioInputSelection) {
        guard let device = InputVolume.deviceID(for: selection) else { return }
        for element in Self.volumeElements {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioObjectPropertyScopeInput,
                mElement: element
            )
            guard AudioObjectHasProperty(device, &address) else { continue }
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                Task { @MainActor in self?.refresh() }
            }
            if AudioObjectAddPropertyListenerBlock(device, &address, nil, block) == noErr {
                observed.append((device, address, block))
            }
        }
        // With `.automatic` the hardware behind the selection can change without
        // any preference changing, so the device itself has to be watched as well
        // as its volume.
        guard case .automatic = selection else { return }
        var address = Self.defaultDeviceAddress
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in
                guard let self, let selection = self.selection else { return }
                self.start(selection: selection)
            }
        }
        if AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, nil, block
        ) == noErr {
            defaultDeviceListener = block
        }
    }

    private static let volumeElements: [UInt32] = [0, 1, 2]

    private static var defaultDeviceAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }
}
