import SwiftUI
import AppKit

// MARK: - Date filtering

enum DatePreset: String, CaseIterable, Identifiable {
    case any, today, week, month, custom
    var id: String { rawValue }
    var label: String {
        switch self {
        case .any: return "Any time"
        case .today: return "Today"
        case .week: return "Last 7 days"
        case .month: return "Last 30 days"
        case .custom: return "Custom range"
        }
    }
}

// MARK: - Middle column: the call list

struct CallListView: View {
    let list: SmartList

    @ObservedObject private var store = RecordingsStore.shared
    @ObservedObject private var lib = LibraryModel.shared
    @ObservedObject private var engine = RecorderEngine.shared
    @ObservedObject private var settings = AppSettings.shared

    @State private var showDateSheet = false
    @State private var namingText = ""
    @State private var showNaming = false
    @State private var namingURL: URL?

    private var filtersActive: Bool { lib.datePreset != .any || lib.groupBy != .none }

    private func passesDate(_ r: Recording) -> Bool {
        let cal = Calendar.current
        switch lib.datePreset {
        case .any: return true
        case .today: return r.modified >= cal.startOfDay(for: Date())
        case .week: return r.modified >= (cal.date(byAdding: .day, value: -7, to: Date()) ?? .distantPast)
        case .month: return r.modified >= (cal.date(byAdding: .day, value: -30, to: Date()) ?? .distantPast)
        case .custom:
            let end = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: lib.customTo)) ?? lib.customTo
            return r.modified >= cal.startOfDay(for: lib.customFrom) && r.modified < end
        }
    }

    private var filtered: [Recording] {
        store.recordings.filter { r in
            guard list.matches(r) else { return false }
            switch lib.direction {
            case .all: break
            case .incoming: if r.direction != "incoming" { return false }
            case .outgoing: if r.direction != "outgoing" { return false }
            }
            if !passesDate(r) { return false }
            if !lib.search.isEmpty {
                // Search names, numbers, and what was said (transcript + summary).
                let hay = [r.title, r.phoneNumber, r.contactName, r.transcript, r.summary]
                    .compactMap { $0 }.joined(separator: " ").lowercased()
                if !hay.contains(lib.search.lowercased()) { return false }
            }
            return true
        }
    }

    private var grouped: [Person] {
        Dictionary(grouping: filtered, by: { $0.personKey })
            .map { Person(key: $0.key, recordings: $0.value) }
            .sorted { $0.latest > $1.latest }
    }

    private struct DateGroup: Identifiable { let id: Date; let title: String; let items: [Recording] }

    private var dateGroups: [DateGroup] {
        let cal = Calendar.current
        let byDay = Dictionary(grouping: filtered) { cal.startOfDay(for: $0.modified) }
        return byDay.keys.sorted(by: >).map { day in
            DateGroup(id: day, title: dateTitle(day),
                      items: byDay[day]!.sorted { $0.modified > $1.modified })
        }
    }

    private func dateTitle(_ day: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(day) { return "Today" }
        if cal.isDateInYesterday(day) { return "Yesterday" }
        let f = DateFormatter()
        f.dateFormat = cal.isDate(day, equalTo: Date(), toGranularity: .year) ? "EEEE, MMM d" : "MMM d, yyyy"
        return f.string(from: day)
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: Space.m) {
                PermissionBanner()
                HStack(spacing: Space.s) {
                    searchField
                    filterMenu
                    moreMenu
                }
                directionChips
            }
            .padding(.horizontal, Space.l)
            .padding(.top, Space.m)
            .padding(.bottom, Space.s)

            if filtered.isEmpty { emptyState } else { recordingsList }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) { RecordToolbarButton() }
        }
        .toolbarBackground(.hidden, for: .windowToolbar)
        .sheet(isPresented: $showDateSheet) { dateSheet }
        .alert("Name This Recording", isPresented: $showNaming) {
            TextField("Name", text: $namingText)
            Button("Save") {
                let name = namingText.trimmingCharacters(in: .whitespaces)
                if let url = namingURL, !name.isEmpty { RecordingsStore.shared.rename(url: url, to: name) }
                namingURL = nil
            }
            Button("Discard", role: .destructive) {
                if let url = namingURL {
                    if AudioPlayer.shared.currentURL == url { AudioPlayer.shared.stop() }
                    RecordingsStore.shared.discard(url: url)
                }
                namingURL = nil
            }
        } message: {
            Text("Save this recording with a name, or discard it.")
        }
        .onReceive(engine.$pendingNameURL) { url in
            guard let url else { return }
            namingURL = url
            namingText = defaultRecordingName()
            engine.pendingNameURL = nil    // consume once so it can't re-fire
            showNaming = true
        }
    }

    private func defaultRecordingName() -> String {
        let f = DateFormatter(); f.dateFormat = "MMM d, h.mm a"
        return "Voice recording \(f.string(from: Date()))"
    }

    // MARK: Controls

    private var searchField: some View {
        HStack(spacing: Space.s) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search name or number", text: $lib.search)
                .textFieldStyle(.plain)
            if !lib.search.isEmpty {
                Button { lib.search = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, Space.m).padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
    }

    private var directionChips: some View {
        HStack(spacing: Space.s) {
            ForEach(DirectionFilter.allCases, id: \.self) { option in
                FilterChip(title: option.title, selected: lib.direction == option) {
                    lib.direction = option
                }
            }
            Spacer()
        }
    }

    private var filterMenu: some View {
        Menu {
            Picker("Date", selection: $lib.datePreset) {
                ForEach(DatePreset.allCases.filter { $0 != .custom }) { Text($0.label).tag($0) }
            }
            Button("Custom range…") { showDateSheet = true }
            Divider()
            Picker("Group by", selection: $lib.groupBy) {
                ForEach(GroupBy.allCases) { Text($0.label).tag($0) }
            }
        } label: {
            Image(systemName: filtersActive
                  ? "line.3.horizontal.decrease.circle.fill"
                  : "line.3.horizontal.decrease.circle")
                .font(.system(size: 16))
                .foregroundStyle(filtersActive ? Palette.accent : .secondary)
                .frame(width: 38, height: 36)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.06)))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Filter by date, or group by person")
    }

    // Overflow "More" menu for bulk/utility actions (Apple keeps these out of the
    // primary controls). Transcribe All lives here so it's discoverable but not noisy.
    private var moreMenu: some View {
        let todo = filtered.filter { $0.transcript == nil }.map(\.url)
        return Menu {
            Toggle("Record calls automatically", isOn: $settings.autoRecord)
            Toggle("Transcribe calls automatically", isOn: $settings.autoTranscribe)
            Divider()
            Button {
                TranscriptionManager.shared.transcribeAll(todo)
            } label: {
                Label("Transcribe All (\(todo.count))", systemImage: "waveform.and.mic")
            }
            .disabled(todo.isEmpty)
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
                .frame(width: 38, height: 36)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.06)))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("More actions")
    }

    private var dateSheet: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            Text("Custom Date Range").font(.title3.weight(.semibold))
            DatePicker("From", selection: $lib.customFrom, displayedComponents: .date)
            DatePicker("To", selection: $lib.customTo, in: lib.customFrom..., displayedComponents: .date)
            HStack {
                Spacer()
                Button("Cancel") { showDateSheet = false }
                Button("Apply") { lib.datePreset = .custom; showDateSheet = false }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(Space.xl)
        .frame(width: 340)
    }

    private var recordingsList: some View {
        List(selection: $lib.selection) {
            switch lib.groupBy {
            case .person:
                ForEach(grouped) { person in
                    Section {
                        ForEach(person.recordings) { CallRow(recording: $0).tag($0.id) }
                    } header: {
                        HStack {
                            Text(person.displayName)
                            Spacer()
                            let todo = person.recordings.filter { $0.transcript == nil }.map(\.url)
                            if !todo.isEmpty {
                                Button("Transcribe all") { TranscriptionManager.shared.transcribeAll(todo) }
                                    .buttonStyle(.plain)
                                    .font(.caption).foregroundStyle(Palette.accent)
                            }
                        }
                    }
                }
            case .date:
                ForEach(dateGroups) { group in
                    Section(group.title) {
                        ForEach(group.items) { CallRow(recording: $0).tag($0.id) }
                    }
                }
            case .none:
                ForEach(filtered) { CallRow(recording: $0).tag($0.id) }
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
    }

    private var emptyState: some View {
        VStack(spacing: Space.s) {
            Spacer()
            Image(systemName: store.recordings.isEmpty ? "waveform" : "magnifyingglass")
                .font(.system(size: 40)).foregroundStyle(.tertiary)
            Text(store.recordings.isEmpty ? "No recordings yet" : "No matches")
                .font(.headline)
            Text(store.recordings.isEmpty
                 ? "Your recorded calls appear here automatically."
                 : "Try a different search, list, or filter.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Compact Record button (toolbar, top-right, with live timer)

struct RecordToolbarButton: View {
    @ObservedObject private var engine = RecorderEngine.shared
    private var recording: Bool { engine.isRecording }

    var body: some View {
        // Native prominent toolbar button. `.labelStyle(.titleAndIcon)` forces the
        // title to show (the toolbar would otherwise collapse a Label to icon-only);
        // on macOS 26 this renders as the system Liquid Glass prominent capsule.
        Group {
            if recording {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    button(title: "Stop Recording (\(elapsedText))",
                           icon: "stop.fill", tint: Palette.recording)
                }
            } else {
                button(title: "Record", icon: "record.circle", tint: .accentColor)
            }
        }
        .help(recording ? "Stop the current recording"
              : "Record the active call, or everything you hear if there is no call.")
    }

    private func button(title: String, icon: String, tint: Color) -> some View {
        Button { engine.quickToggle() } label: {
            HStack(spacing: 7) {
                Image(systemName: icon).font(.system(size: 13, weight: .semibold))
                Text(title).font(.system(size: 13, weight: .semibold)).monospacedDigit()
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 15)
            .padding(.vertical, 7)
            .background(Capsule().fill(tint.gradient))
            .overlay(Capsule().strokeBorder(.white.opacity(0.15), lineWidth: 0.5))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var elapsedText: String {
        guard let start = engine.recordingStartedAt else { return "0:00" }
        let s = max(0, Int(Date().timeIntervalSince(start)))
        return "\(s / 60):\(String(format: "%02d", s % 60))"
    }
}

// MARK: - Permission banner (shown when a needed permission is missing)

struct PermissionBanner: View {
    @State private var mic = Permissions.microphoneGranted
    @State private var fda = Permissions.callLogReadable

    var body: some View {
        Group {
            if !mic {
                banner(icon: "mic.slash.fill",
                       text: "Microphone access is off, so your side of calls won't be recorded.",
                       button: "Allow") { Permissions.requestMicrophone { mic = $0 } }
            } else if !fda {
                banner(icon: "externaldrive.badge.exclamationmark",
                       text: "Turn on Full Disk Access so calls are labeled with names and numbers.",
                       button: "Open System Settings") { Permissions.openSettings(.fullDiskAccess) }
            }
        }
        .onAppear { refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refresh()
        }
    }

    private func refresh() {
        mic = Permissions.microphoneGranted
        fda = Permissions.callLogReadable
    }

    private func banner(icon: String, text: String, button: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: Space.m) {
            Image(systemName: icon).font(.system(size: 15)).foregroundStyle(.orange)
            Text(text).font(.caption).foregroundStyle(.primary)
            Spacer(minLength: Space.s)
            Button(button, action: action).controlSize(.small).buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, Space.m).padding(.vertical, Space.s)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.orange.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.orange.opacity(0.25)))
    }
}

// MARK: - Right column: detail

struct DetailPane: View {
    @ObservedObject private var store = RecordingsStore.shared
    @ObservedObject private var lib = LibraryModel.shared

    private var selected: Recording? { store.recordings.first { $0.id == lib.selection } }

    var body: some View {
        if let recording = selected {
            RecordingDetail(recording: recording).id(recording.id)
        } else {
            VStack(spacing: Space.s) {
                Image(systemName: "waveform.circle").font(.system(size: 48)).foregroundStyle(.tertiary)
                Text("Select a recording").font(.title3.weight(.medium))
                Text("Pick a call on the left to play it and see the details.")
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity).padding()
        }
    }
}

// MARK: - Filter chip

struct FilterChip: View {
    let title: String
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, Space.m).padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .foregroundStyle(selected ? .white : .primary)
        .background(
            Capsule().fill(selected ? AnyShapeStyle(Palette.accent.gradient)
                                    : AnyShapeStyle(Color.primary.opacity(hovering ? 0.10 : 0.05)))
        )
        .overlay(Capsule().strokeBorder(Color.primary.opacity(selected ? 0 : 0.08)))
        
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: selected)
        .animation(.easeOut(duration: 0.15), value: hovering)
    }
}

