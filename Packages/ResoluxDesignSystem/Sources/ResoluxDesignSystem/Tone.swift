import SwiftUI

/// Os mesmos tons do Mevolit: componente escolhe um `Tone`, nunca um hex solto.
public enum Tone: Hashable, Sendable {
    case blue, violet, coral, amber, green, cyan, neutral

    public var tint: Color {
        switch self {
        case .blue: Palette.blue
        case .violet: Palette.violet
        case .coral: Palette.coral
        case .amber: Palette.amber
        case .green: Palette.green
        case .cyan: Palette.cyan
        case .neutral: Palette.muted
        }
    }

    public var fill: Color { tint.opacity(0.20) }
}
