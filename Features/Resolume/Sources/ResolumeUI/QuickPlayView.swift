import ResoluxDesignSystem
import SwiftUI

public struct QuickPlayView: View {
    @StateObject private var model = ArenaMonitorModel()

    public init() {}

    public var body: some View {
        ScreenShell(
            title: "Quick Play",
            subtitle: statusDetail,
            symbol: "play.rectangle.on.rectangle",
            tone: .violet,
            status: model.connected ? "conectado" : "offline",
            statusTone: model.connected ? .green : .coral) {
                ScrollView {
                    VStack(spacing: 18) {
                        liveInfo
                        grid
                    }
                    .frame(maxWidth: 900)
                    .frame(maxWidth: .infinity)
                }
            }
        .frame(minWidth: 720, minHeight: 480)
        .onAppear { model.start() }
        .onDisappear { model.stop() }
    }

    private var statusDetail: String {
        guard model.connected else { return "aguardando Arena…" }
        if let port = model.observedPort {
            return "Arena REST :\(port) · leitura pura"
        }
        return "Arena REST · leitura pura"
    }

    private var liveInfo: some View {
        GlassCard(cornerRadius: 22) {
            VStack(alignment: .leading, spacing: 10) {
                Label("Grade de clips", systemImage: "square.grid.3x3")
                    .font(.headline)
                Text(model.cells.isEmpty
                     ? (model.connected ? "grade vazia" : "aguardando Arena…")
                     : "clips \(model.cells.count) · thumbnails \(model.thumbnailImages.count)")
                    .font(.footnote)
                    .foregroundStyle(Palette.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var grid: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3),
            spacing: 12) {
                ForEach(layerGroups, id: \.layer) { group in
                    ForEach(group.cells) { cell in
                        QuickPlayTile(
                            cell: cell,
                            thumbnail: model.thumbnailImages[cell.id])
                    }
                }
            }
    }

    private var layerGroups: [(layer: Int, cells: [ArenaMonitorModel.Cell])] {
        Dictionary(grouping: model.cells, by: \.layer)
            .sorted { $0.key < $1.key }
            .map { ($0.key, $0.value.sorted { $0.column < $1.column }) }
    }
}

private struct QuickPlayTile: View {
    let cell: ArenaMonitorModel.Cell
    let thumbnail: NSImage?

    private var thumbnailImage: Image? {
        thumbnail.map(Image.init(nsImage:))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Group {
                if let thumbnailImage {
                    thumbnailImage
                        .resizable()
                        .scaledToFill()
                } else {
                    ZStack {
                        Rectangle().fill(Color.white.opacity(0.04))
                        Image(systemName: cell.filled ? "photo.on.rectangle" : "square.dashed")
                            .font(.title2)
                            .foregroundStyle(cell.filled ? Palette.cyan : Palette.muted)
                    }
                }
            }
            .frame(height: 96)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(cell.active ? Palette.violet : Color.white.opacity(0.10),
                                  lineWidth: cell.active ? 1.5 : 1)
            )
            .allowsHitTesting(false)

            HStack(spacing: 6) {
                Image(systemName: cell.active ? "play.fill" : "photo.on.rectangle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(cell.active ? Palette.cyan : Palette.muted)
                Text("camada \(cell.layer)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Palette.muted)
                Spacer()
            }

            Text(cell.name)
                .font(.subheadline.weight(cell.active ? .bold : .medium))
                .foregroundStyle(.white)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .modifier(QuickPlayTileModifier(active: cell.active))
    }
}

private struct QuickPlayTileModifier: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)

        if #available(macOS 26.0, iOS 26.0, *) {
            content
                .glassEffect(
                    .regular.tint(active ? Palette.violet.opacity(0.35) : Palette.cyan.opacity(0.12)),
                    in: shape)
                .overlay(shape.strokeBorder(active ? Palette.violet : Color.white.opacity(0.12), lineWidth: 1))
        } else {
            content
                .background(
                    shape.fill(active ? Palette.violet.opacity(0.35) : Palette.cyan.opacity(0.14)))
                .overlay(shape.strokeBorder(active ? Palette.violet : Color.white.opacity(0.1), lineWidth: 1))
        }
    }
}
