import SwiftUI

public struct ScreenShell<Content: View>: View {
    private let title: String
    private let subtitle: String
    private let symbol: String
    private let tone: Tone
    private let status: String?
    private let statusTone: Tone
    private let content: () -> Content

    public init(
        title: String,
        subtitle: String,
        symbol: String,
        tone: Tone,
        status: String? = nil,
        statusTone: Tone = .green,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.tone = tone
        self.status = status
        self.statusTone = statusTone
        self.content = content
    }

    public var body: some View {
        ZStack {
            AuroraBackground()

            VStack(spacing: 0) {
                header

                content()
                    .padding(.top, 6)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
            }
        }
        .foregroundStyle(Palette.foreground)
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(spacing: 12) {
            ToneIcon(symbol: symbol, tone: tone)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Palette.muted)
            }

            Spacer(minLength: 8)

            if let status {
                StatusPill(text: status, tone: statusTone)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}
