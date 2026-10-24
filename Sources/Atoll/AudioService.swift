import AppKit
import Combine
import CoreAudio
import os

/// Output device discovery and switching via the CoreAudio HAL.
final class AudioService: ObservableObject {
    struct Device: Identifiable, Equatable {
        let id: AudioDeviceID
        let uid: String
        let name: String
        let symbol: String
    }

    @Published private(set) var outputs: [Device] = []
    @Published private(set) var currentOutputID: AudioDeviceID = 0
    @Published private(set) var currentOutputName = "No output"
    @Published private(set) var volume: Double = 0.5
    @Published private(set) var isMuted = false

    private let system = AudioObjectID(kAudioObjectSystemObject)
    private var started = false
    private var isApplyingVolume = false
    private var lastVolumeBeforeMute: Double = 0.5

    // MARK: - Lifecycle

    func start() {
        guard !started else { return }
        started = true
        installListeners()
        refresh()
    }

    func refresh() {
        let ids = allDeviceIDs()
        let current = defaultOutputID()

        var found: [Device] = []
        for id in ids where hasOutput(id) {
            guard let name = stringProperty(id, kAudioObjectPropertyName) else { continue }
            let uid = stringProperty(id, kAudioDevicePropertyDeviceUID) ?? "\(id)"
            let transport = uint32Property(id, kAudioDevicePropertyTransportType) ?? 0
            found.append(Device(id: id, uid: uid, name: name, symbol: symbol(for: transport)))
        }

        outputs = found
        currentOutputID = current
        currentOutputName = found.first(where: { $0.id == current })?.name ?? "No output"
        refreshVolume()
        print("audio: \(found.count) outputs [\(found.map(\.name).joined(separator: ", "))] current=\(currentOutputName)")
        Logger.app.info("audio: \(found.count, privacy: .public) outputs current=\(self.currentOutputName, privacy: .public)")
    }

    // MARK: - Switching

    func setOutput(_ device: Device) {
        var id = device.id
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectSetPropertyData(
            system,
            &address,
            0,
            nil,
            UInt32(MemoryLayout<AudioDeviceID>.size),
            &id
        )
        if status == noErr {
            refresh()
            print("audio: switched output to \(device.name)")
        } else {
            print("audio: failed to switch output (\(status))")
        }
    }

    // MARK: - Volume

    func setVolume(_ value: Double) {
        guard currentOutputID != 0 else { return }
        isApplyingVolume = true
        volume = min(max(value, 0), 1)

        let scalar = Float32(volume)
        let applied = setScalar(currentOutputID, scalar, element: kAudioObjectPropertyElementMain)
            || setScalar(currentOutputID, scalar, element: 1)
            || setScalar(currentOutputID, scalar, element: 2)

        if !applied {
            print("audio: volume not settable on this device")
        }
        isApplyingVolume = false
    }

    func adjustVolume(by delta: Double) -> Double {
        if isMuted {
            setMuted(false)
        }
        let next = min(max(volume + delta, 0), 1)
        setVolume(next)
        return next
    }

    @discardableResult
    func toggleMute() -> Bool {
        setMuted(!isMuted)
        return isMuted
    }

    func setMuted(_ muted: Bool) {
        guard currentOutputID != 0 else { return }

        if muted {
            lastVolumeBeforeMute = max(volume, 0.1)
        }

        let value: UInt32 = muted ? 1 : 0
        let applied = setMuteScalar(currentOutputID, value, element: kAudioObjectPropertyElementMain)
            || setMuteScalar(currentOutputID, value, element: 1)
            || setMuteScalar(currentOutputID, value, element: 2)

        if applied {
            isMuted = muted
            return
        }

        // Devices without a mute control: emulate it with volume.
        if muted {
            isMuted = true
            setVolume(0)
        } else {
            isMuted = false
            setVolume(max(lastVolumeBeforeMute, 0.1))
        }
    }

    private func refreshVolume() {
        guard !isApplyingVolume, currentOutputID != 0 else { return }
        if let scalar = volumeScalar(currentOutputID, element: kAudioObjectPropertyElementMain)
            ?? volumeScalar(currentOutputID, element: 1)
            ?? volumeScalar(currentOutputID, element: 2) {
            volume = Double(scalar)
        }
        if let muted = muteScalar(currentOutputID, element: kAudioObjectPropertyElementMain)
            ?? muteScalar(currentOutputID, element: 1)
            ?? muteScalar(currentOutputID, element: 2) {
            isMuted = muted != 0
        }
    }

    // MARK: - HAL helpers

    private func allDeviceIDs() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else {
            return []
        }
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else {
            return []
        }
        return ids
    }

    private func defaultOutputID() -> AudioDeviceID {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &id) == noErr else {
            return 0
        }
        return id
    }

    private func hasOutput(_ id: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr else {
            return false
        }
        return size > 0
    }

    private func stringProperty(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr,
              let value else {
            return nil
        }
        return value.takeRetainedValue() as String
    }

    private func uint32Property(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else {
            return nil
        }
        return value
    }

    private func volumeAddress(element: AudioObjectPropertyElement) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: element
        )
    }

    private func volumeScalar(_ id: AudioObjectID, element: AudioObjectPropertyElement) -> Float32? {
        var address = volumeAddress(element: element)
        guard AudioObjectHasProperty(id, &address) else { return nil }
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else {
            return nil
        }
        return value
    }

    private func setScalar(_ id: AudioObjectID, _ value: Float32, element: AudioObjectPropertyElement) -> Bool {
        var address = volumeAddress(element: element)
        guard AudioObjectHasProperty(id, &address) else { return false }
        var scalar = value
        return AudioObjectSetPropertyData(
            id,
            &address,
            0,
            nil,
            UInt32(MemoryLayout<Float32>.size),
            &scalar
        ) == noErr
    }

    private func muteAddress(element: AudioObjectPropertyElement) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: element
        )
    }

    private func muteScalar(_ id: AudioObjectID, element: AudioObjectPropertyElement) -> UInt32? {
        var address = muteAddress(element: element)
        guard AudioObjectHasProperty(id, &address) else { return nil }
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else {
            return nil
        }
        return value
    }

    private func setMuteScalar(_ id: AudioObjectID, _ value: UInt32, element: AudioObjectPropertyElement) -> Bool {
        var address = muteAddress(element: element)
        guard AudioObjectHasProperty(id, &address) else { return false }
        var scalar = value
        return AudioObjectSetPropertyData(
            id,
            &address,
            0,
            nil,
            UInt32(MemoryLayout<UInt32>.size),
            &scalar
        ) == noErr
    }

    private func symbol(for transport: UInt32) -> String {
        switch transport {
        case kAudioDeviceTransportTypeBuiltIn:
            return "laptopcomputer"
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE:
            return "airpods"
        case kAudioDeviceTransportTypeUSB:
            return "cable.connector"
        case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort:
            return "display"
        case kAudioDeviceTransportTypeAirPlay:
            return "airplayaudio"
        case kAudioDeviceTransportTypeVirtual:
            return "waveform"
        case kAudioDeviceTransportTypeAggregate:
            return "square.stack.3d.up"
        default:
            return "hifispeaker.fill"
        }
    }

    private func installListeners() {
        var defaultAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(system, &defaultAddress, DispatchQueue.main) { [weak self] _, _ in
            self?.refresh()
        }

        var devicesAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(system, &devicesAddress, DispatchQueue.main) { [weak self] _, _ in
            self?.refresh()
        }
    }
}
