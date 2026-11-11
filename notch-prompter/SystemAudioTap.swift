import AVFoundation
import CoreAudio

/// Captures everything the Mac plays (the other side of a call) through a
/// Core Audio process tap on a private aggregate device.
final class SystemAudioTap {
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private let queue = DispatchQueue(label: "Lafz.SystemAudioTap", qos: .userInitiated)

    private(set) var format: AVAudioFormat?
    private var onBuffer: ((AVAudioPCMBuffer) -> Void)?
    private var outputListener: AudioObjectPropertyListenerBlock?
    private static let defaultOutputAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)

    /// Starts capture. `onBuffer` runs on a private queue with a buffer that is
    /// only valid during the call: convert or copy it before returning.
    /// Capture follows the default output device, so switching to a headset
    /// mid-call keeps it running.
    func start(onBuffer: @escaping (AVAudioPCMBuffer) -> Void) throws {
        stop()
        self.onBuffer = onBuffer
        try startDevice()

        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self, self.onBuffer != nil else { return }
            self.stopDevice()
            try? self.startDevice()
        }
        var address = Self.defaultOutputAddress
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, listener)
        outputListener = listener
    }

    func stop() {
        if let outputListener {
            var address = Self.defaultOutputAddress
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, outputListener)
        }
        outputListener = nil
        onBuffer = nil
        stopDevice()
    }

    private func startDevice() throws {
        guard let onBuffer else { return }
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        description.uuid = UUID()
        description.name = "Lafz Call Assist"
        description.isPrivate = true
        description.muteBehavior = .unmuted
        try check(AudioHardwareCreateProcessTap(description, &tapID), "create the system audio tap")

        var streamDescription: AudioStreamBasicDescription = try read(tapID, kAudioTapPropertyFormat)
        guard let format = AVAudioFormat(streamDescription: &streamDescription) else {
            throw CaptureError("The system audio tap reported an unusable format")
        }
        self.format = format

        let outputDevice: AudioObjectID = try read(
            AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice)
        let outputUID = try readString(outputDevice, kAudioDevicePropertyDeviceUID)

        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Lafz Call Assist Tap",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID as String,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID as String]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapDriftCompensationKey: true,
                kAudioSubTapUIDKey: description.uuid.uuidString,
            ]],
        ]
        try check(AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateID),
                  "create the capture device")

        try check(AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, queue) { _, input, _, _, _ in
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: input, deallocator: nil) else { return }
            onBuffer(buffer)
        }, "attach to the capture device")
        try check(AudioDeviceStart(aggregateID, procID), "start system audio capture")
    }

    private func stopDevice() {
        if let procID {
            AudioDeviceStop(aggregateID, procID)
            AudioDeviceDestroyIOProcID(aggregateID, procID)
        }
        procID = nil
        if aggregateID != kAudioObjectUnknown { AudioHardwareDestroyAggregateDevice(aggregateID) }
        aggregateID = AudioObjectID(kAudioObjectUnknown)
        if tapID != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tapID) }
        tapID = AudioObjectID(kAudioObjectUnknown)
    }

    deinit { stop() }

    /// CFString properties come back retained, so they are read as Unmanaged.
    private func readString(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) throws -> CFString {
        var address = AudioObjectPropertyAddress(
            mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        try check(AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value), "read audio property \(selector)")
        guard let value else { throw CaptureError("Audio property \(selector) was empty") }
        return value.takeRetainedValue()
    }

    /// Plain-value properties only (IDs, formats); see readString for strings.
    private func read<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) throws -> T {
        var address = AudioObjectPropertyAddress(
            mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<T>.size)
        let value = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<T>.alignment)
        defer { value.deallocate() }
        try check(AudioObjectGetPropertyData(object, &address, 0, nil, &size, value), "read audio property \(selector)")
        return value.load(as: T.self)
    }

    private func check(_ status: OSStatus, _ action: String) throws {
        guard status == noErr else { throw CaptureError("Could not \(action) (OSStatus \(status))") }
    }
}

struct CaptureError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
