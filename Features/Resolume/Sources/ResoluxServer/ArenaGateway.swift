import Foundation
import Pulse
import Resolume

/// Gateway read-only do REST do Arena para o proxy `/api/v1/arena/**` e para
/// o poll do Monitor. A porta é observada (nunca presumida): `8080` de
/// fábrica primeiro, `8008` medido nesta máquina depois — e re-observa quando
/// o Arena some. Nenhuma escrita, nenhuma configuração do Arena.
public actor ArenaGateway {
    public enum Falha: Error, Equatable {
        case indisponivel
    }

    public struct Resposta: Sendable, Equatable {
        public var status: Int
        public var contentType: String?
        public var corpo: Data
    }

    private let observador: ArenaRESTPortObserver
    private var porta: Int?
    private let timeout: TimeInterval
    private let proxy: URLSessionProxy = PulseAudit.shared().makeProxy()

    public init(
        observador: ArenaRESTPortObserver = ArenaRESTPortObserver(),
        timeout: TimeInterval = 5) {
        self.observador = observador
        self.timeout = timeout
    }

    /// `GET`/`HEAD` direto no REST do Arena. Status e corpo (JSON ou binário,
    /// ex.: thumbnails `image/*`) vêm como o Arena respondeu. Transporte caiu
    /// → porta esquecida + `.indisponivel` (o handler devolve 502 e o próximo
    /// pedido re-observa).
    public func requisitar(metodo: String, caminho: String) async throws -> Resposta {
        var portaAtual = porta
        if portaAtual == nil {
            portaAtual = try await observador.observe()
            porta = portaAtual
        }
        guard let portaDefinitiva = portaAtual else { throw Falha.indisponivel }
        guard let url = URL(string: "http://127.0.0.1:\(portaDefinitiva)/api/v1\(caminho)") else {
            throw Falha.indisponivel
        }
        var pedido = URLRequest(url: url)
        pedido.httpMethod = metodo
        pedido.timeoutInterval = timeout
        do {
            let (corpo, resposta) = try await proxy.data(for: pedido)
            let http = resposta as? HTTPURLResponse
            return Resposta(
                status: http?.statusCode ?? 500,
                contentType: http?.value(forHTTPHeaderField: "Content-Type"),
                corpo: corpo)
        } catch {
            porta = nil
            throw Falha.indisponivel
        }
    }

    /// Corpo bruto de `GET /composition` — o payload do Monitor.
    public func composition() async throws -> Data {
        try await requisitar(metodo: "GET", caminho: "/composition").corpo
    }
}
