import SwiftUI

// MARK: - Routing

enum AppSection: String { case calls, settings, about }

/// The smart lists in the sidebar. Each is a predicate over recordings.
enum SmartList: String, CaseIterable, Identifiable, Hashable {
    case all, cellular, whatsapp, manual
    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All Calls"
        case .cellular: return "Cellular"
        case .whatsapp: return "WhatsApp"
        case .manual: return "Manual"
        }
    }
    var icon: String {
        switch self {
        case .all: return "tray.full"
        case .cellular: return "phone"
        case .whatsapp: return "phone.bubble"
        case .manual: return "waveform"
        }
    }
    var kind: Recording.SourceKind {
        switch self {
        case .all: return .unknown
        case .cellular: return .cellular
        case .whatsapp: return .whatsapp
        case .manual: return .manual
        }
    }
    func matches(_ r: Recording) -> Bool {
        switch self {
        case .all: return true
        case .cellular: return r.sourceKind == .cellular || r.sourceKind == .unknown
        case .whatsapp: return r.sourceKind == .whatsapp
        case .manual: return r.sourceKind == .manual
        }
    }
}

/// What the main area shows. Library lists and the app panes share one sidebar.
enum Route: Hashable {
    case list(SmartList)
    case settings
    case about
}

enum DirectionFilter: String, CaseIterable {
    case all, incoming, outgoing
    var title: String { rawValue.capitalized }
}

enum GroupBy: String, CaseIterable, Identifiable {
    case none, person, date
    var id: String { rawValue }
    var label: String {
        switch self {
        case .none: return "None"
        case .person: return "Person"
        case .date: return "Date"
        }
    }
}

final class LibraryModel: ObservableObject {
    static let shared = LibraryModel()
    @Published var route: Route = .list(.all)
    @Published var direction: DirectionFilter = .all
    @Published var search = ""
    @Published var selection: Recording.ID?
    // Filter state lives here (not in the view) so it survives layout changes.
    @Published var datePreset: DatePreset = .any
    @Published var customFrom = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
    @Published var customTo = Date()
    @Published var groupBy: GroupBy = .none
    private init() {}

    var currentList: SmartList {
        if case let .list(l) = route { return l }
        return .all
    }

    /// Switch the active list, clearing a selection that wouldn't be visible.
    func select(_ route: Route) {
        if case let .list(newList) = route, newList != currentList { selection = nil }
        self.route = route
    }
}

// MARK: - Main window

struct MainView: View {
    @ObservedObject private var lib = LibraryModel.shared

    private var routeSelection: Binding<Route?> {
        Binding(get: { lib.route }, set: { if let v = $0 { lib.select(v) } })
    }

    var body: some View {
        Group {
            switch lib.route {
            case .list(let smart):
                // Native three columns: this collapses gracefully and never clips.
                NavigationSplitView {
                    Sidebar(selection: routeSelection)
                        .navigationSplitViewColumnWidth(min: 212, ideal: 236, max: 300)
                } content: {
                    CallListView(list: smart)
                        .navigationSplitViewColumnWidth(min: 340, ideal: 400, max: 560)
                } detail: {
                    DetailPane()
                        .navigationSplitViewColumnWidth(min: 380, ideal: 460)
                }
                .navigationSplitViewStyle(.balanced)
            case .settings, .about:
                // Two columns: the pane fills the whole content area.
                NavigationSplitView {
                    Sidebar(selection: routeSelection)
                        .navigationSplitViewColumnWidth(min: 212, ideal: 236, max: 300)
                } detail: {
                    if case .about = lib.route { AboutPane() } else { SettingsPane() }
                }
            }
        }
        .frame(minWidth: 950, minHeight: 600)
    }
}

// MARK: - Sidebar

private struct Sidebar: View {
    @Binding var selection: Route?
    @ObservedObject private var store = RecordingsStore.shared
    // Reactive so the warning clears once permissions are granted.
    @State private var needsAttention = !(Permissions.microphoneGranted && Permissions.callLogReadable)

    private func count(_ list: SmartList) -> Int {
        store.recordings.filter(list.matches).count
    }

    private func refreshAttention() {
        needsAttention = !(Permissions.microphoneGranted && Permissions.callLogReadable)
    }

    var body: some View {
        List(selection: $selection) {
            Section("Library") {
                ForEach(SmartList.allCases) { list in
                    Label(list.title, systemImage: list.icon)
                        .badge(count(list))
                        .tag(Route.list(list))
                }
            }

            Section("App") {
                Label {
                    HStack(spacing: 0) {
                        Text("Settings")
                        if needsAttention {
                            Spacer(minLength: Space.s)
                            Image(systemName: "exclamationmark.circle.fill")
                                .font(.body).foregroundStyle(.yellow)
                        }
                    }
                } icon: {
                    Image(systemName: "gearshape")
                }
                .tag(Route.settings)

                Label("About", systemImage: "info.circle")
                    .tag(Route.about)
            }
        }
        .listStyle(.sidebar)
        .tint(Palette.accent)
        .onAppear { refreshAttention() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshAttention()
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack(spacing: 5) {
                Image(systemName: "lock.fill").font(.caption2)
                Text("Everything stays on your Mac").font(.caption2)
                Spacer()
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, Space.l)
            .padding(.vertical, Space.s)
        }
    }
}
