import AppKit
import Resolume
import ResoluxDesignSystem
import SwiftUI

/// Vitrine read-only do Arena: recebe composicao, clips, contador e status.
/// Nenhuma rota de escrita aqui — tudo que passa vem de `GET /composition`.
@MainActor
public final class ArenaMonitorModel: ObservableObject {
    public struct Cell: Identifiable, Equatable {
        public var id: String { "\(layer).\(column)" }
        public let layer: Int
        public let column: Int
        public let name: String
        public let filled: Bool
        public let active: Bool

        public init(layer: Int, column: Int, name: String, filled: Bool, active: Bool) {
            self.layer = layer
            self.column = column
            self.name = name
            self.filled = filled
            self.active = active
        }
    }

    @Published public private(set) var cells: [Cell] = []
    @Published public private(set) var connected = false
    @Published public private(set) var lastSuccessfulPoll: Date?
    @Published public private(set) var activeClipName: String?
    @Published public private(set) var activeSeconds: Int = 0
    @Published public private(set) var thumbnailImages: [String: NSImage] = [:]
    @Published public private(set) var observedPort: Int?

    private var activeAddress: String?
    private var activeStartedAt: Date?
    private var pollTask: Task<Void, Never>?
    private var thumbnailSources: [String: ThumbnailSource] = [:]
    private var thumbnailTasks: [String: Task<Void, Never>] = [:]
    private var rest = ArenaREST(endpoint: .localhost(port: 8080))
    private let portObserver: ArenaRESTPortObserver
    private let makeREST: @Sendable (Int) -> ArenaREST

    private struct ThumbnailSource: Equatable {
        let id: Int
        let stamp: String
    }

    public init(
        portObserver: ArenaRESTPortObserver = ArenaRESTPortObserver(),
        makeREST: @escaping @Sendable (Int) -> ArenaREST = { ArenaREST(endpoint: .localhost(port: $0)) }) {
        self.portObserver = portObserver
        self.makeREST = makeREST
    }

    public func start() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            await self?.pollLoop()
        }
    }

    public func stop() {
        pollTask?.cancel()
        pollTask = nil
        thumbnailTasks.values.forEach { $0.cancel() }
        thumbnailTasks.removeAll()
    }

    private func pollLoop() async {
        while !Task.isCancelled {
            await pollOnce()
            try? await Task.sleep(for: .seconds(1))
        }
    }

    func pollOnce() async {
        do {
            if observedPort == nil {
                let port = try await portObserver.observe()
                observedPort = port
                rest = makeREST(port)
            }
            let composition = try await rest.composition()
            let slots = TimelineCalculator.slots(from: composition)
            let newCells = slots.map { slot in
                Cell(
                    layer: slot.layer,
                    column: slot.column,
                    name: slot.name,
                    filled: slot.content != .vazio,
                    active: slot.state == .reproduzindo)
            }
            cells = newCells
            connected = true
            lastSuccessfulPoll = .now
            loadThumbnails(for: composition, cells: newCells)

            if let active = newCells.first(where: { $0.active }) {
                let address = active.id
                if address != activeAddress {
                    activeAddress = address
                    activeStartedAt = .now
                    activeSeconds = 0
                } else if let started = activeStartedAt {
                    activeSeconds = Int(Date.now.timeIntervalSince(started))
                }
                activeClipName = active.name
            } else {
                activeClipName = nil
                activeAddress = nil
                activeSeconds = 0
            }
        } catch {
            connected = false
            observedPort = nil
        }
    }

    private func loadThumbnails(for composition: MCPValue, cells: [Cell]) {
        let sources = thumbnailSources(from: composition)
        let desiredAddresses = Set(cells.map(\.id))

        for (address, task) in thumbnailTasks where !desiredAddresses.contains(address) {
            task.cancel()
            thumbnailTasks.removeValue(forKey: address)
        }
        thumbnailSources = thumbnailSources.filter { desiredAddresses.contains($0.key) }

        for cell in cells {
            guard let source = sources[cell.id] else { continue }
            if thumbnailSources[cell.id] == source, thumbnailImages[cell.id] != nil {
                continue
            }

            thumbnailTasks[cell.id]?.cancel()
            thumbnailSources[cell.id] = source
            let model = self
            thumbnailTasks[cell.id] = Task {
                await model.fetchThumbnail(cellID: cell.id, source: source)
            }
        }
    }

    private func thumbnailSources(from composition: MCPValue) -> [String: ThumbnailSource] {
        guard let layers = composition["layers"]?.arrayValue else { return [:] }
        var sources: [String: ThumbnailSource] = [:]

        for (layerIndex, layer) in layers.enumerated() {
            guard let clips = layer["clips"]?.arrayValue else { continue }
            for (columnIndex, clip) in clips.enumerated() {
                let thumbnail = clip["thumbnail"]
                guard thumbnail?["is_default"]?.boolValue == false,
                      let id = thumbnail?["id"]?.intValue,
                      let stamp = thumbnail?["last_update"]?.stringValue,
                      stamp != "0" else { continue }

                sources["\(layerIndex + 1).\(columnIndex + 1)"] = ThumbnailSource(
                    id: id,
                    stamp: stamp)
            }
        }
        return sources
    }

    private func fetchThumbnail(cellID: String, source: ThumbnailSource) async {
        do {
            let data = try await rest.thumbnailData(clipID: source.id, stamp: source.stamp)
            guard thumbnailSources[cellID] == source, !Task.isCancelled else { return }
            thumbnailImages[cellID] = NSImage(data: data)
            thumbnailTasks.removeValue(forKey: cellID)
        } catch {
            guard !Task.isCancelled else { return }
            thumbnailSources.removeValue(forKey: cellID)
            thumbnailTasks.removeValue(forKey: cellID)
        }
    }
}

