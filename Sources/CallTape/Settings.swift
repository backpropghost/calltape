import Foundation
import Combine

/// User preferences, backed by UserDefaults. One shared instance the whole app reads.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    private enum Key {
        static let autoRecord = "autoRecord"
        static let recordCellular = "recordCellular"
        static let recordWhatsApp = "recordWhatsApp"
        static let bitrateKbps = "bitrateKbps"
        static let micGain = "micGain"
        static let remoteGain = "remoteGain"
        static let showDockIcon = "showDockIcon"
        static let showMenuBar = "showMenuBar"
        static let launchAtLogin = "launchAtLogin"
        static let folderPath = "folderPath"
        static let menuBarIcon = "menuBarIcon"
        static let hasOnboarded = "hasOnboarded"
        static let autoTranscribe = "autoTranscribe"
    }

    @Published var autoRecord: Bool        { didSet { defaults.set(autoRecord, forKey: Key.autoRecord) } }
    @Published var recordCellular: Bool    { didSet { defaults.set(recordCellular, forKey: Key.recordCellular) } }
    @Published var recordWhatsApp: Bool    { didSet { defaults.set(recordWhatsApp, forKey: Key.recordWhatsApp) } }
    @Published var bitrateKbps: Int        { didSet { defaults.set(bitrateKbps, forKey: Key.bitrateKbps) } }
    @Published var micGain: Double         { didSet { defaults.set(micGain, forKey: Key.micGain) } }
    @Published var remoteGain: Double      { didSet { defaults.set(remoteGain, forKey: Key.remoteGain) } }
    @Published var showDockIcon: Bool      { didSet { defaults.set(showDockIcon, forKey: Key.showDockIcon) } }
    @Published var showMenuBar: Bool       { didSet { defaults.set(showMenuBar, forKey: Key.showMenuBar) } }
    @Published var launchAtLogin: Bool     { didSet { defaults.set(launchAtLogin, forKey: Key.launchAtLogin) } }
    @Published var folderPath: String      { didSet { defaults.set(folderPath, forKey: Key.folderPath) } }
    @Published var menuBarIcon: String     { didSet { defaults.set(menuBarIcon, forKey: Key.menuBarIcon) } }
    @Published var hasOnboarded: Bool       { didSet { defaults.set(hasOnboarded, forKey: Key.hasOnboarded) } }
    @Published var autoTranscribe: Bool    { didSet { defaults.set(autoTranscribe, forKey: Key.autoTranscribe) } }

    private init() {
        let d = UserDefaults.standard
        autoRecord     = d.object(forKey: Key.autoRecord) as? Bool ?? true
        recordCellular = d.object(forKey: Key.recordCellular) as? Bool ?? true
        recordWhatsApp = d.object(forKey: Key.recordWhatsApp) as? Bool ?? true
        bitrateKbps    = d.object(forKey: Key.bitrateKbps) as? Int ?? 64
        micGain        = d.object(forKey: Key.micGain) as? Double ?? 3.0
        remoteGain     = d.object(forKey: Key.remoteGain) as? Double ?? 0.7
        showDockIcon   = d.object(forKey: Key.showDockIcon) as? Bool ?? false
        showMenuBar    = d.object(forKey: Key.showMenuBar) as? Bool ?? true
        launchAtLogin  = d.object(forKey: Key.launchAtLogin) as? Bool ?? false
        folderPath     = d.string(forKey: Key.folderPath)
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Music/Call Recordings").path
        menuBarIcon    = d.string(forKey: Key.menuBarIcon) ?? "recordingtape"
        hasOnboarded   = d.object(forKey: Key.hasOnboarded) as? Bool ?? false
        autoTranscribe = d.object(forKey: Key.autoTranscribe) as? Bool ?? false
    }

    var folderURL: URL { URL(fileURLWithPath: folderPath) }

    /// Bundle ids of the call apps we watch and tap, based on the toggles above.
    var targetBundles: Set<String> {
        var set = Set<String>()
        if recordCellular { set.insert("com.apple.avconferenced") }
        if recordWhatsApp { set.insert("net.whatsapp.WhatsApp") }
        return set
    }
}
