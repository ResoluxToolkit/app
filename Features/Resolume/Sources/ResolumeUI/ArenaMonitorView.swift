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

    private var activeAddress: String?
    private var activeStartedAt: Date?
    private var pollTask: Task<Void, Never>?
    private let rest = ArenaREST()

    public init() {}

    public func start() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            await self?.pollLoop()
        }
    }

    public func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func pollLoop() async {
        while !Task.isCancelled {
            await pollOnce()
            try? await Task.sleep(for: .seconds(1))
        }
    }

    private func pollOnce() async {
        do {
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
            symbol: "waveform",
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
        model.connected ? "Arena REST · leitura pura" : "aguardando Arena…"
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
                                        ClipCellView(cell: cell)
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

    var body: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(cell.active ? Palette.violet.opacity(0.35)
                  : cell.filled ? Palette.cyan.opacity(0.14) : Color.white.opacity(0.04))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        cell.active ? Palette.violet : Color.white.opacity(0.10),
                        lineWidth: cell.active ? 1.5 : 1)
            }
            .frame(minHeight: 54)
            .overlay {
                Text(cell.filled ? cell.name : "—")
                    .font(.system(size: 11, weight: cell.active ? .bold : .regular))
                    .foregroundStyle(cell.filled ? .white : Palette.muted)
                    .lineLimit(1)
                    .padding(.horizontal, 6)
            }
            .contentTransition(.opacity)
    }
}
