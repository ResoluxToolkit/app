import SwiftUI

/// Tokens do tema MEVOLIT, espelhando o `enum M` que o operador mantém no app
/// Mevolit (contraste alto, fundo quase preto, neon violeta/ciano/magenta).
/// Os valores hex aqui são cópia dos dele, não interpretação minha: mudar tom
/// sem ele pedir é mexer na identidade que ele já aprovou.
public enum Palette {
    public static let background = Color(.sRGB, red: 7 / 255, green: 6 / 255, blue: 11 / 255)
    public static let foreground = Color(.sRGB, red: 245 / 255, green: 243 / 255, blue: 255 / 255)
    public static let muted = Color(.sRGB, red: 148 / 255, green: 140 / 255, blue: 168 / 255)
    public static let hairline = Color.white.opacity(0.12)
    public static let border = Color.white.opacity(0.18)

    public static let assistantBackground = rgb(0x0A0A0D)
    public static let assistantBorder = Color.white.opacity(0.10)
    public static let textPrimary = rgb(0xF5F5F7)
    public static let textSecondary = rgb(0x9C9CA3)
    public static let textTertiary = rgb(0x6E6E75)
    public static let brand = rgb(0xF26B33)
    public static let success = rgb(0x30D158)
    public static let alert = rgb(0xFFD60A)
    public static let danger = rgb(0xFF453A)
    public static let info = rgb(0x64D2FF)
    public static let accentViolet = rgb(0xBF5AF2)

    public static let deepViolet = rgb(0x7C3AED)
    public static let violet = rgb(0xA855F7)
    public static let magenta = rgb(0xEC4899)
    public static let cyan = rgb(0x06B6D4)
    public static let teal = rgb(0x14B8A6)
    public static let blue = rgb(0x3B82F6)
    public static let green = rgb(0x10B981)
    public static let amber = rgb(0xF59E0B)
    public static let coral = rgb(0xF43F5E)

    /// Vidro translúcido com leve coloração violeta para refratar a aurora.
    public static let glass = LinearGradient(
        colors: [rgb(0x1F1635).opacity(0.55), rgb(0x0E0A1A).opacity(0.40)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing)

    public static let primaryGradient = LinearGradient(
        colors: [violet, cyan],
        startPoint: .topLeading,
        endPoint: .bottomTrailing)

    private static func rgb(_ value: UInt32) -> Color {
        Color(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255)
    }
}
