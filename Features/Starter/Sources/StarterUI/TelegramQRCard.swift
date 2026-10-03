import ResoluxDesignSystem
import SwiftUI

public struct TelegramQRCard: View {
    private static let matrix: [String] = [
    "111111100001010011011110101111111",
    "100000100111000111001010101000001",
    "101110101101101100110101101011101",
    "101110101000000110001101101011101",
    "101110100101101011111011001011101",
    "100000100110001101001000101000001",
    "111111101010101010101010101111111",
    "000000000111010101100001000000000",
    "000110110000000011001001100001100",
    "010111001111000001111011010111000",
    "100110101011100001110101011101101",
    "111100000000101100001000010110100",
    "000010100111110101101110111010001",
    "100101011101111010110111010001110",
    "100010101011011000111000100010100",
    "001101011100100001111001101010110",
    "101000110110100100000001011001100",
    "111101001110111010101010101111011",
    "111000101100000100000011000111101",
    "000111001100100011111011110011101",
    "110000101010000101101000001101011",
    "111101001100000010111110101111000",
    "101001101101000011100001001001011",
    "100110011101001110100001100100111",
    "111001111001011001101001111111000",
    "000000001010101010101100100011100",
    "111111101111111001001001101011100",
    "100000100101010101011111100011110",
    "101110101011011011111111111110010",
    "101110101101000111000110010100010",
    "101110100011001101000000000011011",
    "100000100101011001111011100001011",
    "111111100110111100011001101010100",
    ]

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "paperplane.fill")
                    .foregroundStyle(Palette.cyan)
                    .font(.title3)
                Text("Canal no Telegram")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Palette.foreground)
                Spacer()
                Text("escaneia")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Palette.muted)
            }

            HStack(spacing: 16) {
                QRMatrixView(matrix: Self.matrix)
                    .frame(width: 128, height: 128)
                    .background(Palette.foreground.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 6) {
                    Text("@ResoluxToolkit")
                        .font(.headline)
                        .foregroundStyle(Palette.foreground)
                    Text("Canal do projeto no Telegram.")
                        .font(.footnote)
                        .foregroundStyle(Palette.muted)
                    Link("Abrir canal", destination: URL(string: "https://t.me/ResoluxToolkit")!)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Palette.cyan)
                }
                Spacer(minLength: 0)
            }
        }
    }
}

private struct QRMatrixView: View {
    let matrix: [String]

    var body: some View {
        Canvas { context, size in
            let cellSize = size.width / CGFloat(matrix.count)
            for (row, line) in matrix.enumerated() {
                for (column, symbol) in line.enumerated() where symbol == "1" {
                    let rect = CGRect(
                        x: CGFloat(column) * cellSize,
                        y: CGFloat(row) * cellSize,
                        width: cellSize,
                        height: cellSize)
                    context.fill(Path(rect), with: .color(Palette.foreground))
                }
            }
        }
    }
}
