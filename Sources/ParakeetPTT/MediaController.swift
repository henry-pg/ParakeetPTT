import CoreAudio
import Foundation

enum MediaController {
    struct MuteToken {
        fileprivate let deviceStates: [DeviceMuteState]

        var isMuting: Bool {
            !deviceStates.isEmpty
        }
    }

    fileprivate struct DeviceMuteState {
        let deviceID: AudioObjectID
        let previousMute: UInt32?
        let previousVolumes: [VolumeState]
    }

    fileprivate struct VolumeState {
        let element: AudioObjectPropertyElement
        let value: Float32
    }

    @discardableResult
    static func muteSystemAudioForRecording() -> MuteToken {
        let states = defaultOutputDeviceIDs().compactMap { deviceID -> DeviceMuteState? in
            let previousMute = readMute(deviceID)
            let previousVolumes = readVolumeStates(deviceID)
            var changedAudioState = false

            if writeMute(true, deviceID: deviceID) {
                changedAudioState = true
            }

            if writeVolumes(0, deviceID: deviceID, elements: previousVolumes.map(\.element)) {
                changedAudioState = true
            }

            guard changedAudioState else {
                NSLog("ParakeetPTT could not mute output device \(deviceID)")
                return nil
            }

            return DeviceMuteState(
                deviceID: deviceID,
                previousMute: previousMute,
                previousVolumes: previousVolumes
            )
        }

        if states.isEmpty {
            NSLog("ParakeetPTT did not find a mutable output device")
        } else {
            NSLog("ParakeetPTT muted \(states.count) output device(s) for recording")
        }

        return MuteToken(deviceStates: states)
    }

    static func unmuteSystemAudioAfterRecording(_ token: MuteToken) {
        for state in token.deviceStates {
            restoreVolumes(state.previousVolumes, deviceID: state.deviceID)

            if let previousMute = state.previousMute {
                _ = writeMute(previousMute != 0, deviceID: state.deviceID)
            } else if state.previousVolumes.isEmpty {
                _ = writeMute(false, deviceID: state.deviceID)
            }
        }

        if !token.deviceStates.isEmpty {
            NSLog("ParakeetPTT restored output audio after recording")
        }
    }

    private static func defaultOutputDeviceIDs() -> [AudioObjectID] {
        let candidates = [
            defaultOutputDeviceID(kAudioHardwarePropertyDefaultOutputDevice),
            defaultOutputDeviceID(kAudioHardwarePropertyDefaultSystemOutputDevice)
        ]

        var seen = Set<AudioObjectID>()
        return candidates.compactMap { deviceID -> AudioObjectID? in
            guard let deviceID, deviceID != kAudioObjectUnknown, !seen.contains(deviceID) else {
                return nil
            }

            seen.insert(deviceID)
            return deviceID
        }
    }

    private static func defaultOutputDeviceID(_ selector: AudioObjectPropertySelector) -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )

        guard status == noErr else {
            NSLog("ParakeetPTT could not read default output device \(selector): \(status)")
            return nil
        }

        return deviceID
    }

    private static func readMute(_ deviceID: AudioObjectID) -> UInt32? {
        var address = audioDeviceAddress(
            selector: kAudioDevicePropertyMute,
            element: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(deviceID, &address) else { return nil }

        var value = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value)
        guard status == noErr else {
            NSLog("ParakeetPTT could not read output mute state for device \(deviceID): \(status)")
            return nil
        }

        return value
    }

    private static func writeMute(_ muted: Bool, deviceID: AudioObjectID) -> Bool {
        var address = audioDeviceAddress(
            selector: kAudioDevicePropertyMute,
            element: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(deviceID, &address) else { return false }

        var value = UInt32(muted ? 1 : 0)
        let size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &value)
        if status != noErr {
            NSLog("ParakeetPTT could not write output mute=\(muted) for device \(deviceID): \(status)")
        }

        return status == noErr
    }

    private static func readVolumeStates(_ deviceID: AudioObjectID) -> [VolumeState] {
        outputVolumeElements(deviceID).compactMap { element in
            var address = audioDeviceAddress(
                selector: kAudioDevicePropertyVolumeScalar,
                element: element
            )
            guard AudioObjectHasProperty(deviceID, &address) else { return nil }

            var value = Float32(0)
            var size = UInt32(MemoryLayout<Float32>.size)
            let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value)
            guard status == noErr else {
                NSLog("ParakeetPTT could not read output volume element \(element) for device \(deviceID): \(status)")
                return nil
            }

            return VolumeState(element: element, value: value)
        }
    }

    private static func writeVolumes(
        _ value: Float32,
        deviceID: AudioObjectID,
        elements: [AudioObjectPropertyElement]
    ) -> Bool {
        var wroteAtLeastOneElement = false

        for element in elements {
            var address = audioDeviceAddress(
                selector: kAudioDevicePropertyVolumeScalar,
                element: element
            )
            guard AudioObjectHasProperty(deviceID, &address) else { continue }

            var volume = value
            let size = UInt32(MemoryLayout<Float32>.size)
            let status = AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &volume)
            if status == noErr {
                wroteAtLeastOneElement = true
            } else {
                NSLog("ParakeetPTT could not write output volume element \(element) for device \(deviceID): \(status)")
            }
        }

        return wroteAtLeastOneElement
    }

    private static func restoreVolumes(_ volumes: [VolumeState], deviceID: AudioObjectID) {
        for volumeState in volumes {
            var address = audioDeviceAddress(
                selector: kAudioDevicePropertyVolumeScalar,
                element: volumeState.element
            )
            guard AudioObjectHasProperty(deviceID, &address) else { continue }

            var volume = volumeState.value
            let size = UInt32(MemoryLayout<Float32>.size)
            let status = AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &volume)
            if status != noErr {
                NSLog("ParakeetPTT could not restore output volume element \(volumeState.element) for device \(deviceID): \(status)")
            }
        }
    }

    private static func outputVolumeElements(_ deviceID: AudioObjectID) -> [AudioObjectPropertyElement] {
        let channelCount = outputChannelCount(deviceID)
        var elements = [kAudioObjectPropertyElementMain]

        if channelCount > 0 {
            elements.append(contentsOf: (1...channelCount).map(AudioObjectPropertyElement.init))
        }

        return elements
    }

    private static func outputChannelCount(_ deviceID: AudioObjectID) -> Int {
        var address = audioDeviceAddress(
            selector: kAudioDevicePropertyStreamConfiguration,
            element: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        let sizeStatus = AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size)
        guard sizeStatus == noErr, size > 0 else {
            return 2
        }

        let buffer = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { buffer.deallocate() }

        let dataStatus = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, buffer)
        guard dataStatus == noErr else {
            return 2
        }

        let audioBufferList = buffer.assumingMemoryBound(to: AudioBufferList.self)
        return UnsafeMutableAudioBufferListPointer(audioBufferList).reduce(0) { count, audioBuffer in
            count + Int(audioBuffer.mNumberChannels)
        }
    }

    private static func audioDeviceAddress(
        selector: AudioObjectPropertySelector,
        element: AudioObjectPropertyElement
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: element
        )
    }
}
