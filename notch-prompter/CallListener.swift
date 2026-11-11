import AVFoundation

/// Listens to both sides of a call: the mic is "me", everything the Mac plays
/// is "them". Each side has its own transcription channel, merged into one
/// stream of finalized utterances.
final class CallListener {
    let utterances: AsyncStream<Utterance>

    private let continuation: AsyncStream<Utterance>.Continuation
    private let mic = TranscriptionChannel(speaker: .me)
    private let system = TranscriptionChannel(speaker: .them)
    private let engine = AVAudioEngine()
    private let tap = SystemAudioTap()
    private var forwardTasks: [Task<Void, Never>] = []

    init() {
        (utterances, continuation) = AsyncStream.makeStream()
    }

    /// Starts both channels, then the audio. Throws if either side cannot
    /// start; nothing is left running in that case.
    func start() async throws {
        do {
            // SpeechAnalyzer.start returns once analysis is running.
            async let micReady: Void = mic.start()
            async let systemReady: Void = system.start()
            _ = try await (micReady, systemReady)

            for channel in [mic, system] {
                let continuation = continuation
                forwardTasks.append(Task {
                    for await utterance in channel.utterances { continuation.yield(utterance) }
                })
            }

            let input = engine.inputNode
            let mic = mic
            input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in
                mic.append(buffer)
            }
            try engine.start()

            let system = system
            try tap.start { buffer in system.append(buffer) }
        } catch {
            await stop()
            throw error
        }
    }

    func stop() async {
        tap.stop()
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        await mic.stop()
        await system.stop()
        forwardTasks.forEach { $0.cancel() }
        continuation.finish()
    }
}
