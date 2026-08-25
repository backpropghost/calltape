import SwiftUI
import AppKit

/// A titled group of rows in a single rounded card, matching modern macOS 26
/// System Settings: an uppercase caption header above a grouped container.
struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .kerning(0.4)
                .padding(.leading, Space.xs)
            VStack(spacing: 0) { content }
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08))
                )
        }
    }
}

/// One row inside a SettingsSection: an optional tinted icon, a title with optional
/// subtitle, and any trailing control (toggle, picker, slider, button).
struct SettingRow<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    var icon: String? = nil
    var tint: Color = .secondary
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: Space.m) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 15))
                    .foregroundStyle(tint)
                    .frame(width: 24)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body)
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: Space.m)
            trailing
        }
        .padding(.horizontal, Space.l)
        .padding(.vertical, Space.m)
    }
}

/// A hairline divider inset to line up under the row text, like Apple's grouped lists.
struct RowDivider: View {
    var body: some View {
        Divider().padding(.leading, Space.l)
    }
}
