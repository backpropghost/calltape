import SwiftUI

/// A subtle fill that appears on hover and darkens on press. The standard feel
/// for secondary and borderless controls. Also shows the link pointer.
struct HoverButtonStyle: ButtonStyle {
    var padding: EdgeInsets = EdgeInsets(top: 5, leading: 8, bottom: 5, trailing: 8)
    func makeBody(configuration: Configuration) -> some View {
        Hover(configuration: configuration, padding: padding)
    }

    private struct Hover: View {
        let configuration: ButtonStyle.Configuration
        let padding: EdgeInsets
        @State private var hovering = false
        var body: some View {
            configuration.label
                .padding(padding)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.primary.opacity(hovering ? 0.10 : 0))
                )
                .contentShape(Rectangle())
                .opacity(configuration.isPressed ? 0.6 : 1)
                .onHover { hovering = $0 }
                
        }
    }
}

/// A full-width primary action that lifts slightly on hover.
struct ProminentActionStyle: ButtonStyle {
    var tint: Color
    func makeBody(configuration: Configuration) -> some View {
        ActionBody(configuration: configuration, tint: tint)
    }

    private struct ActionBody: View {
        let configuration: ButtonStyle.Configuration
        let tint: Color
        @State private var hovering = false
        var body: some View {
            configuration.label
                .fontWeight(.semibold)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(tint.opacity(configuration.isPressed ? 0.85 : (hovering ? 1.0 : 0.92)))
                )
                .scaleEffect(configuration.isPressed ? 0.98 : 1)
                .animation(.easeOut(duration: 0.12), value: hovering)
                .onHover { hovering = $0 }
                
        }
    }
}
