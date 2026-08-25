import SwiftUI
import AppKit

/// The self-contained panel shown when you click the menu-bar icon: live status, one
/// Record button, the last few calls (with inline play), and quick ways to open the
/// full app, its settings, or quit. Everything you need without leaving the menu bar.
struct MenuView: View {
    @ObservedObject private var engine = RecorderEngine.shared
    @ObservedObject private var store = RecordingsStore.shared
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            controls
            recent
            Divider()
            footer
        }
        .padding(16)
        .frame(width: 340)
    }

    private var elapsedText: String {
        guard let start = engine.recordingStartedAt else { return "0:00" }
        let s = max(0, Int(Date().timeIntervalSince(start)))
        return "\(s / 60):\(String(format: "%02d", s % 60))"
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "recordingtape")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Palette.accent)
            Text("CallTape").font(.system(size: 16, weight: .semibold))
            Spacer()
            StatusPill(state: engine.state, autoOn: settings.autoRecord)
        }
    }

    private var controls: some View {
        VStack(spacing: 12) {
            Button {
                engine.quickToggle()
            } label: {
                if engine.isRecording {
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        Label("Stop Recording (\(elapsedText))", systemImage: "stop.fill")
                            .monospacedDigit()
                    }
                } else {
                    Label("Record Now", systemImage: "record.circle")
                }
            }
            .buttonStyle(ProminentActionStyle(tint: engine.isRecording ? Palette.recording : Palette.accent))
            .help(engine.isRecording
                  ? "Stop the current recording."
                  : "Record the active call, or everything you hear if there is no call.")

            Toggle(isOn: $settings.autoRecord) {
                Label("Record calls automatically", systemImage: "bolt.horizontal.circle")
            }
            .toggleStyle(.switch)
            .help("When on, CallTape records every call by itself.")

            Toggle(isOn: $settings.autoTranscribe) {
                Label("Transcribe calls automatically", systemImage: "text.quote")
            }
            .toggleStyle(.switch)
            .help("When on, each call is transcribed on your Mac as soon as it ends.")

            if let error = engine.lastError {
                Text(error)
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
        .surfaceCard()
    }

    private var recent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Recent").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                if !store.recordings.isEmpty {
                    Button("See All") { AppDelegate.shared?.openApp(section: .calls) }
                        .buttonStyle(.plain)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Palette.accent)
                        
                }
            }

            if store.recordings.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("No recordings yet").font(.callout.weight(.medium))
                    Text("Your recorded calls will show up here automatically.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            } else {
                ForEach(Array(store.recordings.prefix(4))) { recording in
                    MenuRecordingRow(recording: recording)
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button { AppDelegate.shared?.openApp(section: .calls) } label: {
                Label("Open CallTape", systemImage: "arrow.up.forward.app")
            }
            .buttonStyle(ProminentActionStyle(tint: Palette.accent))

            Button { AppDelegate.shared?.openApp(section: .settings) } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(HoverButtonStyle())
            .help("Settings")

            Button { NSApp.terminate(nil) } label: {
                Image(systemName: "power")
            }
            .buttonStyle(HoverButtonStyle())
            .help("Quit CallTape")
        }
        .font(.callout)
    }
}

private struct StatusPill: View {
    let state: RecorderEngine.State
    let autoOn: Bool
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
                .scaleEffect(isRecording && pulse ? 1.4 : 1.0)
                .animation(isRecording ? .easeInOut(duration: 0.7).repeatForever(autoreverses: true) : .default, value: pulse)
            if isRecording {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text("Recording \(elapsedText)").font(.caption.weight(.medium)).monospacedDigit()
                }
            } else {
                Text(label).font(.caption.weight(.medium))
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .surfaceCard(cornerRadius: 9)
        .onAppear { pulse = true }
        .help(helpText)
    }

    private var elapsedText: String {
        guard let start = RecorderEngine.shared.recordingStartedAt else { return "0:00" }
        let s = max(0, Int(Date().timeIntervalSince(start)))
        return "\(s / 60):\(String(format: "%02d", s % 60))"
    }
    private var isRecording: Bool { if case .recording = state { return true } else { return false } }
    private var color: Color {
        if isRecording { return Palette.recording }
        return autoOn ? .green : Palette.idle
    }
    private var label: String {
        if isRecording { return "Recording" }
        return autoOn ? "Ready" : "Off"
    }
    private var helpText: String {
        if isRecording { return "A call is being recorded right now." }
        return autoOn ? "Waiting for a call to record." : "Automatic recording is off."
    }
}

private struct MenuRecordingRow: View {
    let recording: Recording
    @ObservedObject private var player = AudioPlayer.shared
    @State private var hovering = false

    private var isPlaying: Bool { player.currentURL == recording.url && player.isPlaying }

    var body: some View {
        HStack(spacing: 10) {
            Button { player.toggle(recording.url) } label: {
                ZStack {
                    Avatar(text: recording.title, size: 30,
                           tint: Palette.tint(for: recording.sourceKind), imageData: recording.imageData)
                    if hovering || isPlaying {
                        Circle().fill(.black.opacity(0.4))
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                    }
                }
                .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(recording.title).font(.system(size: 12.5, weight: .medium)).lineLimit(1)
                HStack(spacing: 5) {
                    SourceLabel(recording: recording)
                    Text(recording.modified.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
        }
        .padding(.vertical, 3).padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.primary.opacity(hovering ? 0.06 : 0)))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { AppDelegate.shared?.openRecording(recording.id) }
    }
}
