import Foundation

/// Hub da conversa: cada cliente WS assinante recebe a lista completa de
/// turnos quando o disco muda (turno novo ou limpeza). Sem poll — o push
/// nasce do `PersistenciaDisco`, que é quem grava.
public actor ConversaHub {
    public typealias Entregador = @Sendable (Data) async -> Void

    private var entregadores: [UUID: Entregador] = [:]

    public init() {}

    public func assinar(_ entregador: @escaping Entregador) -> UUID {
        let id = UUID()
        entregadores[id] = entregador
        return id
    }

    public func cancelar(_ id: UUID) {
        entregadores.removeValue(forKey: id)
    }

    public func publicar(_ corpo: Data) async {
        for (_, entregador) in entregadores {
            await entregador(corpo)
        }
    }
}
