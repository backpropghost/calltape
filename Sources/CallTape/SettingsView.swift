import SwiftUI
import AppKit

/// Settings, rebuilt with the app's own card system so it matches the rest of the UI
/// instead of the default grouped form.
struct SettingsPane: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var micGranted = Permissions.microphoneGranted
    @State private var contactsGranted = Permissions.contactsGranted
    @State private var callLogReadable = Permissions.callLogReadable

    private let icons = ["recordingtape", "waveform", "record.circle",
                         "phone.circle.fill", "mic.circle.fill", "waveform.circle"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                general
                sources
                quality
                storage
                permissions
            }
            .padding(Space.xl)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear { refreshPermissions() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshPermissions()
        }
    }

    private func gainSlider(value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack(spacing: Space.s) {
            Slider(value: value, in: range, step: 0.1).frame(width: 150)
            Text(String(format: "%.1f×", value.wrappedValue))
                .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                .frame(width: 40, alignment: .trailing)
        }
    }

    // MARK: General

    private var general: some View {
        SettingsSection(title: "General") {
            SettingRow(title: "Record calls automatically",
                       subtitle: "Start recording the moment a call begins.",
                       icon: "bolt.horizontal.circle", tint: Palette.accent) {
                Toggle("Record calls automatically", isOn: $settings.autoRecord).labelsHidden().toggleStyle(.switch)
            }
            RowDivider()
            SettingRow(title: "Transcribe calls automatically",
                       subtitle: "Create an on-device transcript as soon as a call ends.",
                       icon: "text.quote", tint: Palette.accent) {
                Toggle("Transcribe calls automatically", isOn: $settings.autoTranscribe).labelsHidden().toggleStyle(.switch)
            }
            RowDivider()
            SettingRow(title: "Launch at login", icon: "power", tint: .secondary) {
                Toggle("Launch at login", isOn: $launchAtLogin).labelsHidden().toggleStyle(.switch)
                    .onChange(of: launchAtLogin) { _, value in
                        LoginItem.set(value); settings.launchAtLogin = value
                    }
            }
            RowDivider()
            SettingRow(title: "Show icon in menu bar", icon: "menubar.rectangle", tint: .secondary) {
                Toggle("Show icon in menu bar", isOn: $settings.showMenuBar).labelsHidden().toggleStyle(.switch)
            }
            RowDivider()
            SettingRow(title: "Show icon in Dock", icon: "dock.rectangle", tint: .secondary) {
                Toggle("Show icon in Dock", isOn: $settings.showDockIcon).labelsHidden().toggleStyle(.switch)
            }
            RowDivider()
            SettingRow(title: "Menu bar icon",
                       subtitle: "How CallTape appears in the menu bar.",
                       icon: "sparkles", tint: .secondary) {
                HStack(spacing: 6) {
                    ForEach(icons, id: \.self) { name in
                        Button { settings.menuBarIcon = name } label: {
                            Image(systemName: name)
                                .font(.system(size: 14))
                                .frame(width: 30, height: 30)
                                .foregroundStyle(settings.menuBarIcon == name ? .white : .primary)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(settings.menuBarIcon == name
                                              ? AnyShapeStyle(Palette.accent.gradient)
                                              : AnyShapeStyle(Color.primary.opacity(0.06)))
                                )
                        }
                        .buttonStyle(.plain)
                        
                    }
                }
            }
        }
    }

    // MARK: Sources

    private var sources: some View {
        SettingsSection(title: "What to record") {
            SettingRow(title: "Cellular and FaceTime calls",
                       subtitle: "Calls that ring through on your iPhone via Continuity.",
                       icon: "phone", tint: Palette.tint(for: .cellular)) {
                Toggle("Cellular and FaceTime calls", isOn: $settings.recordCellular).labelsHidden().toggleStyle(.switch)
            }
            RowDivider()
            SettingRow(title: "WhatsApp desktop calls",
                       subtitle: "Voice and video calls in the WhatsApp app.",
                       icon: "phone.bubble", tint: Palette.tint(for: .whatsapp)) {
                Toggle("WhatsApp desktop calls", isOn: $settings.recordWhatsApp).labelsHidden().toggleStyle(.switch)
            }
        }
    }

    // MARK: Quality

    private var quality: some View {
        SettingsSection(title: "Audio quality") {
            SettingRow(title: "Bitrate", icon: "dial.high", tint: .secondary) {
                Picker("Bitrate", selection: $settings.bitrateKbps) {
                    Text("32 kbps").tag(32)
                    Text("48 kbps").tag(48)
                    Text("64 kbps").tag(64)
                    Text("96 kbps").tag(96)
                    Text("128 kbps").tag(128)
                }
                .labelsHidden().fixedSize()
            }
            RowDivider()
            SettingRow(title: "Your voice",
                       subtitle: "Boost your side if you sound quiet.",
                       icon: "mic", tint: .secondary) {
                gainSlider(value: $settings.micGain, range: 0.5...6)
            }
            RowDivider()
            SettingRow(title: "Other party",
                       subtitle: "Lower the other side if they are too loud.",
                       icon: "speaker.wave.2", tint: .secondary) {
                gainSlider(value: $settings.remoteGain, range: 0.2...2)
            }
        }
    }

    // MARK: Storage

    private var storage: some View {
        SettingsSection(title: "Storage") {
            SettingRow(title: "Saving to",
                       subtitle: prettyPath(settings.folderPath),
                       icon: "folder", tint: .secondary) {
                HStack(spacing: Space.s) {
                    Button("Change…") { chooseFolder() }
                    Button("Open") { NSWorkspace.shared.open(settings.folderURL) }
                }
                .controlSize(.small)
            }
            RowDivider()
            SettingRow(title: "Plain files you own",
                       subtitle: "Each call is an audio file plus a small text file with the number, direction, length, and name. Nothing is uploaded.",
                       icon: "doc.text", tint: .secondary) { EmptyView() }
        }
    }

    // MARK: Permissions

    private var permissions: some View {
        SettingsSection(title: "Permissions") {
            PermissionRow(title: "Microphone",
                          detail: "Records your side of the call.",
                          granted: micGranted,
                          action: ("Allow", { Permissions.requestMicrophone { micGranted = $0 } }))
            RowDivider()
            PermissionRow(title: "Contacts",
                          detail: "Shows the caller's name instead of just a number.",
                          granted: contactsGranted,
                          action: ("Allow", { Permissions.requestContacts { contactsGranted = $0 } }))
            RowDivider()
            PermissionRow(title: "Full Disk Access",
                          detail: "Reads the call log to fill in the number and direction. Turn CallTape on in the list, then relaunch.",
                          granted: callLogReadable,
                          action: ("Open System Settings", { Permissions.openSettings(.fullDiskAccess) }))
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = settings.folderURL
        panel.prompt = "Use This Folder"
        if panel.runModal() == .OK, let url = panel.url {
            settings.folderPath = url.path
            RecordingsStore.shared.reload()
        }
    }

    private func refreshPermissions() {
        micGranted = Permissions.microphoneGranted
        contactsGranted = Permissions.contactsGranted
        callLogReadable = Permissions.callLogReadable
    }
}

private struct PermissionRow: View {
    let title: String
    let detail: String
    let granted: Bool
    let action: (label: String, run: () -> Void)

    var body: some View {
        SettingRow(title: title, subtitle: detail,
                   icon: granted ? "checkmark.circle.fill" : "exclamationmark.circle",
                   tint: granted ? .green : .orange) {
            if !granted {
                Button(action.label) { action.run() }.controlSize(.small)
            } else {
                Text("Allowed").font(.caption.weight(.medium)).foregroundStyle(.green)
            }
        }
    }
}
