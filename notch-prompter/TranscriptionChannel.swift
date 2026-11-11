import AVFoundation
import CoreMedia
import Speech
import os
import Accelerate

/// One log per Call Assist session stage, readable live with
/// `log stream --predicate 'subsystem == "space.waqasrana.LafzPrompter"'`.
/// Transcript text is logged as public so it shows there; the log stays on this Mac.
let callAssistLog = Logger(subsystem: "space.waqasrana.LafzPrompter", category: "CallAssist")

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
    /// Where the next buffer starts, in analyzer samples. Contiguous: the
    /// analyzer rejects overlaps and restarts recognition on any gap.
    private var nextSample: Int64 = 0
    /// Audio level over the last few seconds, logged so a silent source shows.
    private var levelPeak: Float = 0
    private var levelBuffers = 0
    private var levelSince = Date()
    /// The end of the audio fed so far and when it was fed, to map a result's
    /// audio time back to the clock. Written on the audio queue, read when a
    /// result arrives.
    private let fedUntil = OSAllocatedUnfairLock(initialState: (seconds: 0.0, at: Date()))

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
        let fedUntil = fedUntil
        let continuation = utteranceContinuation
        resultsTask = Task {
            do {
                for try await result in transcriber.results {
                    let text = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { continue }
                    // Their words ended this long before the newest audio fed.
                    let fed = fedUntil.withLock { $0 }
                    let end = fed.at.addingTimeInterval(result.range.end.seconds - fed.seconds)
                    let lag = Date().timeIntervalSince(end)
                    callAssistLog.info("transcript [\(speaker.rawValue, privacy: .public)] \(text, privacy: .public) (arrived \(lag, format: .fixed(precision: 2)) s after speech)")
                    continuation.yield(Utterance(speaker: speaker, text: text, endedAt: end))
                }
            } catch {
                callAssistLog.error("transcription [\(speaker.rawValue, privacy: .public)] stopped: \(error.localizedDescription, privacy: .public)")
            }
        }
        try await analyzer.start(inputSequence: inputs)
    }

    /// Feeds one buffer. Safe to call from the audio thread with a buffer that
    /// is only valid during the call: it is converted into a new buffer here.
    func append(_ buffer: AVAudioPCMBuffer) {
        guard let analyzerFormat, buffer.frameLength > 0 else { return }
        recordLevel(buffer)
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
        let start = CMTime(value: nextSample, timescale: CMTimeScale(rate))
        nextSample += Int64(output.frameLength)
        let fedSeconds = Double(nextSample) / rate
        fedUntil.withLock { $0 = (fedSeconds, Date()) }
        inputContinuation.yield(AnalyzerInput(buffer: output, bufferStartTime: start))
    }

    /// Logs the peak level every 5 seconds: 0 means this side hears nothing.
    private func recordLevel(_ buffer: AVAudioPCMBuffer) {
        if let samples = buffer.floatChannelData?[0] {
            let count = buffer.format.isInterleaved
                ? Int(buffer.frameLength) * Int(buffer.format.channelCount) : Int(buffer.frameLength)
            var rms: Float = 0
            vDSP_rmsqv(samples, 1, &rms, vDSP_Length(count))
            levelPeak = max(levelPeak, rms)
        }
        levelBuffers += 1
        guard Date().timeIntervalSince(levelSince) >= 5 else { return }
        callAssistLog.info("audio [\(self.speaker.rawValue, privacy: .public)] last 5 s: \(self.levelBuffers) buffers, peak level \(self.levelPeak, format: .fixed(precision: 3)) (\(buffer.format.sampleRate, format: .fixed(precision: 0)) Hz, \(buffer.format.channelCount) ch)")
        levelPeak = 0
        levelBuffers = 0
        levelSince = Date()
    }

    func stop() async {
        inputContinuation.finish()
        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        resultsTask?.cancel()
        utteranceContinuation.finish()
    }
}
