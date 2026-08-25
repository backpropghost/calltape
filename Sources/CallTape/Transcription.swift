import Foundation
import Combine
import Speech
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Tracks in-progress transcriptions so both the list and the detail pane can show
/// state, and so the same recording isn't transcribed twice at once.
@MainActor
final class TranscriptionManager: ObservableObject {
    static let shared = TranscriptionManager()
    @Published private(set) var active: Set<URL> = []   // running now (one at a time)
    @Published private(set) var queued: Set<URL> = []   // waiting their turn
    @Published var lastError: String?
    private var order: [URL] = []
    private init() {}

    /// True if this recording is transcribing now or waiting in the queue.
    func isActive(_ url: URL) -> Bool { active.contains(url) || queued.contains(url) }

    func transcribe(_ url: URL) { enqueue([url]) }
    func transcribeAll(_ urls: [URL]) { enqueue(urls) }

    private func enqueue(_ urls: [URL]) {
        for u in urls where !active.contains(u) && !queued.contains(u) {
            queued.insert(u); order.append(u)
        }
        lastError = nil
        pump()
    }

    private func pump() {
        guard active.isEmpty, !order.isEmpty else { return }   // serial: one at a time
        let url = order.removeFirst()
        queued.remove(url)
        runOne(url)
    }

    private func runOne(_ url: URL) {
        func done() { active.remove(url); pump() }
        func begin() {
            active.insert(url)
            Transcription.transcribe(url: url) { [weak self] result in
                guard let self else { return }
                switch result {
                case .failure(let error):
                    self.lastError = error.localizedDescription; done()
                case .success(let data) where data.text.isEmpty:
                    self.lastError = "No speech was detected in this recording."; done()
                case .success(let data):
                    Transcription.summarize(data.text) { summary in
                        var fields: [String: Any] = ["transcript": data.text, "segments": data.segments]
                        if let summary { fields["summary"] = summary }
                        RecordingsStore.shared.updateSidecar(url: url, adding: fields)
                        done()
                    }
                }
            }
        }
        // macOS 26's SpeechAnalyzer runs entirely on-device and needs no speech
        // authorization, so we skip the legacy prompt (which wrongly warns that
        // "speech data will be sent to Apple"). Older macOS still needs it.
        if #available(macOS 26, *) {
            begin()
        } else if Transcription.isAuthorized {
            begin()
        } else {
            Transcription.requestAuthorization { ok in
                if ok { begin() }
                else { self.lastError = Transcription.TranscribeError.notAuthorized.localizedDescription; done() }
            }
        }
    }
}

/// On-device speech-to-text (Apple's Speech framework) plus an optional on-device
/// summary (Apple Intelligence via Foundation Models, macOS 26+). Nothing leaves the
/// Mac: recognition is forced on-device and the language model runs locally.
enum Transcription {

    enum TranscribeError: LocalizedError {
        case unavailable, notAuthorized, failed(String)
        var errorDescription: String? {
            switch self {
            case .unavailable: return "Speech recognition isn't available on this Mac."
            case .notAuthorized: return "Allow Speech Recognition in System Settings to transcribe."
            case .failed(let m): return m
            }
        }
    }

    static var isAuthorized: Bool { SFSpeechRecognizer.authorizationStatus() == .authorized }

