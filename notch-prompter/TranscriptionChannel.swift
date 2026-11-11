import AVFoundation
import CoreMedia
import Speech

enum Speaker: String {
    case me
    case them
}

struct Utterance: Equatable {
    let speaker: Speaker
    let text: String
    /// When the speaker stopped talking, from the audio timeline. Later than
    /// this by the transcriber's finalization lag is when the text arrives.
    let endedAt: Date
}

/// On-device transcription of one audio source (mic or system audio) with its
/// own SpeechAnalyzer, emitting finalized utterances.
final class TranscriptionChannel {
    let speaker: Speaker
    let utterances: AsyncStream<Utterance>

    private let utteranceContinuation: AsyncStream<Utterance>.Continuation
    private let inputs: AsyncStream<AnalyzerInput>
    private let inputContinuation: AsyncStream<AnalyzerInput>.Continuation
    private var analyzer: SpeechAnalyzer?
    private var resultsTask: Task<Void, Never>?

    // Touched only on the audio queue that calls append(_:).
    private var analyzerFormat: AVAudioFormat?
    private var converter: AVAudioConverter?
    /// Wall-clock time of audio position zero; buffers are stamped against it
    /// so result ranges map back to when words were spoken.
    private let clockStart = Date()
    /// Where the next buffer starts, in analyzer samples. The analyzer rejects
    /// overlapping timestamps, so positions advance by sample count and only
    /// jump ahead when the clock shows a real gap in the audio.
    private var nextSample: Int64 = 0

    init(speaker: Speaker) {
        self.speaker = speaker
        (utterances, utteranceContinuation) = AsyncStream.makeStream()
        (inputs, inputContinuation) = AsyncStream.makeStream()
    }

    /// Installs the speech model if needed and starts analysing. Call before
    /// feeding audio.
    func start(locale: Locale = Locale(identifier: "en-US")) async throws {
        guard let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
            throw CaptureError("On-device transcription does not support \(locale.identifier)")
        }
        let transcriber = SpeechTranscriber(
            locale: supported, transcriptionOptions: [],
            reportingOptions: [.fastResults], attributeOptions: [.audioTimeRange])
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw CaptureError("No audio format available for transcription")
        }
        analyzerFormat = format

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzer = analyzer
        let speaker = speaker
        let clockStart = clockStart
        let continuation = utteranceContinuation
        resultsTask = Task {
            do {
                for try await result in transcriber.results {
                    let text = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { continue }
                    let end = clockStart.addingTimeInterval(result.range.end.seconds)
                    continuation.yield(Utterance(speaker: speaker, text: text, endedAt: end))
                }
            } catch {
                // Analysis ended with an error; the channel just goes quiet.
            }
        }
        try await analyzer.start(inputSequence: inputs)
    }

    /// Feeds one buffer. Safe to call from the audio thread with a buffer that
    /// is only valid during the call: it is converted into a new buffer here.
    func append(_ buffer: AVAudioPCMBuffer) {
        guard let analyzerFormat, buffer.frameLength > 0 else { return }
        if converter?.inputFormat != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: analyzerFormat)
        }
        guard let converter else { return }

        let ratio = analyzerFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
        guard let output = AVAudioPCMBuffer(pcmFormat: analyzerFormat, frameCapacity: capacity) else { return }
        var supplied = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if supplied {
                status.pointee = .noDataNow
                return nil
            }
            supplied = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, output.frameLength > 0 else { return }

        let rate = analyzerFormat.sampleRate
        let arrivedAt = Date().timeIntervalSince(clockStart)
        let clockSample = Int64((arrivedAt - Double(output.frameLength) / rate) * rate)
        if clockSample - nextSample > Int64(rate / 4) { nextSample = clockSample }
        let start = CMTime(value: nextSample, timescale: CMTimeScale(rate))
        nextSample += Int64(output.frameLength)
        inputContinuation.yield(AnalyzerInput(buffer: output, bufferStartTime: start))
    }

    func stop() async {
        inputContinuation.finish()
        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        resultsTask?.cancel()
        utteranceContinuation.finish()
    }
}
