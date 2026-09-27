public enum PlatformTarget: String, Sendable, Codable, CaseIterable, Comparable {
    case macOS
    case iOS

    public static func < (lhs: PlatformTarget, rhs: PlatformTarget) -> Bool {
        lhs.sortRank < rhs.sortRank
    }

    private var sortRank: Int {
        switch self {
        case .macOS: 0
        case .iOS: 1
        }
    }
}

extension PlatformTarget {
    public static var current: PlatformTarget {
        #if os(macOS)
        .macOS
        #elseif os(iOS)
        .iOS
        #else
        fatalError("ResoluxCore: plataforma não suportada")
        #endif
    }
}
