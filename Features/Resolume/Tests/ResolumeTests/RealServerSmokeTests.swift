import Foundation
import Testing
@testable import Resolume

/// Fumaça contra o binário real: só roda com o Arena aberto (socket REST vivo),
/// porque sem ele o servidor MCP trava em tools/list.
@Test("sessão real com o binário MCP do Arena",
      .enabled(if: ResolumeProduct.arena.isRunning()))
func realArenaHandshake() async throws {
    let transport = ProcessMCPTransport(
        executableURL: URL(fileURLWithPath: ResolumeProduct.arena.mcpExecutablePath),
        responseTimeout: 15)
    let client = MCPClient(transport: transport)
    try await client.connect()
    let tools = try await client.listTools()
    #expect(tools.contains { $0.name == "composition" })
    #expect(tools.contains { $0.name == "transport" })
    await client.disconnect()
}
