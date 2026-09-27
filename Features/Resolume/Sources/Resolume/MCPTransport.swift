import Foundation

/// Pipe de mensagens JSON-RPC newline-delimited com um servidor MCP stdio.
public protocol MCPTransport: Actor {
    /// Inicia o parceiro (processo ou fake). Deve ser chamado antes de enviar.
    func start() async throws

    /// Escreve uma requisição (uma linha JSON) e espera a linha de resposta.
    func send(requestLine: String) async throws -> String

    /// Escreve uma notificação (sem resposta esperada).
    func notify(_ line: String) async throws

    func stop() async
}
