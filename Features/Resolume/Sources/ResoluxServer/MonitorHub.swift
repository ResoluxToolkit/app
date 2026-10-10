import Foundation

/// Hub do Monitor: um único poll de 1 s no REST do Arena compartilhado por
/// todos os assinantes WS. Só empurra quando o payload muda; em falha, avisa
/// na transição (sem spam por tick) e continua tentando reconectar. Quando o
/// último assinante sai, o poll para.
public actor MonitorHub {
    public enum Evento: Sendable, Equatable {
        case update(Data)
        case erro(codigo: String, mensagem: String)
    }

    public typealias Entregador = @Sendable (Evento) async -> Void
    public typealias Provedor = @Sendable () async throws -> Data

    private let provedor: Provedor
    private let intervalo: TimeInterval
    private var entregadores: [UUID: Entregador] = [:]
    private var tarefa: Task<Void, Never>?
    private var ultimoCorpo: Data?
    private var emFalha = false

    public init(provedor: @escaping Provedor, intervalo: TimeInterval = 1.0) {
        self.provedor = provedor
        self.intervalo = intervalo
    }

    public func assinar(_ entregador: @escaping Entregador) -> UUID {
        let id = UUID()
        entregadores[id] = entregador
        if tarefa == nil { tarefa = Task { await vigiar() } }
        return id
    }

    public func cancelar(_ id: UUID) {
        entregadores.removeValue(forKey: id)
        if entregadores.isEmpty {
            tarefa?.cancel()
            tarefa = nil
            ultimoCorpo = nil
            emFalha = false
        }
    }

    private func vigiar() async {
        while !Task.isCancelled {
            await apurar()
            if entregadores.isEmpty { return }
            try? await Task.sleep(nanoseconds: UInt64(intervalo * 1_000_000_000))
        }
    }

    private func apurar() async {
        do {
            let corpo = try await provedor()
            if corpo != ultimoCorpo {
                ultimoCorpo = corpo
                await entregar(.update(corpo))
            }
            emFalha = false
        } catch {
            if !emFalha {
                emFalha = true
                await entregar(.erro(codigo: "arena_unavailable", mensagem: "Arena REST unavailable"))
            }
        }
    }

    private func entregar(_ evento: Evento) async {
        for (_, entregador) in entregadores {
            await entregador(evento)
        }
    }
}