// MARK: - Avatar

private let avatarImageCache = NSCache<NSString, NSImage>()

struct Avatar: View {
    let text: String
    var size: CGFloat = 40
    var tint: Color? = nil
    var imageData: Data? = nil

    private var decodedImage: NSImage? {
        guard let imageData else { return nil }
        let key = NSString(string: "\(imageData.count)-\(imageData.hashValue)")
        if let cached = avatarImageCache.object(forKey: key) { return cached }
        guard let image = NSImage(data: imageData) else { return nil }
        avatarImageCache.setObject(image, forKey: key)
        return image
    }

    var body: some View {
        Group {
            if let image = decodedImage {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                ZStack {
                    Circle().fill((tint ?? color).gradient)
                    Text(initials).font(.system(size: size * 0.4, weight: .semibold)).foregroundStyle(.white)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var initials: String {
        let letters = text.split(separator: " ").prefix(2).compactMap { $0.first }.map(String.init).joined()
        if !letters.isEmpty, text.first?.isLetter == true { return letters.uppercased() }
        return "#"
    }
    // Stable across launches (String.hashValue is per-process seeded, so it isn't).
    private var color: Color {
        let palette: [Color] = [.blue, .purple, .pink, .orange, .teal, .indigo, .green, .cyan]
        var hash = 5381
        for byte in text.utf8 { hash = (hash &* 33) &+ Int(byte) }
        return palette[abs(hash) % palette.count]
    }
}

// MARK: - Source label (Apple Phone-app style: tinted glyph + quiet text)

struct SourceLabel: View {
    let recording: Recording
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Palette.tint(for: recording.sourceKind))
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
    private var label: String {
        if let dir = recording.directionLabel { return "\(recording.sourceLabel) · \(dir)" }
        return recording.sourceLabel
    }
    private var icon: String {
        switch recording.sourceKind {
        case .whatsapp: return recording.isVideo ? "video.fill" : "phone.bubble.fill"
        case .manual: return "waveform"
        case .cellular, .unknown:
            switch recording.direction {
            case "outgoing": return "arrow.up.right"
            case "incoming": return "arrow.down.left"
            default: return "phone.fill"
            }
        }
    }
}

// MARK: - Row

struct CallRow: View {
    let recording: Recording
    @ObservedObject private var player = AudioPlayer.shared
    @ObservedObject private var transcriber = TranscriptionManager.shared
    @State private var hovering = false

    private var isPlaying: Bool { player.currentURL == recording.url && player.isPlaying }
    private var isTranscribing: Bool { transcriber.isActive(recording.url) }

    var body: some View {
        HStack(spacing: Space.m) {
            Button { player.toggle(recording.url) } label: {
                ZStack {
                    Avatar(text: recording.title, size: 42,
                           tint: Palette.tint(for: recording.sourceKind), imageData: recording.imageData)
                    if hovering || isPlaying {
                        Circle().fill(.black.opacity(0.42))
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                    }
                }
                .frame(width: 42, height: 42)
            }
            .buttonStyle(.plain)
            .help(isPlaying ? "Pause" : "Play")

            VStack(alignment: .leading, spacing: 3) {
                Text(recording.title).font(.system(size: 13.5, weight: .medium)).lineLimit(1)
                SourceLabel(recording: recording)
            }
            Spacer(minLength: Space.xs)
            if isTranscribing {
                ProgressView().controlSize(.small)
            } else if recording.transcript != nil {
                Image(systemName: "text.quote")
                    .font(.caption2).foregroundStyle(.tertiary)
                    .help("Transcribed")
            }
            VStack(alignment: .trailing, spacing: 3) {
                Text(recording.modified.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption2).foregroundStyle(.secondary)
                if let s = recording.durationSeconds, s > 0 {
                    Text("\(s / 60):\(String(format: "%02d", s % 60))")
                        .font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .contextMenu {
            Button {
                TranscriptionManager.shared.transcribe(recording.url)
            } label: {
                Label(recording.transcript == nil ? "Transcribe" : "Transcribe Again",
                      systemImage: "waveform.and.mic")
            }
            Button { player.toggle(recording.url) } label: {
                Label(isPlaying ? "Pause" : "Play", systemImage: isPlaying ? "pause" : "play")
            }
            Button { NSWorkspace.shared.activateFileViewerSelecting([recording.url]) } label: {
                Label("Show in Finder", systemImage: "folder")
            }
            Divider()
            Button(role: .destructive) {
                if player.currentURL == recording.url { player.stop() }
                RecordingsStore.shared.delete(recording)
            } label: { Label("Delete", systemImage: "trash") }
        }
    }
}

// MARK: - Detail

private struct RecordingDetail: View {
    let recording: Recording
    @ObservedObject private var player = AudioPlayer.shared
    @State private var showRename = false
    @State private var newName = ""
    @State private var confirmDelete = false
    @State private var showAddContact = false
    @State private var addName = ""
    @ObservedObject private var transcriber = TranscriptionManager.shared
    @State private var showTranscript = true

    private var isCurrent: Bool { player.currentURL == recording.url }
    private var transcribing: Bool { transcriber.isActive(recording.url) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                header
                playerCard
                transcriptSection
                metadata
                actionBar
            }
            .padding(Space.xl)
            .frame(maxWidth: 620, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .alert("Rename Recording", isPresented: $showRename) {
            TextField("Name", text: $newName)
            Button("Cancel", role: .cancel) {}
            Button("Save") { RecordingsStore.shared.rename(recording, to: newName) }
        }
        .confirmationDialog("Delete Recording?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if isCurrent { player.stop() }
                RecordingsStore.shared.delete(recording)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes the audio and its details. This can't be undone.")
        }
        .alert("Add to Contacts", isPresented: $showAddContact) {
            TextField("Name", text: $addName)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                if let number = recording.phoneNumber {
                    Enrichment.addContact(name: addName, number: number)
                    RecordingsStore.shared.reload()
                }
            }
        } message: {
            Text(recording.phoneNumber.map { "Save \($0) to your Contacts." } ?? "")
        }
    }

    private var header: some View {
        HStack(spacing: Space.l) {
            Avatar(text: recording.title, size: 64,
                   tint: Palette.tint(for: recording.sourceKind), imageData: recording.imageData)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: Space.s) {
                    Text(recording.title).font(.title2.weight(.semibold)).lineLimit(1)
                    Button { newName = recording.name; showRename = true } label: {
                        Image(systemName: "pencil").font(.body)
                    }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                    .help("Rename")
                }
                if let number = recording.phoneNumber, number != recording.title {
                    Text(number).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                }
                HStack(spacing: Space.m) {
                    SourceLabel(recording: recording)
                    if let number = recording.phoneNumber, !recording.isInContacts {
                        Button { addName = ""; showAddContact = true } label: {
                            Label("Add to Contacts", systemImage: "person.crop.circle.badge.plus")
                                .font(.caption.weight(.medium))
                        }
                        .buttonStyle(.plain).foregroundStyle(Palette.accent)
                        .help("Save \(number) to your Contacts")
                    }
                }
            }
            Spacer()
        }
    }

    private var playerCard: some View {
        VStack(spacing: Space.m) {
            HStack {
                Text(isCurrent ? formatTime(player.currentTime) : "0:00")
                Spacer()
                Text(isCurrent ? formatTime(player.duration) : durationText)
            }
            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)

            Slider(value: Binding(
                get: { isCurrent ? player.progress : 0 },
                set: { if isCurrent { player.seek(to: $0) } }
            ))
            .disabled(!isCurrent)

            Button { player.toggle(recording.url) } label: {
                Image(systemName: isCurrent && player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 54)).foregroundStyle(Palette.accent)
            }
            .buttonStyle(.plain)
        }
        .padding(Space.xl)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06))
        )
    }

    // MARK: Transcript

    @ViewBuilder private var transcriptSection: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(spacing: Space.s) {
                Label("Transcript", systemImage: "text.quote")
                    .font(.headline)
                Spacer()
                if transcribing {
                    EmptyView()
                } else if recording.transcript == nil {
                    Button { runTranscription() } label: {
                        Label("Transcribe", systemImage: "waveform.and.mic")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                } else {
                    Button { copyTranscript() } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                    Button { runTranscription() } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                    .help("Transcribe again")
                }
            }

            if transcribing {
                HStack(spacing: Space.s) {
                    ProgressView().controlSize(.small)
                    Text("Transcribing on this Mac…").font(.callout).foregroundStyle(.secondary)
                }
            } else if recording.transcript == nil, let error = transcriber.lastError {
                Text(error).font(.callout).foregroundStyle(.secondary)
            } else if recording.transcript != nil {
                if let summary = recording.summary {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Summary", systemImage: "sparkles")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(Palette.accent)
                        Text(summary).font(.callout).textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(Space.m)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Palette.accent.opacity(0.10)))
                }
                transcriptBox
            } else {
                Text("Turn this recording into searchable text, right here on your Mac.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 2)
    }

    // The full transcript in its own expandable container, with tappable timestamps
    // (like subtitles) that jump the audio to that point.
    private var transcriptBox: some View {
        let lines = recording.transcriptLines.isEmpty
            ? [(time: 0.0, text: recording.transcript ?? "")]
            : recording.transcriptLines
        let hasTimes = lines.contains { $0.time > 0 }
        return DisclosureGroup(isExpanded: $showTranscript) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        let speaker = recording.speaker(at: line.time)
                        HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                            if hasTimes {
                                Button { player.playAndSeek(recording.url, to: line.time) } label: {
                                    Text(formatTime(line.time))
                                        .font(.caption.monospacedDigit()).foregroundStyle(Palette.accent)
                                }
                                .buttonStyle(.plain)
                                .help("Play from here")
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                if let speaker {
                                    Text(speaker)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(speaker == "You" ? Palette.accent : .secondary)
                                }
                                Text(line.text).font(.callout).textSelection(.enabled)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(Space.m)
            }
            .frame(maxHeight: 320)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07)))
        } label: {
            Text("Full transcript").font(.subheadline.weight(.semibold))
        }
    }

    private func runTranscription() { transcriber.transcribe(recording.url) }

    private func copyTranscript() {
        let lines = recording.transcriptLines.isEmpty
            ? [(time: 0.0, text: recording.transcript ?? "")]
            : recording.transcriptLines
        let text = lines.map { line -> String in
            if let speaker = recording.speaker(at: line.time) { return "\(speaker): \(line.text)" }
            return line.text
        }.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private var metadata: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            row("Recorded", recording.modified.formatted(date: .complete, time: .shortened))
            if let seconds = recording.durationSeconds, seconds > 0 {
                row("Length", "\(seconds / 60)m \(seconds % 60)s")
            }
            row("Source", sourceLabel)
            row("File", recording.url.lastPathComponent)
        }
        .padding(.horizontal, 2)
    }

    private var actionBar: some View {
        HStack(spacing: Space.s) {
            Button { NSWorkspace.shared.activateFileViewerSelecting([recording.url]) } label: {
                Label("Show in Finder", systemImage: "folder")
            }
            Button { shareFile(recording.url) } label: {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            Spacer()
            Button(role: .destructive) { confirmDelete = true } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label).foregroundStyle(.secondary).frame(width: 92, alignment: .leading)
            Text(value).textSelection(.enabled)
            Spacer()
        }
        .font(.callout)
    }

    private var durationText: String {
        recording.durationSeconds.map { formatTime(TimeInterval($0)) } ?? "--:--"
    }
    private var sourceLabel: String {
        var base = recording.sourceLabel
        if recording.sourceKind == .whatsapp, recording.isVideo { base += " video" }
        if let dir = recording.directionLabel { return "\(base) · \(dir)" }
        return base
    }
}

func shareFile(_ url: URL) {
    let picker = NSSharingServicePicker(items: [url])
    if let view = NSApp.keyWindow?.contentView {
        picker.show(relativeTo: .zero, of: view, preferredEdge: .minY)
    }
}
