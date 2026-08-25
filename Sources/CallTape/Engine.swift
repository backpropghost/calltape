import Foundation
import CoreAudio
import AudioToolbox
import AVFoundation
import Combine

// MARK: - Core Audio helpers

private let systemObject = AudioObjectID(kAudioObjectSystemObject)

private func audioProcessList() -> [AudioObjectID] {
    var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList,
                                             mScope: kAudioObjectPropertyScopeGlobal,
                                             mElement: kAudioObjectPropertyElementMain)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(systemObject, &address, 0, nil, &size) == noErr else { return [] }
    let count = Int(size) / MemoryLayout<AudioObjectID>.size
    var ids = [AudioObjectID](repeating: 0, count: count)
    guard AudioObjectGetPropertyData(systemObject, &address, 0, nil, &size, &ids) == noErr else { return [] }
    return ids
}

private func stringProperty(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
    var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                             mElement: kAudioObjectPropertyElementMain)
    guard AudioObjectHasProperty(object, &address) else { return nil }
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr else { return nil }
    var value: CFString?
    let status = withUnsafeMutablePointer(to: &value) {
        AudioObjectGetPropertyData(object, &address, 0, nil, &size, $0)
    }
    return status == noErr ? value as String? : nil
}

private func boolProperty(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> Bool {
    var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                             mElement: kAudioObjectPropertyElementMain)
    guard AudioObjectHasProperty(object, &address) else { return false }
    var value: UInt32 = 0
    var size = UInt32(MemoryLayout<UInt32>.size)
    guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return false }
    return value != 0
}

/// The first call app (from `bundles`) that currently has both mic and speaker live,
/// which means an actual two-way call is in progress.
private func activeCallProcess(matching bundles: Set<String>) -> (id: AudioObjectID, bundle: String)? {
    for process in audioProcessList() {
        guard let bundle = stringProperty(process, kAudioProcessPropertyBundleID),
              bundles.contains(bundle) else { continue }
        if boolProperty(process, kAudioProcessPropertyIsRunningInput),
           boolProperty(process, kAudioProcessPropertyIsRunningOutput) {
            return (process, bundle)
        }
    }
    return nil
}

/// Turn an OSStatus into its readable four-char code, e.g. 'nope'.
private func describe(_ status: OSStatus) -> String {
    let value = UInt32(bitPattern: status)
    let bytes = [UInt8(value >> 24 & 0xff), UInt8(value >> 16 & 0xff),
                 UInt8(value >> 8 & 0xff), UInt8(value & 0xff)]
    if bytes.allSatisfy({ $0 >= 32 && $0 < 127 }), let code = String(bytes: bytes, encoding: .ascii) {
        return "'\(code)' (\(status))"
    }
    return "\(status)"
}

// MARK: - Mic sample FIFO

/// Holds mic samples produced by AVAudioEngine until the tap callback consumes them.
private final class MicBuffer {
    private var samples = [Float]()
    private let lock = NSLock()
    private let cap = 480_000 // ~10s at 48k

    func append(_ new: UnsafeBufferPointer<Float>) {
        lock.lock(); defer { lock.unlock() }
        samples.append(contentsOf: new)
        if samples.count > cap { samples.removeFirst(samples.count - cap) }
    }

    /// Exactly `count` samples, padded with silence if the mic is running behind.
    func take(_ count: Int) -> [Float] {
        lock.lock(); defer { lock.unlock() }
        if samples.count >= count {
            let out = Array(samples[0..<count]); samples.removeFirst(count); return out
        }
        var out = samples; samples.removeAll(keepingCapacity: true)
        out.append(contentsOf: repeatElement(0, count: count - out.count))
        return out
    }
}

// MARK: - Recording session

/// What the tap listens to: one app's audio (a call) or the whole system (a manual
/// recording of, say, a browser meeting).
enum TapSource {
    case process(AudioObjectID)
    case system
}

/// Records one call: remote party via a process tap, your voice via the mic, mixed
/// into a single mono AAC file. The mic is captured with AVAudioEngine (which shares
/// the input device), so Bluetooth headsets work even while the call holds them.
final class CallSession {
    private var tap: AudioObjectID = 0
    private var aggregate: AudioDeviceID = 0
    private var ioProc: AudioDeviceIOProcID?
    private var file: AVAudioFile?
    private var outputFormat: AVAudioFormat?
    private var running = false

