import Foundation
import Combine

/// One recording on disk: the audio file plus whatever its JSON sidecar tells us,
/// with a contact name resolved from Contacts at load time.
struct Recording: Identifiable {
    let url: URL
    let modified: Date
    let metadata: [String: Any]?
    let resolvedName: String?
    var imageData: Data? = nil   // contact photo (thumbnail), if any

    var id: URL { url }
    var name: String { url.deletingPathExtension().lastPathComponent }

    /// True when the file still has its auto-generated "yyyy-MM-dd_HH-mm-ss_Tag" name,
    /// i.e. the user hasn't renamed it.
    var hasAutoName: Bool {
        name.range(of: #"^\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}_"#, options: .regularExpression) != nil
    }

    var phoneNumber: String? { metadata?["phone_number"] as? String }
    var direction: String? { metadata?["direction"] as? String }
    var source: String? { metadata?["source"] as? String }
    var durationSeconds: Int? { metadata?["recorded_duration_seconds"] as? Int }
    var isVideo: Bool { (metadata?["call_type"] as? String) == "video" }
    var transcript: String? { (metadata?["transcript"] as? String).flatMap { $0.isEmpty ? nil : $0 } }
    var summary: String? { (metadata?["summary"] as? String).flatMap { $0.isEmpty ? nil : $0 } }

    /// Timestamped transcript lines (for timed-subtitle display). Empty for older
    /// transcripts saved before timestamps were captured.
    var transcriptLines: [(time: Double, text: String)] {
        guard let arr = metadata?["segments"] as? [[String: Any]] else { return [] }
        return arr.compactMap { d in
            guard let text = d["text"] as? String else { return nil }
            return ((d["t"] as? Double) ?? 0, text)
        }
    }

    /// Who-spoke-when timeline captured during the call: (start time, "you"/"them").
    var speakerTimeline: [(time: Double, who: String)] {
        guard let arr = metadata?["speakers"] as? [[String: Any]] else { return [] }
        return arr.compactMap { d in
            guard let who = d["who"] as? String else { return nil }
            return ((d["t"] as? Double) ?? 0, who)
        }
    }

    /// The speaker's display name at a given time ("You" or the caller), or nil if
    /// the recording has no speaker timeline.
    func speaker(at time: Double) -> String? {
        let timeline = speakerTimeline
        guard !timeline.isEmpty else { return nil }
        var who = timeline[0].who
        for entry in timeline where entry.time <= time { who = entry.who }
        if who == "you" { return "You" }
        return contactName ?? phoneNumber ?? "Caller"
    }

    private var sidecarName: String? {
        guard let name = metadata?["contact_name"] as? String, name != "(unknown)" else { return nil }
        return name
    }

    var contactName: String? { sidecarName ?? resolvedName }

    /// One-line title for lists.
    var title: String {
        if let contactName { return contactName }
        if let phoneNumber { return phoneNumber }
        // A recording the user renamed keeps that name.
        if !hasAutoName { return name }
        switch sourceKind {
        case .manual: return "Voice recording"
        case .whatsapp: return "WhatsApp call"
        default: return "Unknown caller"
        }
    }

    /// Key used to group recordings by the same person.
    var personKey: String { contactName ?? phoneNumber ?? "Unknown" }

    // MARK: Source & direction (reliable; source is known at record time)

    enum SourceKind { case cellular, whatsapp, manual, unknown }

    var sourceKind: SourceKind {
        switch source {
        case "whatsapp": return .whatsapp
        case "cellular": return .cellular
        case "manual": return .manual
        default:
            // No sidecar: infer from the filename tag.
            if name.contains("Manual") || name.contains("Recording") { return .manual }
            return .unknown
        }
    }

    /// Short label shown as a pill on each row, e.g. "WhatsApp".
    var sourceLabel: String {
        switch sourceKind {
        case .whatsapp: return "WhatsApp"
        case .cellular: return "Cellular"
        case .manual: return "Manual"
        case .unknown: return "Call"
        }
    }

    /// "Incoming" / "Outgoing" when known (cellular only; WhatsApp's Mac database
    /// does not record call direction).
    var directionLabel: String? {
        switch direction {
        case "incoming": return "Incoming"
        case "outgoing": return "Outgoing"
        default: return nil
        }
    }

    var isInContacts: Bool { contactName != nil }
}

/// A person and all their recordings, for the grouped view.
struct Person: Identifiable {
    let key: String
    let recordings: [Recording]
    var id: String { key }
    var displayName: String { recordings.first?.contactName ?? recordings.first?.phoneNumber ?? key }
    var latest: Date { recordings.first?.modified ?? .distantPast }
}

/// Watches the recordings folder and exposes the list to the UI.
final class RecordingsStore: ObservableObject {
    static let shared = RecordingsStore()