    static func requestAuthorization(_ completion: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async { completion(status == .authorized) }
        }
    }

    /// Whether an on-device summary is possible on this Mac right now.
    static var canSummarize: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) { return SystemLanguageModel.default.availability == .available }
        #endif
        return false
    }

    /// The full text plus timestamped lines (for timed-subtitle display).
    struct TranscriptData { let text: String; let segments: [[String: Any]] }

    /// Transcribe an audio file fully on-device. Uses SpeechAnalyzer on macOS 26
    /// (handles long recordings), else falls back to SFSpeechRecognizer.
    static func transcribe(url: URL, completion: @escaping (Result<TranscriptData, Error>) -> Void) {
        if #available(macOS 26, *) {
            Task {
                do {
                    let result = try await transcribeLongForm(url: url)
                    DispatchQueue.main.async { completion(.success(result)) }
                } catch {
                    DispatchQueue.main.async { completion(.failure(error)) }
                }
            }
        } else {
            transcribeLegacy(url: url, completion: completion)
        }
    }

    /// macOS 26+: SpeechAnalyzer/SpeechTranscriber — built for long-form audio.
    @available(macOS 26, *)
    private static func transcribeLongForm(url: URL) async throws -> TranscriptData {
        let requested = Locale.current
        let matched = await SpeechTranscriber.supportedLocale(equivalentTo: requested)
        let fallback = await SpeechTranscriber.supportedLocales.first
        guard let locale = matched ?? fallback else {
            throw TranscribeError.unavailable
        }

        let transcriber = SpeechTranscriber(locale: locale,
                                            transcriptionOptions: [],
                                            reportingOptions: [],
                                            attributeOptions: [.audioTimeRange])

        // Make sure the on-device model for this language is installed.
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let audioFile = try AVAudioFile(forReading: url)

        var lines: [[String: Any]] = []
        var full = ""

        // Collect results (each is a finalized phrase with a time range) concurrently.
        let collector = Task {
            for try await result in transcriber.results {   // finalized phrases with time ranges
                let attributed = result.text
                let text = String(attributed.characters).trimmingCharacters(in: .whitespaces)
                guard !text.isEmpty else { continue }
                var start = 0.0
                for run in attributed.runs {
                    if let range = run.audioTimeRange { start = range.start.seconds; break }
                }
                full += text + " "
                lines.append(["t": start, "text": text])
            }
        }

        defer { collector.cancel() }   // don't leak the results task if analysis throws
        if let last = try await analyzer.analyzeSequence(from: audioFile) {
            try await analyzer.finalizeAndFinish(through: last)
        } else {
            await analyzer.cancelAndFinishNow()
        }
        try await collector.value

        return TranscriptData(text: full.trimmingCharacters(in: .whitespacesAndNewlines), segments: lines)
    }

    /// Older macOS: SFSpeechRecognizer (note: reliable only for shorter recordings).
    private static func transcribeLegacy(url: URL, completion: @escaping (Result<TranscriptData, Error>) -> Void) {
        func finish(_ r: Result<TranscriptData, Error>) { DispatchQueue.main.async { completion(r) } }

        guard let recognizer = SFSpeechRecognizer(locale: Locale.current) ?? SFSpeechRecognizer() else {
            finish(.failure(TranscribeError.unavailable)); return
        }
        guard recognizer.isAvailable else { finish(.failure(TranscribeError.unavailable)); return }
        guard recognizer.supportsOnDeviceRecognition else {
            finish(.failure(TranscribeError.failed("On-device transcription isn't supported for this language.")))
            return
        }

        let request = SFSpeechURLRecognitionRequest(url: url)
        request.requiresOnDeviceRecognition = true   // never send audio to a server
        request.shouldReportPartialResults = false

        recognizer.recognitionTask(with: request) { result, error in
            if let error {
                finish(.failure(TranscribeError.failed(error.localizedDescription))); return
            }
            guard let result, result.isFinal else { return }
            let transcription = result.bestTranscription
            let text = transcription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
            let segments = groupIntoLines(transcription.segments)
            finish(.success(TranscriptData(text: text, segments: segments)))
        }
    }

    /// Group word-level segments into readable, timestamped lines (like subtitles).
    private static func groupIntoLines(_ segments: [SFTranscriptionSegment]) -> [[String: Any]] {
        var lines: [[String: Any]] = []
        var current = ""
        var start: Double = 0
        var lastEnd: Double = 0

        for seg in segments {
            let word = seg.substring
            if current.isEmpty { start = seg.timestamp }
            let gap = seg.timestamp - lastEnd
            // Break on a noticeable pause or once a line gets long.
            if !current.isEmpty && (gap > 1.1 || current.count > 90) {
                lines.append(["t": start, "text": current.trimmingCharacters(in: .whitespaces)])
                current = ""; start = seg.timestamp
            }
            current += word + " "
            lastEnd = seg.timestamp + seg.duration
        }
        if !current.isEmpty {
            lines.append(["t": start, "text": current.trimmingCharacters(in: .whitespaces)])
        }
        return lines
    }

    /// Summarize a transcript on-device. Returns nil if Apple Intelligence is unavailable.
    static func summarize(_ transcript: String, completion: @escaping (String?) -> Void) {
        #if canImport(FoundationModels)
        if #available(macOS 26, *), SystemLanguageModel.default.availability == .available {
            Task {
                let text: String?
                do {
                    let session = LanguageModelSession(instructions:
                        "You summarize phone-call transcripts. Be concise and neutral.")
                    let prompt = """
                    Summarize this call in 2 short sentences. Then, if there are any, list action items as short bullet points starting with "- ". If there are none, omit the list.

                    Transcript:
                    \(transcript)
                    """
                    let response = try await session.respond(to: prompt)
                    text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
                } catch {
                    text = nil
                }
                let final = text
                DispatchQueue.main.async { completion(final) }
            }
            return
        }
        #endif
        DispatchQueue.main.async { completion(nil) }
    }
}
