import Resolume
import ResoluxDesignSystem
import SwiftUI

@MainActor
public final class SystemMonitorModel: ObservableObject {
    @Published public private(set) var hardware: SystemHardware?
    @Published public private(set) var cpu: CPULoad?
    @Published public private(set) var memory: MemoryUsage?
    @Published public private(set) var gpu: GPUMetrics?
    @Published public private(set) var ports: [SystemPortEndpoint] = []
    @Published public private(set) var network: NetworkSample?
    @Published public private(set) var throughputs: [NetworkThroughput] = []
    @Published public private(set) var networkTotals: NetworkTotals?
    @Published public private(set) var ndi: NDIStatus?
    @Published public private(set) var lastSuccessfulPoll: Date?
    @Published public private(set) var errorMessage: String?

    private var pollTask: Task<Void, Never>?
    private let source: any SystemMonitorSource
    private let networkSource: any NetworkMonitorSource
    private let ndiProbe: NDIProbe
    private var ndiCycle = 0

    public init(
        source: any SystemMonitorSource = MachSystemMonitorSource(),
        networkSource: any NetworkMonitorSource = GetIfAddrsNetworkMonitorSource(),
        ndiProbe: NDIProbe = NDIProbe()
    ) {
        self.source = source
        self.networkSource = networkSource
        self.ndiProbe = ndiProbe
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
    }

    public func refresh() async {
        var next = snapshot
        var observedError: String?

        if next.hardware == nil {
            do { next.hardware = try await source.hardware() }
            catch { observedError = error.localizedDescription }
        }
        do { next.cpu = try await source.cpuLoad() ?? next.cpu }
        catch { observedError = error.localizedDescription }
        do { next.memory = try await source.memoryUsage() }
        catch { observedError = error.localizedDescription }
        do { next.gpu = try await source.gpuMetrics() ?? next.gpu }
        catch { observedError = error.localizedDescription }
        do { next.ports = try await source.ports() }
        catch { observedError = error.localizedDescription }
        do {
            let sample = try await networkSource.sample()
            if let previous = next.network {
                let rates = NetworkMonitorMath.throughput(current: sample, previous: previous)
                next.throughputs = rates
                next.networkTotals = NetworkMonitorMath.totals(from: sample, throughputs: rates)
            }
            next.network = sample
        }
        catch { observedError = error.localizedDescription }
        ndiCycle += 1
        if ndiCycle % 5 == 1 {
            next.ndi = await ndiProbe.status()
        }

        snapshot = next
        errorMessage = observedError
        if observedError == nil {
            lastSuccessfulPoll = Date()
        }
    }

    private var snapshot: SystemSnapshot {
        get {
            SystemSnapshot(
                hardware: hardware,
                cpu: cpu,
                memory: memory,
            gpu: gpu,
            ports: ports,
            network: network,
            throughputs: throughputs,
            networkTotals: networkTotals,
            ndi: ndi)
        }
        set {
            hardware = newValue.hardware
            cpu = newValue.cpu
            memory = newValue.memory
            gpu = newValue.gpu
            ports = newValue.ports
            network = newValue.network
            throughputs = newValue.throughputs
            networkTotals = newValue.networkTotals
            ndi = newValue.ndi
        }
    }

    private func pollLoop() async {
        while !Task.isCancelled {
            await refresh()
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
    }
}

private struct SystemSnapshot: Sendable, Equatable {
    var hardware: SystemHardware?
    var cpu: CPULoad?
    var memory: MemoryUsage?
    var gpu: GPUMetrics?
    var ports: [SystemPortEndpoint]
    var network: NetworkSample?
    var throughputs: [NetworkThroughput]
    var networkTotals: NetworkTotals?
    var ndi: NDIStatus?
}

public struct SystemMonitorView: View {
    @StateObject private var model = SystemMonitorModel()

    public init() {}

    public var body: some View {
        ScreenShell(
            title: "Sistema",
            subtitle: statusDetail,
            symbol: "cpu",
            tone: .violet,
            status: model.errorMessage == nil ? "leitura pura" : "falha parcial",
            statusTone: model.errorMessage == nil ? .green : .coral) {
                ScrollView {
                    LazyVStack(spacing: 18) {
                        if let error = model.errorMessage {
                            errorCard(error)
                        }
                        cpuCard
                        memoryCard
                        gpuCard
                        portsCard
                        networkCard
                        ndiCard
                    }
                }
            }
        .frame(minWidth: 720, minHeight: 480)
        .onAppear { model.start() }
        .onDisappear { model.stop() }
    }

