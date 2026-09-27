import SwiftUI

public struct Theme: Sendable {
    public let accentHex: String
    public let cornerRadius: CGFloat

    public init(accentHex: String = "#3E6BFF", cornerRadius: CGFloat = 10) {
        self.accentHex = accentHex
        self.cornerRadius = cornerRadius
    }

    public static let shared = Theme()
}

extension ShapeStyle where Self == Color {
    public static var resoluxAccent: Color {
        Color(hex: Theme.shared.accentHex) ?? .accentColor
    }
}

extension Color {
    public init?(hex: String) {
        var digits = hex
        if digits.hasPrefix("#") { digits.removeFirst() }
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        self = Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255)
    }
}
