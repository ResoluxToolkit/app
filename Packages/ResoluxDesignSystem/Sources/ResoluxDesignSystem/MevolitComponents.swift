import BorderBeamKit
import SwiftUI

// Portado de `Mevolit/Components.swift` do operador: geometria, opacidades e
// tempos sao exatamente os dele. Nao reinterpretar sem ele pedir.
// Extraido mecanicamente do arquivo dele; so visibilidade (public) e os nomes
// de cor (`M.` -> `Palette.`) foram adaptados para uso entre modulos.

public struct BeamStroke: View {
    public var cornerRadius: CGFloat = 24
    public var lineWidth: CGFloat = 1.8
    public var active: Bool = true
    public var duration: Double = 3.5

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Init declarado aqui (e nao em extensao) para ser publico entre modulos:
    // o memberwise sintetizado de um struct publico e so interno.
    public init(cornerRadius: CGFloat = 24, lineWidth: CGFloat = 1.8,
                active: Bool = true, duration: Double = 3.5) {
        self.cornerRadius = cornerRadius
        self.lineWidth = lineWidth
        self.active = active
        self.duration = duration
    }

    public var body: some View {
        GeometryReader { geo in
            if active && !reduceMotion {
                TimelineView(.animation) { context in
                    let span = max(geo.size.width, geo.size.height) * 2.2
                    let t = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: duration) / duration
                    AngularGradient(
                        colors: [
                            .clear,
                            Palette.violet.opacity(0.9),
                            .white,
                            Palette.cyan.opacity(0.9),
                            .clear
                        ],
                        center: .center,
                        startAngle: .degrees(t * 360),
                        endAngle: .degrees(t * 360 + 90)
                    )
                    .frame(width: span, height: span)
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
                    .mask(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(Color.white, lineWidth: lineWidth)
                    )
                    .shadow(color: Palette.violet.opacity(0.7), radius: 6)
                }
            } else if active {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(colors: [Palette.violet.opacity(0.8), Palette.cyan.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: lineWidth
                    )
            }
        }
        .allowsHitTesting(false)
    }
}

public struct GlassCard<Content: View>: View {
    public var beam: Bool = false
    public var beamActive: Bool = true
    public var cornerRadius: CGFloat = 24
    @ViewBuilder public var content: () -> Content

    public init(beam: Bool = false, beamActive: Bool = true, cornerRadius: CGFloat = 24, @ViewBuilder content: @escaping () -> Content) {
        self.beam = beam
        self.beamActive = beamActive
        self.cornerRadius = cornerRadius
        self.content = content
    }

    public var body: some View {
        if beam {
            card.borderBeam(
                .md,
                colorVariant: .ocean,
                theme: .dark,
                active: beamActive,
                borderRadius: cornerRadius
            )
        } else {
            card
        }
    }

    private var card: some View {
        content()
            .padding(20)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .environment(\.colorScheme, .dark)
                    .opacity(0.72)
            }
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.06), Palette.deepViolet.opacity(0.04), Color.black.opacity(0.25)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                // Borda de refração de luz (especular)
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            stops: [
                                .init(color: .white.opacity(0.32), location: 0.0),
                                .init(color: .white.opacity(0.06), location: 0.35),
                                .init(color: Palette.violet.opacity(0.35), location: 0.75),
                                .init(color: .white.opacity(0.12), location: 1.0)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .shadow(color: Color.black.opacity(0.4), radius: 24, x: 0, y: 12)
    }
}

public struct ToneIcon: View {
    public let symbol: String
    public let tone: Tone
    public var size: CGFloat = 42

    public init(symbol: String, tone: Tone, size: CGFloat = 42) {
        self.symbol = symbol
        self.tone = tone
        self.size = size
    }

    public var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.30, style: .continuous)
                .fill(tone.tint.opacity(0.16))
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.30, style: .continuous)
                        .strokeBorder(tone.tint.opacity(0.32), lineWidth: 1)
                )
            Image(systemName: symbol)
                .font(.system(size: size * 0.44, weight: .semibold))
                .foregroundStyle(tone.tint)
        }
        .frame(width: size, height: size)
    }
}

public struct StatusPill: View {
    public var text: String = "All Clear"
    // No Mevolit a pilula e sempre verde ("All Clear"). Aqui o estado real do
    // Arena muda -- conectando precisa ser amber, falha coral -- entao o tom e
    // parametro, mantendo o verde como padrao dele.
    public var tone: Tone = .green

    public init(text: String, tone: Tone = .green) {
        self.text = text
        self.tone = tone
    }

    public var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(tone.tint)
                .frame(width: 8, height: 8)
                .shadow(color: tone.tint, radius: 5)
            Text(text)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
                .opacity(0.7)
        }
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.2), lineWidth: 1))
        .fixedSize()
    }
}

public struct ThinkingOrb: View {
    @State private var pulse = false

    public init() {}

    public var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [Palette.violet.opacity(0.9), Palette.cyan.opacity(0.4), .clear], center: .center, startRadius: 1, endRadius: 14))
                .frame(width: 26, height: 26)
                .blur(radius: pulse ? 2 : 4)
                .opacity(pulse ? 0.75 : 1)
            Circle()
                .fill(LinearGradient(colors: [Palette.violet, Palette.cyan], startPoint: .top, endPoint: .bottom))
                .frame(width: 9, height: 9)
                .shadow(color: Palette.violet.opacity(0.9), radius: 6)
                .offset(y: pulse ? -1.5 : 1.5)
        }
        .frame(width: 22, height: 22)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulse = true }
        }
    }
}
