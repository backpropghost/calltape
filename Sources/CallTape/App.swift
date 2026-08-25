import SwiftUI
import AppKit
import Combine
import ServiceManagement
import Carbon

@main
struct CallTapeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    // The main window and status item are AppKit (managed by the delegate). The
    // Settings scene gives us the native Preferences window that ⌘, opens.
    var body: some Scene {
        // Gives ⌘, a native Settings window showing the same settings pane.
        Settings {
            SettingsPane().frame(width: 560, height: 640)
        }
        .commands {
            // App menu: use our own About window instead of the standard panel.
            CommandGroup(replacing: .appInfo) {
                Button("About CallTape") { AppDelegate.shared?.showAbout() }
                Button("Support CallTape…") {
                    if let url = URL(string: "https://github.com/sponsors/backpropghost") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
            // A dedicated Recording menu.
            CommandMenu("Recording") {
                Button("Record") { RecorderEngine.shared.startRecording() }
                    .keyboardShortcut("r", modifiers: .command)
                Button("Stop Recording") { RecorderEngine.shared.stopRecording() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                Divider()
                Button("Open CallTape") { AppDelegate.shared?.showMainWindow() }
                    .keyboardShortcut("0", modifiers: .command)
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    static var shared: AppDelegate!

    private var statusItem: NSStatusItem?
    private var mainWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var popover: NSPopover?
    private var statusTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        Log.info("CallTape launching…")

        applyActivationPolicy(AppSettings.shared.showDockIcon)
        setupStatusItem()
        observe()
        RecorderEngine.shared.startMonitoring()

        if AppSettings.shared.hasOnboarded {
            // Only open the window when the user launched CallTape themselves. When
            // macOS starts us at login we stay in the menu bar and show no window.
            if !launchedAsLoginItem {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                    self?.showMainWindow()
                }
            } else {
                Log.info("Launched at login; staying in the menu bar only")
            }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                self?.showOnboarding()
            }
        }
        Log.info("CallTape launched")
    }

    /// True when macOS started the app automatically as a login item, rather than
    /// the user opening it. Read from the Apple event that launched the process.
    private var launchedAsLoginItem: Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent else { return false }
        return event.eventID == kAEOpenApplication &&
            event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    }

    // Keep running after the window is closed; we live in the menu bar.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    // Clicking the Dock/Launchpad icon (or reopening) shows the window again.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showMainWindow() }
        return true
    }

    // MARK: Status item

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = symbolImage(AppSettings.shared.menuBarIcon)
        item.button?.image?.isTemplate = true
        // Monospaced digits so the ticking timer never changes width (no "dancing").
        item.button?.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        item.button?.toolTip = "CallTape"
        item.button?.target = self
        item.button?.action = #selector(statusClicked(_:))
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem = item
        Log.info("Status item created: \(item.button != nil)")
    }

    @objc private func statusClicked(_ sender: Any?) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showStatusMenu()
        } else {
            togglePopover()
        }
    }

    // MARK: Popover (self-contained menu-bar panel)

    private func togglePopover() {
        if let popover, popover.isShown { popover.performClose(nil); return }
        guard let button = statusItem?.button else { return }
        let popover = self.popover ?? {
            let p = NSPopover()
            p.behavior = .transient
            p.animates = true
            p.contentViewController = NSHostingController(rootView: MenuView())
            self.popover = p
            return p
        }()
        RecordingsStore.shared.reload()
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    func closePopover() { popover?.performClose(nil) }

    /// Called from the popover: dismiss it and open the main window at a section.
    func openApp(section: AppSection) {
        closePopover()
        showMainWindow(section: section)
    }

    /// From the popover's Recent list: open the app and select that recording.
    func openRecording(_ id: Recording.ID) {
        closePopover()
        LibraryModel.shared.route = .list(.all)
        LibraryModel.shared.selection = id
        showMainWindow()
    }

    private func showStatusMenu() {
        let menu = NSMenu()
        menu.addItem(menuItem("Open CallTape", #selector(menuOpen)))
        menu.addItem(.separator())
        let recording = RecorderEngine.shared.isRecording
        menu.addItem(menuItem(recording ? "Stop Recording" : "Record Now", #selector(menuRecord)))
        menu.addItem(menuItem("Settings…", #selector(menuSettings)))
        menu.addItem(.separator())
        menu.addItem(menuItem("Quit CallTape", #selector(menuQuit)))
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        DispatchQueue.main.async { self.statusItem?.menu = nil }
    }

    private func menuItem(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func menuOpen() { showMainWindow() }
    @objc private func menuRecord() { RecorderEngine.shared.quickToggle() }
    @objc private func menuSettings() { showMainWindow(section: .settings) }
    @objc private func menuQuit() { NSApp.terminate(nil) }

    // MARK: Windows

    func showMainWindow(section: AppSection? = nil) {
        switch section {
        case .settings: LibraryModel.shared.route = .settings
        case .about:    LibraryModel.shared.route = .about
        case .calls:    LibraryModel.shared.route = .list(LibraryModel.shared.currentList)
        case .none:     break
        }
        if mainWindow == nil {
            let host = NSHostingController(rootView: MainView())
            let window = NSWindow(contentViewController: host)
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.title = "CallTape"
            window.setContentSize(NSSize(width: 1040, height: 680))
            window.isReleasedWhenClosed = false
            window.titlebarAppearsTransparent = true
            window.delegate = self
            window.center()
            mainWindow = window
        }
        present(mainWindow)
    }

    func showSettings() { showMainWindow(section: .settings) }
    func showAbout() { showMainWindow(section: .about) }

    func showOnboarding() {
        if onboardingWindow == nil {
            let host = NSHostingController(rootView: OnboardingView(onFinish: { [weak self] in
                self?.finishOnboarding()
            }))
            let window = NSWindow(contentViewController: host)
            window.styleMask = [.titled, .closable]
            window.title = "Welcome to CallTape"
            window.setContentSize(NSSize(width: 540, height: 520))
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            onboardingWindow = window
        }
        present(onboardingWindow)
    }

    private func finishOnboarding() {
        AppSettings.shared.hasOnboarded = true
        onboardingWindow?.close()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.showMainWindow(section: .calls)
        }
    }

    private func present(_ window: NSWindow?) {
        guard let window else { return }
        NSApp.setActivationPolicy(.regular)   // let the window take focus even for a menu-bar app
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let anyVisible = [self.mainWindow, self.onboardingWindow].contains { $0?.isVisible == true }
            if !anyVisible && !AppSettings.shared.showDockIcon {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }

    // MARK: Observation

    private func observe() {
        AppSettings.shared.$showDockIcon
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.applyActivationPolicy($0) }
            .store(in: &cancellables)

        // Show / hide the menu-bar icon on demand.
        AppSettings.shared.$showMenuBar
            .receive(on: RunLoop.main)
            .sink { [weak self] visible in self?.statusItem?.isVisible = visible }
            .store(in: &cancellables)

        Publishers.CombineLatest(AppSettings.shared.$menuBarIcon, RecorderEngine.shared.$state)
            .receive(on: RunLoop.main)
            .sink { [weak self] icon, state in
                guard let self, let button = self.statusItem?.button else { return }
                let recording: Bool = { if case .recording = state { return true } else { return false } }()
                if recording {
                    // Non-template red so it stays visible (and clearly "recording") on
                    // both light and dark menu bars.
                    let config = NSImage.SymbolConfiguration(paletteColors: [.systemRed])
                    button.image = self.symbolImage("record.circle.fill")?.withSymbolConfiguration(config)
                    button.image?.isTemplate = false
                    button.imagePosition = .imageLeading
                    if self.statusTimer == nil { self.startStatusTimer() }
                } else {
                    button.image = self.symbolImage(icon)
                    button.image?.isTemplate = true
                    button.imagePosition = .imageOnly
                    self.stopStatusTimer()
                }
            }
            .store(in: &cancellables)
    }

    // Live elapsed time shown next to the menu-bar icon while recording.
    private func startStatusTimer() {
        updateStatusTitle()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.updateStatusTitle()
        }
        RunLoop.main.add(timer, forMode: .common)   // added once; ticks during menu tracking too
        statusTimer = timer
    }

    private func stopStatusTimer() {
        statusTimer?.invalidate()
        statusTimer = nil
        statusItem?.button?.title = ""
    }

    private func updateStatusTitle() {
        guard let start = RecorderEngine.shared.recordingStartedAt else { statusItem?.button?.title = ""; return }
        let s = max(0, Int(Date().timeIntervalSince(start)))
        statusItem?.button?.title = String(format: " %d:%02d", s / 60, s % 60)
    }

    private func symbolImage(_ name: String) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: "CallTape")
            ?? NSImage(systemSymbolName: "waveform", accessibilityDescription: "CallTape")
    }

    private func applyActivationPolicy(_ showDock: Bool) {
        NSApp.setActivationPolicy(showDock ? .regular : .accessory)
    }
}

/// Wraps SMAppService so the Settings toggle reads cleanly.
enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            Log.error("Login item change failed: \(error.localizedDescription)")
        }
    }
}
