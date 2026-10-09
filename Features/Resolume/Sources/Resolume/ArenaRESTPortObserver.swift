import Foundation

/// Observa em que porta o REST do Arena está de pé. A porta é observada, não
/// presumida: `8080` é o default de fábrica, mas pode ter sido movida — nesta
/// máquina `8008` respondeu. Sonda os candidatos em ordem com leitura pura
/// (um `GET /composition` por candidato) e nunca configura o Arena.
public struct ArenaRESTPortObserver: Sendable {
    public struct Failure: Error, Equatable, CustomStringConvertible {
        public let triedPorts: [Int]

        public var description: String {
            "REST do Arena não respondeu em nenhuma porta tentada: \(triedPorts)"
        }
    }

    public var candidates: [Int]
    public var probe: @Sendable (Int) async throws -> Void

    public init(
        candidates: [Int] = [8080, 8008],
        probe: @escaping @Sendable (Int) async throws -> Void = {
            try await Self.compositionProbe(port: $0)
        }) {
        self.candidates = candidates
        self.probe = probe
    }

    /// Sonda real: `GET /composition` com timeout curto. Leitura pura.
    public static func compositionProbe(port: Int, timeout: TimeInterval = 2) async throws {
        let rest = ArenaREST(endpoint: .localhost(port: port, timeout: timeout))
        _ = try await rest.composition()
    }

    /// Primeira porta que responde; se todas falharem, erro com as tentadas.
    public func observe() async throws -> Int {
        var tried: [Int] = []
        for port in candidates {
            tried.append(port)
            do {
                try await probe(port)
                return port
            } catch {}
        }
        throw Failure(triedPorts: tried)
    }
}
