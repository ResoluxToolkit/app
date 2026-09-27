import Foundation

/// Motor do fluxo "operador fala, Arena executa": linguagem natural entra no
/// modelo, tool_calls saem traduzidas como comandos MCP no Resolume.
public actor ChatEngine {
    public struct Config: Sendable {
        public var endpoint: URL
        public var apiKey: String
        public var model: String

        public init(endpoint: URL, apiKey: String, model: String) {
            self.endpoint = endpoint
            self.apiKey = apiKey
            self.model = model
        }

        /// Backend OpenAI-compatível padrão (OpenAI; troque base URL p/ Ollama, OpenRouter etc.).
        public init(
            baseURL: URL = URL(string: "https://api.openai.com/v1")!,
            apiKey: String,
            model: String = "gpt-5.6"
        ) {
            self.endpoint = URL(string: "chat/completions", relativeTo: baseURL)!
            self.apiKey = apiKey
            self.model = model
        }
    }

    private let config: Config
    private let transport: any ChatBackendTransport
    private let mcp: MCPClient
    private let maxToolRounds: Int
    private var history: [ChatMessage] = []

    public init(
        config: Config,
        transport: any ChatBackendTransport = URLSessionChatTransport(),
        mcp: MCPClient,
        maxToolRounds: Int = 8
    ) {
        self.config = config
        self.transport = transport
        self.mcp = mcp
        self.maxToolRounds = maxToolRounds
        history = [ChatMessage.system(Self.systemPrompt)]
    }

    public var transcript: [ChatMessage] { history }

    /// Processa uma mensagem do operador e devolve a resposta final do modelo,
    /// executando quantas rodadas de ferramentas forem necessárias.
    public func send(_ userText: String) async throws -> String {
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
    }

    private func complete() async throws -> ChatCompletionResponse.Choice {
        let tools = try await mcp.listTools().map { tool in
            ChatToolSpec(function: .init(
                name: tool.name,
                description: tool.description ?? tool.name,
                parameters: tool.inputSchema))
        }
        let request = ChatCompletionRequest(
            model: config.model, messages: history, tools: tools.isEmpty ? nil : tools,
            tool_choice: tools.isEmpty ? nil : "auto")
        let body = try JSONEncoder().encode(request)
        let (data, _) = try await transport.complete(
            endpoint: config.endpoint, apiKey: config.apiKey, body: body)
        let response = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        guard let choice = response.choices.first else { throw ChatError.noChoices }
        return choice
    }

    private func execute(_ call: ChatMessage.ToolCall) async -> String {
        let arguments = decodeArguments(call.function.arguments)
        do {
            let result = try await mcp.callTool(call.function.name, arguments: arguments)
            return result.text.isEmpty ? "{\"ok\":true}" : result.text
        } catch let error as MCPError {
            return "{\"error\":\"\(error.localizedDescription)\"}"
        } catch {
            return "{\"error\":\"\(error.localizedDescription)\"}"
        }
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
    narrar cada tool call.
    """
}