    @Published private(set) var recordings: [Recording] = []

    // Loading (file scan + Contacts resolution) runs here, never on the main thread.
    private let ioQueue = DispatchQueue(label: "com.calltape.recordings", qos: .userInitiated)
    // Persisted across reloads so we don't re-enumerate Contacts every time.
    private var contactCache: [String: (name: String?, image: Data?)] = [:]

    private init() { reload() }

    /// Rescan the folder and resolve contacts off the main thread, then publish.
    func reload() {
        ioQueue.async { [weak self] in
            guard let self else { return }
            let items = self.load()
            DispatchQueue.main.async { self.recordings = items }
        }
    }

    private func load() -> [Recording] {
        let folder = AppSettings.shared.folderURL
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys) else {
            return []
        }
        return urls
            .filter { $0.pathExtension == "m4a" }
            .filter { url in   // skip captures that produced no usable audio
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                return size >= 1024
            }
            .map { url in
                let sidecar = url.deletingPathExtension().appendingPathExtension("json")
                var metadata: [String: Any]?
                if let data = try? Data(contentsOf: sidecar) {
                    metadata = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
                }
                var resolved: String?
                var image: Data?
                if let number = metadata?["phone_number"] as? String {
                    let info: (name: String?, image: Data?)
                    if let cached = contactCache[number] { info = cached }
                    else { info = Enrichment.contactInfo(for: number); contactCache[number] = info }
                    resolved = info.name
                    image = info.image
                }
                let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? .distantPast
                return Recording(url: url, modified: modified, metadata: metadata,
                                 resolvedName: resolved, imageData: image)
            }
            .sorted { $0.modified > $1.modified }
    }

    /// Recordings grouped by person, most-recent person first.
    func people() -> [Person] {
        Dictionary(grouping: recordings, by: { $0.personKey })
            .map { Person(key: $0.key, recordings: $0.value) }
            .sorted { $0.latest > $1.latest }
    }

    /// Merge extra keys (e.g. transcript, summary) into a recording's JSON sidecar.
    /// The read-modify-write happens off the main thread.
    func updateSidecar(url: URL, adding fields: [String: Any]) {
        ioQueue.async { [weak self] in
            let sidecar = url.deletingPathExtension().appendingPathExtension("json")
            var dict = (try? Data(contentsOf: sidecar))
                .flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any] ?? [:]
            for (k, v) in fields { dict[k] = v }
            if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: sidecar)
            }
            self?.reload()
        }
    }

    func delete(_ recording: Recording) { discard(url: recording.url) }

    /// Delete a recording's audio and sidecar by URL.
    func discard(url: URL) {
        try? FileManager.default.removeItem(at: url)
        let sidecar = url.deletingPathExtension().appendingPathExtension("json")
        try? FileManager.default.removeItem(at: sidecar)
        reload()
    }

    func rename(_ recording: Recording, to newName: String) {
        rename(url: recording.url, to: newName)
    }

    func rename(url: URL, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // ":" and "/" both display as "/" in Finder, so replace both.
        let safe = trimmed
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: ".")
        let dir = url.deletingLastPathComponent()
        let newAudio = dir.appendingPathComponent(safe).appendingPathExtension("m4a")
        guard newAudio != url else { return }
        try? FileManager.default.moveItem(at: url, to: newAudio)
        let oldSidecar = url.deletingPathExtension().appendingPathExtension("json")
        let newSidecar = newAudio.deletingPathExtension().appendingPathExtension("json")
        try? FileManager.default.moveItem(at: oldSidecar, to: newSidecar)
        // The file URL is the identity, so move the selection with it.
        if LibraryModel.shared.selection == url { LibraryModel.shared.selection = newAudio }
        reload()
    }
}
