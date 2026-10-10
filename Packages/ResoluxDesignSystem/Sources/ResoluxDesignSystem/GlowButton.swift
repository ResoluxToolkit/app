import SwiftUI

// Portado do `GlowButton` do Mevolit: botao de acao principal com
// borda de luz quando esta trabalhando.
public struct GlowButton: View {
    public var title: String
    public var symbol: String = "arrow.clockwise"
    public var spinning: Bool = false
    public var beam: Bool = true
    public var action: () -> Void

    // Init declarado dentro do struct: o memberwise sintetizado de um struct
    // publico e apenas interno, e a tela de chat vive em outro modulo.
    public init(title: String, symbol: String = "arrow.clockwise",
                spinning: Bool = false, beam: Bool = true,
                action: @escaping () -> Void) {
        self.title = title
        self.symbol = symbol
        self.spinning = spinning
        self.beam = beam
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .rotationEffect(.degrees(spinning ? 360 : 0))
                    .animation(spinning ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: spinning)
                Text(title)
                    .font(.system(size: 15, weight: .bold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .modifier(GlowButtonGlassModifier(spinning: spinning))
            .overlay {
                if beam {
                    BeamStroke(cornerRadius: 24, lineWidth: 1.8, active: spinning, duration: 2.5)
                        .clipShape(Capsule())
                }
            }
            .shadow(color: Palette.deepViolet.opacity(spinning ? 0.6 : 0.25), radius: 16, y: 6)
        }
        .buttonStyle(.plain)
    }
}

private struct GlowButtonGlassModifier: ViewModifier {
    let spinning: Bool

    func body(content: Content) -> some View {
        if #available(macOS 26.0, iOS 26.0, *) {
            content
                .glassEffect(.regular.interactive().tint(Palette.deepViolet.opacity(0.35)), in: Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(0.4), Color.white.opacity(0.1)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                )
        } else {
            content
                .background(
                    LinearGradient(
                        colors: [Color.white.opacity(0.22), Color.white.opacity(0.08)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(0.4), Color.white.opacity(0.1)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                )
        }
    }
}
