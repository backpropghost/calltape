import SwiftUI
import AppKit

struct AboutPane: View {
    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Image(systemName: "recordingtape")
                    .font(.system(size: 48, weight: .regular))
                    .foregroundStyle(Palette.accent)
                    .symbolRenderingMode(.hierarchical)
                Text("CallTape").font(.title.weight(.semibold))
                Text("Version \(version)").font(.caption).foregroundStyle(.secondary)

                VStack(spacing: 10) {
                    Label("Everything stays on your Mac", systemImage: "lock.fill")
                        .font(.headline)
                    Text("CallTape has no account and no server. Your recordings and their details never leave this Mac and are never uploaded anywhere. They're plain files in the folder you chose, and you can move or delete them anytime.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(18)
                .frame(maxWidth: 420)
                .surfaceCard()

                VStack(spacing: 10) {
                    Label("Support CallTape", systemImage: "heart.fill")
                        .font(.headline).foregroundStyle(Palette.accent)
                    Text("CallTape is free, and it stays that way. If it earned a spot in your menu bar, you can help keep it going. Right now it goes toward an Apple Developer ID, so installs stop showing the scary warning.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        if let url = URL(string: "https://github.com/sponsors/backpropghost") {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        Label("Sponsor on GitHub", systemImage: "heart")
                    }
                    .buttonStyle(ProminentActionStyle(tint: Palette.accent))
                    .padding(.top, 4)
                }
                .padding(18)
                .frame(maxWidth: 420)
                .surfaceCard()

                HStack(spacing: 12) {
                    Button("View Logs") {
                        NSWorkspace.shared.activateFileViewerSelecting([Log.fileURL])
                    }
                    Button("Open Recordings Folder") {
                        NSWorkspace.shared.open(AppSettings.shared.folderURL)
                    }
                }
                .buttonStyle(HoverButtonStyle())

                VStack(alignment: .leading, spacing: 8) {
                    Label("Disclaimer", systemImage: "exclamationmark.shield")
                        .font(.subheadline.weight(.semibold))
                    Text(Legal.disclaimer)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(16)
                .frame(maxWidth: 460)
                .surfaceCard()
            }
            .frame(maxWidth: .infinity)
            .padding(30)
        }
    }
}
