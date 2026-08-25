import AppIntents

/// Siri / Shortcuts support. These let the user say "Hey Siri, start recording with
/// CallTape" or add the actions to a Shortcut.
struct StartRecordingIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Recording"
    static var description = IntentDescription("Start recording the current call in CallTape.")
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult {
        RecorderEngine.shared.startRecording()
        return .result()
    }
}

struct StopRecordingIntent: AppIntent {
    static var title: LocalizedStringResource = "Stop Recording"
    static var description = IntentDescription("Stop the current CallTape recording.")
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult {
        RecorderEngine.shared.stopRecording()
        return .result()
    }
}

struct TranscribeLastCallIntent: AppIntent {
    static var title: LocalizedStringResource = "Transcribe Last Call"
    static var description = IntentDescription("Transcribe the most recent recording on this Mac.")
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult {
        if let url = RecordingsStore.shared.recordings.first?.url {
            TranscriptionManager.shared.transcribe(url)
        }
        return .result()
    }
}

struct CallTapeShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StartRecordingIntent(),
                    phrases: ["Start recording with \(.applicationName)",
                              "Record a call with \(.applicationName)"],
                    shortTitle: "Start Recording",
                    systemImageName: "record.circle")
        AppShortcut(intent: StopRecordingIntent(),
                    phrases: ["Stop recording with \(.applicationName)"],
                    shortTitle: "Stop Recording",
                    systemImageName: "stop.fill")
        AppShortcut(intent: TranscribeLastCallIntent(),
                    phrases: ["Transcribe my last call with \(.applicationName)",
                              "Transcribe the last recording with \(.applicationName)"],
                    shortTitle: "Transcribe Last Call",
                    systemImageName: "text.quote")
    }
}
