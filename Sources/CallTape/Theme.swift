import SwiftUI
import AppKit

/// Small visual helpers so the UI reads as one system in both light and dark.
extension View {
    /// Liquid Glass, for elements that genuinely float over content (macOS 26+).
    @ViewBuilder
    func glassCard(cornerRadius: CGFloat = 14) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(macOS 26, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
        }
    }

    /// A solid grouped-content card, for stationary panels (the correct choice over
    /// glass for things that sit on the window background).
    func surfaceCard(cornerRadius: CGFloat = 14) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return self
            .background(shape.fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(shape.strokeBorder(Color.primary.opacity(0.08)))
    }
}

enum Palette {
    static let accent = Color.accentColor
    static let recording = Color(red: 0.90, green: 0.26, blue: 0.30)
    static let idle = Color.secondary

    /// Consistent tint per call source, used by pills, avatars and the sidebar.
    static func tint(for kind: Recording.SourceKind) -> Color {
        switch kind {
        case .whatsapp: return Color(red: 0.15, green: 0.72, blue: 0.40) // WhatsApp green
        case .cellular: return .blue
        case .manual:   return .orange
        case .unknown:  return .gray
        }
    }
}

/// One 8pt-based spacing scale so everything lines up on the same grid.
enum Space {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 24
}
