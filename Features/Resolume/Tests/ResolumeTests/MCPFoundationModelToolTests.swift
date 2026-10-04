import Foundation
import FoundationModels
import Testing
import Resolume
@testable import ResolumeUI

private struct RawToolsList: Decodable {
    struct Result: Decodable {
        struct Tool: Decodable {
            let name: String
            let description: String?
            let inputSchema: MCPValue?
        }
        let tools: [Tool]
    }
    let result: Result
}

@available(macOS 26.0, *)
@Test("schemas MCP viram schemas Foundation Models")
func mcpSchemasBecomeFoundationModelSchemas() throws {
    guard let url = Bundle.module.url(forResource: "tools-schema", withExtension: "json") else {
        Issue.record("fixture tools-schema.json ausente no bundle de testes")
        return
    }
    let fixture = try JSONDecoder().decode(RawToolsList.self, from: Data(contentsOf: url))
    let infos = fixture.result.tools.map {
        MCPToolInfo(
            name: $0.name,
            description: $0.description,
            inputSchema: $0.inputSchema ?? .object(["type": .string("object")]))
    }
    let filtered = infos.filter { LocalChatBackend.appleToolSubset.contains($0.name) }
    let tools = MCPFoundationModelToolFactory.makeTools(
        from: filtered,
        client: MCPClient(transport: FakeMCPServer()),
        policy: .readOnly)

    #expect(filtered.count == 10)
    #expect(tools.count == filtered.count)
}

@available(macOS 26.0, *)
@Test("subset medido deixa o Apple FM dentro da janela")
func appleSubsetStaysWithinTheWindow() throws {
    guard let url = Bundle.module.url(forResource: "tools-schema", withExtension: "json") else {
        Issue.record("fixture tools-schema.json ausente no bundle de testes")
        return
    }
    let fixture = try JSONDecoder().decode(RawToolsList.self, from: Data(contentsOf: url))
    let infos = fixture.result.tools.compactMap { tool -> MCPToolInfo? in
        guard LocalChatBackend.appleToolSubset.contains(tool.name) else { return nil }
        return MCPToolInfo(
            name: tool.name,
            description: tool.description,
            inputSchema: tool.inputSchema ?? .object(["type": .string("object")]))
    }
    let tools = MCPFoundationModelToolFactory.makeTools(
        from: infos,
        client: MCPClient(transport: FakeMCPServer()),
        policy: .readOnly)

    #expect(infos.count == 10)
    #expect(tools.count == 10)
}

@available(macOS 26.0, *)
@Test("ToolPolicy bloqueia antes do MCPClient")
func toolPolicyBlocksBeforeMCPClientCall() async throws {
    let client = MCPClient(transport: FakeMCPServer())
    let info = MCPToolInfo(
        name: "transport",
        description: "transport",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "action": .object([
                    "type": .string("string"),
                    "enum": .array([.string("get"), .string("set")]),
                ]),
            ]),
        ]))
    let tool = try MCPFoundationModelTool(info: info, client: client, policy: .readOnly)
    let arguments = try GeneratedContent(json: #"{"action":"set"}"#)

    let output = try await tool.call(arguments: arguments)
    #expect(output.contains("Modo somente leitura"))
    #expect(output.contains("transport.set"))
}

@available(macOS 26.0, *)
@Test("escrita permitida pelo FM registra no diário com valor anterior")
func fmWriteJournalsWithPreviousValue() async throws {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("resolux-fm-journal-" + UUID().uuidString)
    let journal = WriteJournal(directory: root, sessionID: "teste")
    defer { try? FileManager.default.removeItem(at: root) }

    let server = FakeMCPServer()
    let client = MCPClient(transport: server)
    try await client.connect()
    let info = MCPToolInfo(
        name: "parameter", description: "parameter",
        inputSchema: .object(["type": .string("object")]))
    let tool = try MCPFoundationModelTool(
        info: info, client: client, policy: .readWrite, journal: journal)
    let arguments = try GeneratedContent(
        json: #"{"action":"set","path":"/layers/1/volume","value":0.5}"#)

    let output = try await tool.call(arguments: arguments)
    #expect(output == "ok de parameter")

    let linhas = WriteJournal.entries(at: journal.url)
    #expect(linhas.count == 1)
    let registro = try #require(linhas.first)
    #expect(registro.tool == "parameter")
    #expect(registro.action == "set")
    #expect(registro.isError == false)
    #expect(registro.previous != nil)

    // Ordem provada: leitura espelhada antes da escrita, e nada além.
    let enviadas = await server.receivedLines
        .map { $0.replacingOccurrences(of: "\\/", with: "/") }
        .filter { $0.contains("tools/call") }
    #expect(enviadas.count == 2)
    #expect(try #require(enviadas.first).contains("get"))
    #expect(try #require(enviadas.last).contains(#""action":"set""#))
}

@available(macOS 26.0, *)
@Test("leitura via FM não entra no diário")
func fmReadDoesNotJournal() async throws {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("resolux-fm-journal-" + UUID().uuidString)
    let journal = WriteJournal(directory: root, sessionID: "teste")
    defer { try? FileManager.default.removeItem(at: root) }

    let server = FakeMCPServer()
    let client = MCPClient(transport: server)
    try await client.connect()
    let info = MCPToolInfo(
        name: "layer", description: "layer",
        inputSchema: .object(["type": .string("object")]))
    let tool = try MCPFoundationModelTool(
        info: info, client: client, policy: .readWrite, journal: journal)
    let arguments = try GeneratedContent(json: #"{"action":"get","index":0}"#)

    _ = try await tool.call(arguments: arguments)

    #expect(WriteJournal.entries(at: journal.url).isEmpty)
    // Mesma pegadinha do journal: a Foundation escapa a barra ("tools\/call").
    let enviadas = await server.receivedLines
        .map { $0.replacingOccurrences(of: "\\/", with: "/") }
        .filter { $0.contains("tools/call") }
    #expect(enviadas.count == 1)
}