    private let engine = AVAudioEngine()
    private let mic = MicBuffer()
    private var converter: AVAudioConverter?
    private var micRunning = false

    private let micGain: Float
    private let remoteGain: Float

    // Speaker timeline: per-window we compare your mic energy vs the other party's,
    // so the transcript can be labeled "You" vs the caller without needing stereo.
    private var sampleRateHz: Double = 48000
    private var winMineE: Float = 0
    private var winRemoteE: Float = 0
    private var winFrames = 0
    private var windowIndex = 0
    private var lastWho = ""
    private var timeline: [[String: Any]] = []
    func speakerTimeline() -> [[String: Any]] { timeline }

    init() {
        micGain = Float(AppSettings.shared.micGain)
        remoteGain = Float(AppSettings.shared.remoteGain)
    }

    func start(source: TapSource, outputURL: URL) throws {
        // 1) Mono tap of the source audio, in its own private aggregate device.
        let description: CATapDescription
        switch source {
        case .process(let pid): description = CATapDescription(monoMixdownOfProcesses: [pid])
        case .system: description = CATapDescription(monoGlobalTapButExcludeProcesses: [])
        }
        description.name = "CallTapeTap"
        description.isPrivate = true
        description.muteBehavior = .unmuted
        try check(AudioHardwareCreateProcessTap(description, &tap), "create tap")

        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey as String: "CallTape Tap",
            kAudioAggregateDeviceUIDKey as String: "com.calltape.tap",
            kAudioAggregateDeviceIsPrivateKey as String: true,
            kAudioAggregateDeviceIsStackedKey as String: false,
            kAudioAggregateDeviceTapListKey as String: [
                [kAudioSubTapUIDKey as String: description.uuid.uuidString]
            ]
        ]
        try check(AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &aggregate), "create aggregate")

        // 2) The tap's sample rate defines our mono output format.
        var asbd = AudioStreamBasicDescription()
        var formatAddress = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamFormat,
                                                       mScope: kAudioObjectPropertyScopeInput, mElement: 0)
        var formatSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        try check(AudioObjectGetPropertyData(aggregate, &formatAddress, 0, nil, &formatSize, &asbd), "read tap format")
        let sampleRate = asbd.mSampleRate
        sampleRateHz = sampleRate
        guard let mono = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate,
                                       channels: 1, interleaved: false) else {
            throw failure("could not build output format")
        }
        outputFormat = mono

        // 3) The AAC file.
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: AppSettings.shared.bitrateKbps * 1000,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        file = try AVAudioFile(forWriting: outputURL, settings: settings,
                               commonFormat: .pcmFormatFloat32, interleaved: false)

        // 4) Mic via AVAudioEngine (shares the input device -> Bluetooth-safe).
        startMic(target: mono)

        // 5) Pull the tap and mix.
        try check(AudioDeviceCreateIOProcIDWithBlock(&ioProc, aggregate, nil) { [weak self] _, input, _, _, _ in
            self?.mix(input)
        }, "create IO proc")
        try check(AudioDeviceStart(aggregate, ioProc), "start device")

        running = true
        Log.info("Recording \(outputURL.lastPathComponent) at \(Int(sampleRate))Hz\(micRunning ? " (both sides)" : " (remote only)")")
    }

    private func startMic(target: AVAudioFormat) {
        let input = engine.inputNode
        let nativeFormat = input.outputFormat(forBus: 0)
        guard nativeFormat.sampleRate > 0, let converter = AVAudioConverter(from: nativeFormat, to: target) else {
            Log.error("No usable microphone, recording the other side only")
            return
        }
        self.converter = converter

        input.installTap(onBus: 0, bufferSize: 2048, format: nativeFormat) { [weak self] buffer, _ in
            guard let self, let converter = self.converter else { return }
            let ratio = target.sampleRate / nativeFormat.sampleRate
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
            guard let converted = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }

            var supplied = false
            var conversionError: NSError?
            converter.convert(to: converted, error: &conversionError) { _, status in
                if supplied { status.pointee = .noDataNow; return nil }
                supplied = true; status.pointee = .haveData; return buffer
            }
            if let channel = converted.floatChannelData, converted.frameLength > 0 {
                self.mic.append(UnsafeBufferPointer(start: channel[0], count: Int(converted.frameLength)))
            }
        }
        engine.prepare()
        do { try engine.start(); micRunning = true }
        catch { Log.error("Mic engine failed (\(error.localizedDescription)), recording the other side only") }
    }

    private func mix(_ input: UnsafePointer<AudioBufferList>) {
        guard running, let file, let outputFormat else { return }
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        guard buffers.count > 0, let remoteData = buffers[0].mData, buffers[0].mDataByteSize > 0 else { return }

        let frames = Int(buffers[0].mDataByteSize) / 4 // mono float32
        guard frames > 0,
              let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: AVAudioFrameCount(frames)),
              let destination = output.floatChannelData else { return }
        output.frameLength = AVAudioFrameCount(frames)

        let remote = remoteData.assumingMemoryBound(to: Float.self)
        let mine = micRunning ? mic.take(frames) : [Float](repeating: 0, count: frames)
        for frame in 0..<frames {
            let sample = mine[frame] * micGain + remote[frame] * remoteGain
            // Soft limiter: stay linear at normal levels, but round off peaks with a
            // tanh knee above 0.7 so a loud remote party does not harshly clip at 0 dBFS.
            destination[0][frame] = abs(sample) > 0.7 ? tanhf(sample) : sample
            winMineE += mine[frame] * mine[frame]
            winRemoteE += remote[frame] * remote[frame]
        }
        try? file.write(from: output)

        // Every ~0.6s, record who was the dominant speaker (only when both sides exist).
        if micRunning {
            winFrames += frames
            let windowLen = Int(sampleRateHz * 0.6)
            if winFrames >= windowLen {
                let mineW = winMineE * micGain * micGain
                let remoteW = winRemoteE * remoteGain * remoteGain
                let energy = max(mineW, remoteW) / Float(winFrames)
                let who = energy < 0.0009 ? "silence" : (mineW > remoteW ? "you" : "them")
                if who != "silence", who != lastWho {
                    timeline.append(["t": Double(windowIndex) * 0.6, "who": who])
                    lastWho = who
                }
                windowIndex += 1
                winFrames = 0; winMineE = 0; winRemoteE = 0
            }
        }
    }

    func stop() {
        guard running else { return }
        running = false
        if micRunning { engine.inputNode.removeTap(onBus: 0); engine.stop(); micRunning = false }
        if let ioProc { AudioDeviceStop(aggregate, ioProc); AudioDeviceDestroyIOProcID(aggregate, ioProc); self.ioProc = nil }
        if aggregate != 0 { AudioHardwareDestroyAggregateDevice(aggregate); aggregate = 0 }
        if tap != 0 { AudioHardwareDestroyProcessTap(tap); tap = 0 }
        file = nil
        Log.info("Session stopped")
    }

    private func check(_ status: OSStatus, _ what: String) throws {
        guard status == noErr else { throw failure("\(what) failed: \(describe(status))") }
    }
    private func failure(_ message: String) -> NSError {
        NSError(domain: "CallTape", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

// MARK: - Engine

/// Owns call detection and the active session. This is the object the UI observes.
final class RecorderEngine: ObservableObject {
    static let shared = RecorderEngine()

    enum State: Equatable {
        case idle
        case recording(title: String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var lastError: String?
    /// Wall-clock start of the current recording, so the UI can show a live timer.
    @Published private(set) var recordingStartedAt: Date?
    /// Set when a manual recording just finished, so the UI can offer to name it.
    @Published var pendingNameURL: URL?

    var isRecording: Bool { if case .recording = state { return true } else { return false } }
    var recordingTitle: String? { if case let .recording(title) = state { return title } else { return nil } }

    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "com.calltape.engine")
    // Enrichment polls the call log for up to 90s; keep it OFF the control queue so
    // detection and the Stop button never block.
    private let enrichQueue = DispatchQueue(label: "com.calltape.enrich", qos: .utility)

    private var session: CallSession?
    private var currentURL: URL?
    private var startedAt = Date()
    private var baselinePK: Int64 = 0
    private var manual = false
    private var currentIsWhatsApp = false

    private var manualSession: CallSession?
    private var manualURL: URL?
    private var manualStartedAt: Date?

    private init() {}

    /// Begin watching for calls. Safe to call once at launch.
    func startMonitoring() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: 0.5)
        timer.setEventHandler { [weak self] in self?.tick() }
        timer.resume()
        self.timer = timer
        Log.info("Monitoring started")
    }

    // Calls briefly report no audio during connect and mid-call blips. Requiring a few
    // consecutive misses before stopping keeps one call in one file instead of splitting
    // it into tiny mic-only fragments.
    private var missCount = 0
    private let missesToEnd = 8   // 0.5s tick * 8 = ~4s grace before we call it over

    private func tick() {
        let active = activeCallProcess(matching: AppSettings.shared.targetBundles)

        if let active, session == nil, manualSession == nil, AppSettings.shared.autoRecord {
            begin(target: active.id, bundle: active.bundle, manual: false)
            missCount = 0
        } else if session != nil, !manual {
            if active == nil {
                missCount += 1
                if missCount >= missesToEnd { end(); missCount = 0 }
            } else {
                missCount = 0   // still in a call; reset the grace counter
            }
        }
    }

    /// Manually record everything the Mac is playing plus your mic (for a browser
    /// meeting, etc.). Returns false if something is already recording.
    @discardableResult
    private func startSystemRecording() -> Bool {
        guard session == nil, manualSession == nil else { return false }
        let url = newRecordingURL(tag: "Recording")
        let recorder = CallSession()
        do {
            try recorder.start(source: .system, outputURL: url)
            manualSession = recorder
            manualURL = url
            manualStartedAt = Date()
            DispatchQueue.main.async {
                self.state = .recording(title: "Recording")
                self.recordingStartedAt = Date()
                self.lastError = nil
            }
            return true
        } catch {
            Log.error("Manual recording failed: \(error.localizedDescription)")
            DispatchQueue.main.async { self.lastError = error.localizedDescription }
            return false
        }
    }

    @discardableResult
    private func stopSystemRecording() -> URL? {
        manualSession?.stop()
        manualSession = nil
        let url = manualURL
        let start = manualStartedAt
        manualURL = nil
        manualStartedAt = nil
        if let url { writeManualSidecar(url, start: start) }
        DispatchQueue.main.async {
            self.state = .idle
            self.recordingStartedAt = nil
            RecordingsStore.shared.reload()
            if let url { self.pendingNameURL = url }   // offer to name it
        }
        return url
    }

    private func writeManualSidecar(_ url: URL, start: Date?) {
        let iso = ISO8601DateFormatter()
        let end = Date()
        let began = start ?? end
        var dict: [String: Any] = [
            "audio_file": url.lastPathComponent,
            "source": "manual",
            "recorded_start": iso.string(from: began),
            "recorded_end": iso.string(from: end),
            "recorded_duration_seconds": max(0, Int(end.timeIntervalSince(began)))
        ]
        dict["contact_name"] = "(unknown)"
        let sidecar = url.deletingPathExtension().appendingPathExtension("json")
        if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: sidecar)
        }
    }

    /// One button for the menu bar: stop if recording; otherwise record the active
    /// call, or fall back to recording all system audio (for a browser meeting).
    func quickToggle() {
        queue.async { [weak self] in
            guard let self else { return }
            if self.manualSession != nil { self.stopSystemRecording(); return }
            if self.session != nil { self.end(); return }
            if let active = activeCallProcess(matching: AppSettings.shared.targetBundles) {
                self.begin(target: active.id, bundle: active.bundle, manual: true)
            } else {
                _ = self.startSystemRecording()
            }
        }
    }

    /// Start recording (for Siri / App Intents). No-op if already recording.
    func startRecording() {
        queue.async { [weak self] in
            guard let self, self.session == nil, self.manualSession == nil else { return }
            if let active = activeCallProcess(matching: AppSettings.shared.targetBundles) {
                self.begin(target: active.id, bundle: active.bundle, manual: true)
            } else {
                _ = self.startSystemRecording()
            }
        }
    }

    /// Stop recording (for Siri / App Intents). No-op if nothing is recording.
    func stopRecording() {
        queue.async { [weak self] in
            guard let self else { return }
            if self.manualSession != nil { self.stopSystemRecording() }
            else if self.session != nil { self.end() }
        }
    }

    /// Toggle a user-initiated recording of whatever call is active right now.
    func toggleManual() {
        queue.async { [weak self] in
            guard let self else { return }
            if self.manualSession != nil { return }   // a manual system recording owns the engine
            if self.session != nil {
                self.end()
            } else if let active = activeCallProcess(matching: AppSettings.shared.targetBundles) {
                self.begin(target: active.id, bundle: active.bundle, manual: true)
            } else {
                DispatchQueue.main.async { self.lastError = "No active call to record right now." }
            }
        }
    }

    private func begin(target: AudioObjectID, bundle: String, manual: Bool) {
        let isWhatsApp = bundle.contains("whatsapp")
        let title = isWhatsApp ? "WhatsApp call" : "Call"
        let session = CallSession()
        let url = newRecordingURL(tag: manual ? "Manual" : "Call")
        do {
            let baseline = Enrichment.currentMaxPK()
            // WhatsApp renders call audio in a way a per-process tap can miss, so we
            // capture the whole system output for it; cellular uses the exact process.
            try session.start(source: isWhatsApp ? .system : .process(target), outputURL: url)
            self.session = session
            self.currentURL = url
            self.startedAt = Date()
            self.baselinePK = baseline
            self.manual = manual
            self.currentIsWhatsApp = isWhatsApp
            DispatchQueue.main.async {
                self.state = .recording(title: title)
                self.recordingStartedAt = Date()
                self.lastError = nil
            }
        } catch {
            Log.error("Failed to start: \(error.localizedDescription)")
            DispatchQueue.main.async { self.lastError = error.localizedDescription }
        }
    }

    private func end() {
        // Read the timeline only AFTER stop() halts the audio IO proc, so the audio
        // thread can't still be appending to it (that would be a data race).
        session?.stop()
        let timeline = session?.speakerTimeline() ?? []
        session = nil
        manual = false
        let url = currentURL
        let start = startedAt
        let baseline = baselinePK
        let whatsapp = currentIsWhatsApp
        currentURL = nil
        DispatchQueue.main.async {
            self.state = .idle
            self.recordingStartedAt = nil
            RecordingsStore.shared.reload()
        }
        if let url {
            let end = Date()
            let src: Enrichment.Source = whatsapp ? .whatsapp : .cellular
            // A near-empty file means the audio tap captured nothing. Tell the user
            // instead of leaving a silent, broken recording.
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int ?? 0
            if size < 3000 {
                Log.error("Recording captured no audio (\(size) bytes): \(url.lastPathComponent)")
                DispatchQueue.main.async {
                    self.lastError = "The last call recorded no audio. Check Microphone permission and that the call had sound."
                }
            }
            enrichQueue.async {
                // Write a sidecar immediately (survives an early quit), then refine.
                Enrichment.writeInitialSidecar(audioURL: url, recStart: start, recEnd: end,
                                               baselinePK: baseline, source: src)
                if !timeline.isEmpty {
                    RecordingsStore.shared.updateSidecar(url: url, adding: ["speakers": timeline])
                }
                DispatchQueue.main.async { RecordingsStore.shared.reload() }
                Enrichment.enrich(audioURL: url, recStart: start, recEnd: end, baselinePK: baseline,
                                  source: src, maxWait: 90)
                if AppSettings.shared.autoTranscribe {
                    DispatchQueue.main.async { TranscriptionManager.shared.transcribe(url) }
                }
            }
        }
    }
}

// MARK: - Output paths

private func newRecordingURL(tag: String) -> URL {
    let folder = AppSettings.shared.folderURL
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
    return folder.appendingPathComponent("\(formatter.string(from: Date()))_\(tag).m4a")
}
