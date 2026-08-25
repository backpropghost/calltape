import SwiftUI
import AppKit

/// First-run flow. Each permission is explained *before* the system prompt fires
/// (priming), and the user picks where recordings are saved. Plain language only.
struct OnboardingView: View {
    let onFinish: () -> Void

    @ObservedObject private var settings = AppSettings.shared
    @State private var step = 0
    @State private var micGranted = Permissions.microphoneGranted
    @State private var contactsGranted = Permissions.contactsGranted

    private let lastStep = 4

    var body: some View {
        VStack(spacing: 0) {
            progress
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(28)
            Divider()
            footer
        }
        .frame(width: 540, height: 520)
    }

    // MARK: Steps

    @ViewBuilder private var content: some View {
        switch step {
        case 0: welcome
        case 1: microphone
        case 2: fullDisk
        case 3: contacts
        default: storage
        }
    }

    private var welcome: some View {
        Step(icon: "recordingtape", title: "Welcome to CallTape",
             message: "CallTape quietly records your calls, both your voice and theirs, and saves each one to your Mac automatically. Setting up takes about a minute.")
    }

    private var microphone: some View {
        Step(icon: "mic.fill", title: "Record your voice",
             message: "CallTape uses the microphone to capture your side of the call alongside theirs. Nothing is recorded until a call actually starts.",
             granted: micGranted,
             action: ("Allow Microphone", { Permissions.requestMicrophone { micGranted = $0 } }))
    }

    private var fullDisk: some View {
        Step(icon: "folder.badge.gearshape", title: "Add call details",
             message: "To label each recording with the phone number and whether it was incoming or outgoing, CallTape reads your Mac's call history, which needs Full Disk Access. In the window that opens, turn CallTape on, then come back here.",
             action: ("Open System Settings", { Permissions.openSettings(.fullDiskAccess) }))
    }

    private var contacts: some View {
        Step(icon: "person.crop.circle", title: "Show caller names",
             message: "Allow Contacts and recordings are labeled with the caller's name instead of just their number. This is optional, and you can turn it on later.",
             granted: contactsGranted,
             action: ("Allow Contacts", { Permissions.requestContacts { contactsGranted = $0 } }))
    }

    private var storage: some View {
        VStack(spacing: 18) {
            Image(systemName: "square.and.arrow.down.on.square")
                .font(.system(size: 42, weight: .regular))
                .foregroundStyle(Palette.accent)
            Text("Where to save recordings").font(.title2.weight(.semibold))
            Text("Each call is saved here as an audio file. You can change this anytime in Settings.")
                .font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 8) {
                Image(systemName: "folder")
                Text(prettyPath(settings.folderPath)).lineLimit(1).truncationMode(.middle)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .glassCard(cornerRadius: 9)

            Button("Choose a Different Folder…") { chooseFolder() }
                .buttonStyle(HoverButtonStyle())

            Text("By using CallTape you agree to record only where it's legal. See About for the full disclaimer.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
                .padding(.top, 6)
        }
    }

    // MARK: Chrome

    private var progress: some View {
        HStack(spacing: 7) {
            ForEach(0...lastStep, id: \.self) { index in
                Capsule()
                    .fill(index == step ? Palette.accent : Color.secondary.opacity(0.3))
                    .frame(width: index == step ? 20 : 7, height: 7)
                    .animation(.easeInOut(duration: 0.2), value: step)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
    }

    private var footer: some View {
        HStack {
            if step > 0 {
                Button("Back") { step -= 1 }
                    .buttonStyle(HoverButtonStyle())
            }
            Spacer()
            Button(step == lastStep ? "Start Using CallTape" : "Continue") {
                if step == lastStep { onFinish() } else { step += 1 }
            }
            .buttonStyle(ProminentActionStyle(tint: Palette.accent))
            .frame(width: 200)
        }
        .padding(16)
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
        }
    }
}

/// A consistent onboarding screen: big icon, title, explanation, an optional action
/// button that shows a check once granted.
private struct Step: View {
    let icon: String
    let title: String
    let message: String
    var granted: Bool? = nil
    var action: (label: String, run: () -> Void)? = nil

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: icon)
                .font(.system(size: 44, weight: .regular))
                .foregroundStyle(Palette.accent)
                .symbolRenderingMode(.hierarchical)
            Text(title).font(.title2.weight(.semibold)).multilineTextAlignment(.center)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 8)

            if let action {
                if granted == true {
                    Label("Allowed", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.callout.weight(.medium))
                } else {
                    Button(action.label) { action.run() }
                        .buttonStyle(ProminentActionStyle(tint: Palette.accent))
                        .frame(width: 220)
                }
            }
        }
    }
}

func prettyPath(_ path: String) -> String {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
}
