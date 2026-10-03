import Foundation

/// Motor do fluxo "operador fala, Arena executa": linguagem natural entra no
/// modelo, tool_calls saem traduzidas como comandos MCP no Resolume.
public actor ChatEngine {
    public struct Config: Sendable {
        public var endpoint: URL
        public var apiKey: String
        public var model: String
        /// Ferramentas que o motor pode oferecer ao modelo. `nil` = todas as que
        /// o servidor MCP declarou. Existe porque o `fm serve` da Apple tem
        /// janela curta: medido com `stream:false` e o system prompt real, ele
        /// aceita as 10 ferramentas mais baratas (3.986 tokens de prompt) e
        /// devolve HTTP 500 na decima primeira -- inclusive uma de 453 tokens.
        public var toolAllowlist: Set<String>?

        public init(endpoint: URL, apiKey: String, model: String,
                    toolAllowlist: Set<String>? = nil) {
            self.endpoint = endpoint
            self.apiKey = apiKey
            self.model = model
            self.toolAllowlist = toolAllowlist
        }

        /// Backend OpenAI-compatível padrão (OpenAI; troque base URL p/ Ollama, OpenRouter etc.).
        public init(
            baseURL: URL = URL(string: "https://api.openai.com/v1")!,
            apiKey: String,
            model: String = "gpt-5.6",
            toolAllowlist: Set<String>? = nil
        ) {
            self.endpoint = Self.chatCompletionsEndpoint(baseURL)
            self.apiKey = apiKey
            self.model = model
            self.toolAllowlist = toolAllowlist
        }

        /// `URL(string:relativeTo:)` descarta o último segmento do path quando a
        /// base não termina em "/": "https://api.openai.com/v1" virava
        /// "https://api.openai.com/chat/completions" (404). Normalizamos a barra.
        static func chatCompletionsEndpoint(_ baseURL: URL) -> URL {
            var string = baseURL.absoluteString
            if !string.hasSuffix("/") { string += "/" }
            return URL(string: "chat/completions", relativeTo: URL(string: string)!)!
        }
    }

    private let config: Config
    private let transport: any ChatBackendTransport
    private let mcp: MCPClient
    private let maxToolRounds: Int
    private let policy: ToolPolicy
    /// Diário do que escrevemos no set. `nil` é o default e mantém o motor igual
    /// ao que era: o Cmd-Z do Arena não alcança automação nenhuma, então o rastro
    /// tem que existir, mas ligar isso é escolha de quem monta o turno.
    private let journal: WriteJournal?
    private var history: [ChatMessage] = []
    private var instructionsAdopted = false
    /// Nomes que o **servidor MCP** declarou em `tools/list`. É a única lista que
    /// autoriza um resgate de texto: nome fora dela nunca roda.
    private var knownToolNames: Set<String> = []

    public init(
        config: Config,
        transport: any ChatBackendTransport = URLSessionChatTransport(),
        mcp: MCPClient,
        maxToolRounds: Int = 8,
        policy: ToolPolicy = .readOnly,
        journal: WriteJournal? = nil
    ) {
        self.config = config
        self.transport = transport
        self.mcp = mcp
        self.maxToolRounds = maxToolRounds
        self.policy = policy
        self.journal = journal
        history = [ChatMessage.system(Self.systemPrompt)]
    }

    public var transcript: [ChatMessage] { history }

    /// Processa uma mensagem do operador e devolve a resposta final do modelo,
    /// executando quantas rodadas de ferramentas forem necessárias.
    public func send(_ userText: String) async throws -> String {
        await adoptServerInstructions()
        history.append(.user(userText))
        for _ in 0..<maxToolRounds {
            let reply = try await complete()
            switch reply.message.tool_calls {
            case .some(let calls) where !calls.isEmpty:
                history.append(reply.message)
                for call in calls {
                    let outcome = await execute(call)
                    history.append(.tool(toolCallId: call.id, content: outcome))
                }
            default:
                let text = reply.message.content ?? ""
                // Backend local que não sabe usar o campo `tool_calls` escreve a
                // chamada como texto. Sem este resgate o turno acaba aqui e nada
                // roda no Arena -- o modelo responde "acho que tem 3 camadas".
                if let rescued = ToolCallTextRescue.rescue(from: text, knownTools: knownToolNames) {
                    history.append(.assistant(
                        rescued.remainingText.isEmpty ? nil : rescued.remainingText,
                        toolCalls: rescued.calls))
                    for call in rescued.calls {
                        let outcome = await execute(call)
                        history.append(.tool(toolCallId: call.id, content: outcome))
                    }
                    continue
                }
                history.append(.assistant(text))
                return text
            }
        }
        let exhausted = "Limite de \(maxToolRounds) rodadas de ferramentas atingido."
        history.append(.assistant(exhausted))
        return exhausted
    }

    public func reset() {
        history = [ChatMessage.system(Self.systemPrompt)]
        instructionsAdopted = false
    }

    /// Coloca as instruções do servidor no system prompt do modelo. A Resolume
    /// escreve ali regras duras (confirmar antes de salvar, não narrar tool
    /// calls, economizar tokens) — ignorá-las deixa o assistente meio surdo.
    /// A confirmação protocolar do gate é do `MCPClient`, não daqui.
    private func adoptServerInstructions() async {
        guard !instructionsAdopted else { return }
        guard let instructions = await mcp.serverInstructions, !instructions.isEmpty else { return }
        instructionsAdopted = true
        history[0] = .system(Self.systemPrompt + "\n\n" + Self.instructionsMarker + "\n" + instructions)
    }

    private func complete() async throws -> ChatCompletionResponse.Choice {
        let listed = try await mcp.listTools()
        // Janela curta nao e motivo para oferecer ferramenta que o backend vai
        // derrubar. O filtro vale tambem para o resgate de texto: so roda nome
        // que foi realmente oferecido nesta conversa.
        let offered = config.toolAllowlist.map { allowed in
            listed.filter { allowed.contains($0.name) }
        } ?? listed
        knownToolNames = Set(offered.map(\.name))
        let tools = offered.map { tool in
            ChatToolSpec(function: .init(
                name: tool.name,
                description: tool.description ?? tool.name,
                parameters: ToolSchemaNormalizer.normalize(tool.inputSchema)))
        }
        let request = ChatCompletionRequest(
            model: config.model, messages: history, tools: tools.isEmpty ? nil : tools,
            tool_choice: tools.isEmpty ? nil : "auto", stream: false)
        let body = try JSONEncoder().encode(request)
        let (data, _) = try await transport.complete(
            endpoint: config.endpoint, apiKey: config.apiKey, body: body)
        let response = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        guard let choice = response.choices.first else { throw ChatError.noChoices }
        return choice
    }

    private func execute(_ call: ChatMessage.ToolCall) async -> String {
        let arguments = decodeArguments(call.function.arguments)
        let decision = policy.decide(tool: call.function.name, arguments: arguments)
        guard case .allow = decision else {
            return ToolPolicy.refusal(
                tool: call.function.name,
                action: arguments["action"]?.stringValue,
                alwaysBlocked: decision.isNever)
        }
        let tool = call.function.name
        // Escrita permitida: antes de mudar o valor, guardamos o valor antigo onde
        // existe leitura espelhada (`parameter`). É a nossa versão do undo que o
        // Arena não nos dá pra automação.
        let previous = await previousValue(tool: tool, arguments: arguments)
        do {
            let result = try await mcp.callTool(call.function.name, arguments: arguments)
            await record(tool: tool, arguments: arguments, result: result.text,
                         isError: result.isError, previous: previous)
            return result.text.isEmpty ? "{\"ok\":true}" : result.text
        } catch let error as MCPError {
            await record(tool: tool, arguments: arguments, result: error.localizedDescription,
                         isError: true, previous: previous)
            return "{\"error\":\"\(error.localizedDescription)\"}"
        } catch {
            await record(tool: tool, arguments: arguments, result: error.localizedDescription,
                         isError: true, previous: previous)
            return "{\"error\":\"\(error.localizedDescription)\"}"
        }
    }

    /// Valor anterior só faz sentido em escrita de `parameter`; leitura comum e
    /// escrita sem paridade devolvem `nil` sem gastar chamada no Arena.
    private func previousValue(
        tool: String, arguments: [String: MCPValue]) async -> String? {
        guard journal != nil, ToolPolicy.isWrite(tool: tool, arguments: arguments) else { return nil }
        guard let readArguments = WriteJournal.mirroredRead(tool: tool, arguments: arguments) else { return nil }
        return try? await mcp.callTool("parameter", arguments: readArguments).text
    }

    private func record(
        tool: String, arguments: [String: MCPValue], result: String,
        isError: Bool, previous: String?) async {
        // Recusa de política nem chega aqui; erro de disco não pode matar o turno.
        guard let journal, ToolPolicy.isWrite(tool: tool, arguments: arguments) else { return }
        try? await journal.record(
            tool: tool, arguments: arguments, result: result,
            isError: isError, previous: previous.map { WriteJournal.cap($0) })
    }

    private func decodeArguments(_ raw: String) -> [String: MCPValue] {
        guard let data = raw.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String: MCPValue].self, from: data)
        else { return [:] }
        return decoded
    }

    static let systemPrompt = """
    Você é o operador do Resolux controlando o Resolume \(ProcessInfo.processInfo.hostName) via \
    ferramentas MCP. Regras: converta o pedido do operador em chamadas MCP mínimas e encadeadas; \
    nunca invente IDs — descubra-os com a própria ferramenta; confirme ações destrutivas \
    (clear/remove/delete) perguntando antes; responda ao operador em português, curto e sem \
    narrar cada tool call. Sobre o relógio: cada clipe tem o próprio modo de transporte \
    (`clip.transporttype`: Timeline, BPM Sync, SMPTE 1, SMPTE 2, Denon DJ, Pioneer DJ), então \
    o BPM global do `transport` não é necessariamente o andamento do show. Antes de informar BPM, \
    taxa ou posição, diga de qual fonte vem o número; se a fonte não estiver na resposta da \
    ferramenta, diga isso em vez de apresentar número solto. Restrição de uso (regra do operador, \
    não do schema): sincronismo SMPTE só funciona em clipe cuja faixa seja só de vídeo, sem faixa \
    de áudio. Nunca sugira SMPTE para clipe com áudio.
    """

    /// Marcador que separa as regras nossas das instruções vindas do servidor.
    static let instructionsMarker = "## Instruções do servidor MCP"
}
