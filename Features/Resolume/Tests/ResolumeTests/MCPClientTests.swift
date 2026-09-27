import Foundation
import Testing
@testable import Resolume

/// Fake que responde como o servidor MCP da Resolume nas três chamadas essenciais.
actor FakeMCPServer: MCPTransport {
    private(set) var receivedLines: [String] = []

    func start() async throws {}
    func stop() async {}

    func notify(_ line: String) async throws {
        receivedLines.append(line)
    }

    func send(requestLine: String) async throws -> String {
        receivedLines.append(requestLine)
        struct RawRequest: Decodable {
            let id: Int
            let method: String
            let params: [String: MCPValue]?
        }
        let request = try JSONDecoder().decode(RawRequest.self, from: Data(requestLine.utf8))
        switch request.method {
        case "initialize":
            return """
            {"jsonrpc":"2.0","id":\(request.id),"result":{"protocolVersion":"2025-03-26","serverInfo":{"name":"fake-arena","version":"7.26.0"},"capabilities":{"tools":{}}}}
            """
        case "tools/list":
            return """
            {"jsonrpc":"2.0","id":\(request.id),"result":{"tools":[{"name":"status","description":"Arena status"},{"name":"layer","description":"Camadas"}]}}
            """
        case "tools/call":
            let tool = request.params?["name"]?.stringValue ?? "?"
            return """
            {"jsonrpc":"2.0","id":\(request.id),"result":{"content":[{"type":"text","text":"ok de \(tool)"}],"isError":false}}
            """
        default:
            return """
            {"jsonrpc":"2.0","id":\(request.id),"error":{"code":-32601,"message":"method not found"}}
            """
        }
    }
}

@Test("handshake completa e expõe ferramentas")
func connectAndListTools() async throws {
    let client = MCPClient(transport: FakeMCPServer())
    try await client.connect()
    let tools = try await client.listTools()
    #expect(tools.map(\.name) == ["status", "layer"])
}

@Test("tools/call devolve texto do servidor")
func callToolReturnsText() async throws {
    let client = MCPClient(transport: FakeMCPServer())
    try await client.connect()
    let result = try await client.callTool("status")
    #expect(result.text == "ok de status")
    #expect(!result.isError)
}

@Test("erro JSON-RPC vira MCPError.serverError")
func methodNotFoundThrows() async throws {
    let client = MCPClient(transport: FakeMCPServer())
    try await client.connect()
    await #expect(throws: MCPError.serverError(code: -32601, message: "method not found")) {
        _ = try await client.request(method: "metodo-inexistente")
    }
}