    private var statusDetail: String {
        if let poll = model.lastSuccessfulPoll {
            return "Telemetria do host · \(poll.formatted(date: .omitted, time: .standard))"
        }
        return "Telemetria do host · conectando"
    }

    private var cpuCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                sectionHeader("CPU", symbol: "cpu", tone: .cyan)
                if let cpu = model.cpu {
                    Text(String(format: "%.1f%%", cpu.usagePercent))
                        .font(.system(size: 36, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                    meter(value: cpu.usagePercent / 100, tone: .cyan)
                    HStack(spacing: 16) {
                        metric("Usuário", value: String(format: "%.1f%%", cpu.userPercent))
                        metric("Sistema", value: String(format: "%.1f%%", cpu.systemPercent))
                        metric("Ocioso", value: String(format: "%.1f%%", cpu.idlePercent))
                    }
                } else {
                    Text("Medindo no próximo poll…")
                        .font(.footnote)
                        .foregroundStyle(Palette.muted)
                }

                if let hardware = model.hardware {
                    Text("\(hardware.cpuModel) · \(hardware.coreCount) cores")
                        .font(.caption)
                        .foregroundStyle(Palette.muted)
                }
            }
        }
    }

    private var memoryCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                sectionHeader("RAM", symbol: "memorychip", tone: .violet)
                if let memory = model.memory {
                    let percent = Double(memory.usedBytes) / Double(max(memory.totalBytes, 1)) * 100
                    Text("\(ByteCountFormatter.string(fromByteCount: Int64(memory.usedBytes), countStyle: .memory)) de \(ByteCountFormatter.string(fromByteCount: Int64(memory.totalBytes), countStyle: .memory))")
                        .font(.title3.weight(.semibold))
                    meter(value: percent / 100, tone: .violet)
                    HStack(spacing: 16) {
                        metric("Ativa", value: byteCount(memory.activeBytes))
                        metric("Wired", value: byteCount(memory.wiredBytes))
                        metric("Compressor", value: byteCount(memory.compressorBytes))
                        metric("Livre", value: byteCount(memory.freeBytes))
                    }
                } else {
                    Text("aguardando leitura…")
                        .font(.footnote)
                        .foregroundStyle(Palette.muted)
                }
            }
        }
    }

    private var gpuCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                sectionHeader("GPU", symbol: "sparkles.rectangle.stack", tone: .blue)
                if let gpu = model.gpu {
                    if let device = gpu.devicePercent {
                        Text("\(device)%")
                            .font(.system(size: 36, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                            .contentTransition(.numericText())
                        meter(value: Double(device) / 100, tone: .blue)
                    }
                    HStack(spacing: 16) {
                        if let renderer = gpu.rendererPercent {
                            metric("Renderer", value: "\(renderer)%")
                        }
                        if let tiler = gpu.tilerPercent {
                            metric("Tiler", value: "\(tiler)%")
                        }
                        if let used = gpu.usedBytes {
                            metric("Memória", value: byteCount(UInt64(used)))
                        }
                    }
                    if let name = gpu.name {
                        Text(name)
                            .font(.caption)
                            .foregroundStyle(Palette.muted)
                    }
                } else {
                    Text("GPU não exposta pelo ioreg")
                        .font(.footnote)
                        .foregroundStyle(Palette.muted)
                }
            }
        }
    }

    private var portsCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                sectionHeader("Portas e protocolos", symbol: "point.3.connected.trianglepath.dotted", tone: .green)
                protocolChips
                if model.ports.isEmpty {
                    Text("nenhuma porta local exposta")
                        .font(.footnote)
                        .foregroundStyle(Palette.muted)
                } else {
                    LazyVStack(spacing: 8) {
                        ForEach(model.ports) { port in
                            portRow(port)
                        }
                    }
                }
            }
        }
    }

    private var protocolChips: some View {
        let counts = Dictionary(grouping: model.ports, by: \.protocolLabel)
            .map { (label: $0.key, count: $0.value.count) }
        let sortedCounts = counts.sorted { first, second in
            if first.count != second.count {
                return first.count > second.count
            }
            return first.label < second.label
        }

        return FlowLayout(spacing: 8) {
            ForEach(sortedCounts, id: \.label) { item in
                Text("\(item.label) · \(item.count)")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Palette.cyan.opacity(0.14)))
                    .foregroundStyle(.white)
            }
        }
    }

    private func portRow(_ port: SystemPortEndpoint) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(port.localPort)")
                .font(.system(.body, design: .monospaced).weight(.bold))
                .frame(minWidth: 58, alignment: .leading)
            Text(port.processName)
                .font(.footnote)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(port.protocolLabel)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Palette.cyan)
                .lineLimit(1)
            Text("PID \(port.processID)")
                .font(.caption2)
                .foregroundStyle(Palette.muted)
        }
        .padding(.vertical, 4)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Palette.hairline)
                .frame(height: 1)
        }
    }

    private var networkCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                sectionHeader("Rede", symbol: "antenna.radiowaves.left.and.right", tone: .cyan)
                if let totals = model.networkTotals {
                    HStack(spacing: 16) {
                        metric("Entrada", value: rate(totals.bytesInPerSecond))
                        metric("Saída", value: rate(totals.bytesOutPerSecond))
                        metric("Pacotes", value: "\(Int(totals.packetsInPerSecond))/\(Int(totals.packetsOutPerSecond)) /s")
                    }
                }
                if let network = model.network {
                    let ranked = network.interfaces
                        .filter { !$0.isLoopback }
                        .sorted { $0.bytesIn + $0.bytesOut > $1.bytesIn + $1.bytesOut }
                    ForEach(ranked, id: \.name) { interface in
                        interfaceRow(interface)
                    }
                } else {
                    Text("Amostrando interfaces no próximo poll…")
                        .font(.footnote)
                        .foregroundStyle(Palette.muted)
                }
            }
        }
    }

    private func interfaceRow(_ interface: NetworkInterfaceCounters) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(interface.name)
                    .font(.system(.body, design: .monospaced).weight(.bold))
                    .frame(minWidth: 64, alignment: .leading)
                if let throughput = model.throughputs.first(where: { $0.name == interface.name }) {
                    Text("↓ \(rate(throughput.bytesInPerSecond)) · ↑ \(rate(throughput.bytesOutPerSecond))")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white)
                }
                Spacer(minLength: 8)
                Text(interface.isUp ? "UP" : "down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(interface.isUp ? Palette.green : Palette.muted)
            }
            if !interface.addresses.isEmpty {
                Text(interface.addresses.joined(separator: " · "))
                    .font(.caption2)
                    .foregroundStyle(Palette.muted)
                    .lineLimit(1)
            }
            HStack(spacing: 12) {
                Text("\(byteCount(interface.bytesIn)) recebidos · \(byteCount(interface.bytesOut)) enviados")
                    .font(.caption2)
                    .foregroundStyle(Palette.muted)
                if interface.errorsIn > 0 || interface.errorsOut > 0 || interface.dropsIn > 0 {
                    Text("err \(interface.errorsIn)/\(interface.errorsOut) · drops \(interface.dropsIn)")
                        .font(.caption2)
                        .foregroundStyle(Palette.coral)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var ndiCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader("NDI", symbol: "dot.radiowaves.left.and.right", tone: .violet)
                if let ndi = model.ndi {
                    if ndi.isAvailable {
                        HStack(spacing: 10) {
                            if let version = ndi.version {
                                Text("NDI \(version)")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.white)
                            }
                            if let path = ndi.libraryPath {
                                Text(path)
                                    .font(.caption2)
                                    .foregroundStyle(Palette.muted)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                        if ndi.sources.isEmpty {
                            Text("Nenhuma fonte descoberta na rede")
                                .font(.caption)
                                .foregroundStyle(Palette.muted)
                        } else {
                            ForEach(ndi.sources, id: \.name) { source in
                                HStack(alignment: .firstTextBaseline) {
                                    Text(source.name)
                                        .font(.footnote.weight(.semibold))
                                        .foregroundStyle(.white)
                                    Spacer(minLength: 8)
                                    Text(source.address)
                                        .font(.caption2)
                                        .foregroundStyle(Palette.muted)
                                }
                            }
                        }
                    } else {
                        Text("Runtime NDI não encontrado neste host")
                            .font(.caption)
                            .foregroundStyle(Palette.muted)
                    }
                } else {
                    Text("Sondando NDI…")
                        .font(.footnote)
                        .foregroundStyle(Palette.muted)
                }
            }
        }
    }

    private func rate(_ bytesPerSecond: Double) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytesPerSecond), countStyle: .memory) + "/s"
    }

    private func errorCard(_ message: String) -> some View {
        GlassCard {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Palette.coral)
                Text(message)
                    .font(.footnote)
            }
        }
    }

    private func sectionHeader(_ title: String, symbol: String, tone: Tone) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(tone.tint)
            Text(title)
                .font(.headline)
        }
    }

    private func metric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(Palette.muted)
            Text(value)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white)
        }
    }

    private func meter(value: Double, tone: Tone) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.10))
                Capsule()
                    .fill(tone.tint)
                    .frame(width: max(2, geometry.size.width * min(1, max(0, value))))
            }
        }
        .frame(height: 6)
    }

    private func byteCount(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .memory)
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 720
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