public struct ArenaMonitorView: View {
    @StateObject private var model = ArenaMonitorModel()

    public init() {}

    public var body: some View {
        ScreenShell(
            title: "Monitor Arena",
            subtitle: statusDetail,
            symbol: "info.triangle.fill",
            tone: .cyan,
            status: model.connected ? "conectado" : "offline",
            statusTone: model.connected ? .green : .coral) {
                ScrollView {
                    VStack(spacing: 18) {
                        liveInfo
                        gridCard
                    }
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
        VStack(alignment: .leading, spacing: 10) {
            if let active = model.activeClipName {
                HStack(spacing: 8) {
                    Image(systemName: "play.circle.fill")
                        .foregroundStyle(Palette.cyan)
                    Text(active)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer()
                    Text(format(seconds: model.activeSeconds))
                        .font(.system(.title3, design: .monospaced).weight(.semibold))
                        .foregroundStyle(Palette.cyan)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .modifier(LiveTimerGlassModifier())
                        .contentTransition(.numericText())
                }
            } else {
                Label("nenhum clip tocando", systemImage: "pause.circle")
                    .foregroundStyle(Palette.muted)
            }

            if let last = model.lastSuccessfulPoll {
                Text("último poll \(last.formatted(date: .omitted, time: .standard))")
                    .font(.caption)
                    .foregroundStyle(Palette.muted)
            }
        }
        .padding(.horizontal, 4)
    }

    private var gridCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                Label("Grade de clips", systemImage: "square.grid.3x3")
                    .font(.headline)
                if model.cells.isEmpty {
                    Text(model.connected ? "grade vazia" : "aguardando Arena…")
                        .font(.footnote)
                        .foregroundStyle(Palette.muted)
                } else {
                    ForEach(layerGroups, id: \.layer) { group in
                        VStack(alignment: .leading, spacing: 6) {
                            Text("camada \(group.layer)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Palette.muted)
                            LazyVGrid(
                                columns: Array(
                                    repeating: GridItem(.flexible(), spacing: 8),
                                    count: min(group.cells.count, 9)),
                                spacing: 8) {
                    ForEach(group.cells) { cell in
                        ClipCellView(cell: cell, thumbnail: model.thumbnailImages[cell.id])
                    }
                                }
                        }
                    }
                }
            }
        }
    }

    private var layerGroups: [(layer: Int, cells: [ArenaMonitorModel.Cell])] {
        Dictionary(grouping: model.cells, by: { $0.layer })
            .sorted { $0.key < $1.key }
            .map { ($0.key, $0.value.sorted { $0.column < $1.column }) }
    }

    private func format(seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

private struct ClipCellView: View {
    let cell: ArenaMonitorModel.Cell
    let thumbnail: NSImage?

    private var thumbnailImage: Image? {
        thumbnail.map(Image.init(nsImage:))
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        Group {
            if let thumbnailImage {
                thumbnailImage
                    .resizable()
                    .scaledToFill()
            } else {
                Text(cell.filled ? cell.name : "—")
                    .font(.system(size: 11, weight: cell.active ? .bold : .regular))
                    .foregroundStyle(cell.filled ? .white : Palette.muted)
                    .lineLimit(1)
                    .padding(.horizontal, 6)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 54)
            .modifier(ClipCellGlassModifier(cell: cell, shape: shape))
            .contentTransition(.opacity)
    }
}

private struct ClipCellGlassModifier: ViewModifier {
    let cell: ArenaMonitorModel.Cell
    let shape: RoundedRectangle

    func body(content: Content) -> some View {
        if #available(macOS 26.0, iOS 26.0, *) {
            if cell.active {
                content
                    .glassEffect(.regular.tint(Palette.violet.opacity(0.35)), in: shape)
                    .overlay(shape.strokeBorder(Palette.violet, lineWidth: 1.5))
            } else if cell.filled {
                content
                    .glassEffect(.clear.tint(Palette.cyan.opacity(0.12)), in: shape)
                    .overlay(shape.strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
            } else {
                content
                    .background(shape.fill(Color.white.opacity(0.04)))
                    .overlay(shape.strokeBorder(Color.white.opacity(0.06), lineWidth: 1))
            }
        } else {
            content
                .background(
                    shape.fill(cell.active ? Palette.violet.opacity(0.35)
                              : cell.filled ? Palette.cyan.opacity(0.14) : Color.white.opacity(0.04))
                )
                .overlay(
                    shape.strokeBorder(
                        cell.active ? Palette.violet : Color.white.opacity(0.10),
                        lineWidth: cell.active ? 1.5 : 1)
                )
        }
    }
}

private struct LiveTimerGlassModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, iOS 26.0, *) {
            content
                .glassEffect(.clear.tint(Palette.cyan.opacity(0.12)), in: Capsule())
                .overlay(Capsule().strokeBorder(Palette.cyan.opacity(0.25), lineWidth: 1))
        } else {
            content
                .background(Capsule().fill(Palette.cyan.opacity(0.1)))
        }
    }
}
