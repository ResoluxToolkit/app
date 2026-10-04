import Foundation
import Testing
@testable import Resolume

/// O filtro de ferramentas por backend existe por uma medicao, nao por gosto:
/// com o system prompt real e `stream:false`, o `fm serve` da Apple aceita as
/// 10 ferramentas mais baratas do Arena (3.986 tokens de prompt, HTTP 200) e
/// devolve HTTP 500 na decima primeira -- inclusive uma barata (`layer`, que e
/// justamente a que responde "quantas camadas tem"). O gateway local leva as 22.
/// Estes testes prendem essa medicao para ninguem "simplificar" o filtro depois.

private func nomesOferecidos(noBody body: Data) -> [String] {
    struct Request: Decodable {
        struct Tool: Decodable {
            struct Fn: Decodable { let name: String }
            let function: Fn
        }
        let tools: [Tool]?
    }
    guard let decoded = try? JSONDecoder().decode(Request.self, from: body) else { return [] }
    return decoded.tools?.map(\.function.name) ?? []
}

@Test("allowlist limita as ferramentas oferecidas ao modelo")
func allowlistLimitsOfferedTools() async throws {
    let mcp = MCPClient(transport: FakeMCPServer())
    try await mcp.connect()
    // FakeMCPServer declara status + layer; so status esta na allowlist.
    let backend = ScriptedChatTransport(script: [
        ScriptedChatTransport.textResponse("Arena rodando.")])
    let engine = ChatEngine(
        config: .init(
            baseURL: URL(string: "http://127.0.0.1:1976/v1")!,
            apiKey: "local",
            model: "system",
            toolAllowlist: ["status"]),
        transport: backend,
        mcp: mcp)

    _ = try await engine.send("como esta?")
    let bodies = await backend.requestBodies
    #expect(bodies.count == 1)
    let nomes = nomesOferecidos(noBody: bodies[0])
    #expect(nomes == ["status"], "layer vazou para o modelo: \(nomes)")
}

@Test("sem allowlist oferece tudo o que o servidor MCP declarou")
func nilAllowlistOffersEverything() async throws {
    let mcp = MCPClient(transport: FakeMCPServer())
    try await mcp.connect()
    let backend = ScriptedChatTransport(script: [
        ScriptedChatTransport.textResponse("Arena rodando.")])
    let engine = ChatEngine(
        config: .init(baseURL: LocalChatBackend.localGatewayBaseURL,
                      apiKey: LocalChatBackend.localGatewayAPIKey,
                      model: LocalChatBackend.localGatewayModel),
        transport: backend,
        mcp: mcp)

    _ = try await engine.send("como esta?")

    let bodies = await backend.requestBodies
    let nomes = Set(nomesOferecidos(noBody: bodies[0]))
    #expect(nomes == ["status", "layer"], "gateway deveria receber tudo: \(nomes)")
}

@Test("nome filtrado nao pode ser resgatado como texto")
func filteredOutNameCannotBeRescued() async throws {
    let mcp = MCPClient(transport: FakeMCPServer())
    try await mcp.connect()
    // O fm escreve a chamada como texto (comportamento medido). Raw string:
    // \n e \" aqui sao o escape do JSON, nao do Swift -- padrao do repo.
    let backend = ScriptedChatTransport(script: [
        ScriptedChatTransport.textResponse(
            #"Vou olhar.\n```json\n{\"tool_calls\":[{\"name\":\"layer\",\"arguments\":{\"action\":\"list\"}}]}\n```"#),
        ScriptedChatTransport.textResponse("Sem acesso as camadas neste modo.")])
    let engine = ChatEngine(
        config: .init(baseURL: URL(string: "http://127.0.0.1:1976/v1")!,
                      apiKey: "local", model: "system",
                      toolAllowlist: ["status"]),
        transport: backend,
        mcp: mcp)

    _ = try await engine.send("quantas camadas?")

    let usouFerramenta = await engine.transcript.contains { $0.role == "tool" }
    #expect(!usouFerramenta, "camada filtrada foi executada pelo resgate")
}

@Test("subset medido do Apple tem exatamente as 10 que cabem na janela")
func appleSubsetMatchesTheMeasurement() throws {
    let subset = LocalChatBackend.appleToolSubset
    #expect(subset.count == 10, "subset mudou de tamanho; re-medir a escada")
    // As que estouraram na medicao nao podem voltar por descuido.
    for cara in ["clip", "effect", "layer", "parameter", "monitor", "batch"] {
        #expect(!subset.contains(cara), "\(cara) estoura a janela do fm")
    }
    let gateway = LocalChatBackend(kind: .localGateway, baseURL: URL(string: "http://x/v1")!,
                                   model: "gemini-3.8-flash-high")
    #expect(gateway.toolAllowlist == nil, "gateway local nao deve filtrar nada")
    let apple = LocalChatBackend(kind: .appleFoundationModels,
                                 baseURL: URL(string: "http://x/v1")!, model: "system")
    #expect(apple.toolAllowlist == subset)
}
