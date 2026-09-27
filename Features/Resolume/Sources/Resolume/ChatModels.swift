import Foundation

/// Tipos do wire format OpenAI /chat/completions (subset que usamos).
public struct ChatMessage: Codable, Sendable, Equatable {
    public struct ToolCall: Codable, Sendable, Equatable {
        public struct Function: Codable, Sendable, Equatable {
            public var name: String
            public var arguments: String

            public init(name: String, arguments: String) {
                self.name = name
                self.arguments = arguments
            }
        }

        public var id: String
        public var type: String = "function"
        public var function: Function

        public init(id: String, function: Function) {
            self.id = id
            self.function = function
        }
    }

    public var role: String
    public var content: String?
    public var tool_calls: [ToolCall]?
    public var tool_call_id: String?

    enum CodingKeys: String, CodingKey {
        case role, content, tool_calls, tool_call_id
    }

    public static func system(_ text: String) -> ChatMessage { .init(role: "system", content: text) }
    public static func user(_ text: String) -> ChatMessage { .init(role: "user", content: text) }
    public static func assistant(_ text: String) -> ChatMessage { .init(role: "assistant", content: text) }
    public static func assistant(_ text: String?, toolCalls: [ToolCall]) -> ChatMessage {
        .init(role: "assistant", content: text, tool_calls: toolCalls)
    }
    public static func tool(toolCallId: String, content: String) -> ChatMessage {
        .init(role: "tool", content: content, tool_call_id: toolCallId)
    }
}

public struct ChatToolSpec: Encodable, Sendable {
    public struct Function: Encodable, Sendable {
        public var name: String
        public var description: String
        public var parameters: MCPValue
    }

    public var type: String = "function"
    public var function: Function
}

public struct ChatCompletionRequest: Encodable, Sendable {
    public var model: String
    public var messages: [ChatMessage]
    public var tools: [ChatToolSpec]?
    public var tool_choice: String?
    /// `false` pedido explicitamente: o `fm serve` da Apple **defaulta para SSE**
    /// (`Content-Type: text/event-stream`) e nosso parser só lê resposta fechada.
    /// Medido: com `stream:false` ele devolve JSON puro e HTTP 200.
    /// Optional para não mandar o campo para backends que não o entendem.
    public var stream: Bool?
}

public struct ChatCompletionResponse: Decodable, Sendable {
    public struct Choice: Decodable, Sendable {
        public var message: ChatMessage
        public var finish_reason: String?
    }

    public var choices: [Choice]
}

/// Transporte HTTP injetável para o backend de chat (fake nos testes).
public protocol ChatBackendTransport: Sendable {
    func complete(
        endpoint: URL, apiKey: String, body: Data) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionChatTransport: ChatBackendTransport {
    /// Visivel para testes (`@testable`): e assim que a regressao prova que o
    /// padrao nao voltou a ser `URLSession.shared` (teto de 60 s).
    let session: URLSession

    /// Turno local de verdade (modelo pequeno + 22 ferramentas MCP) medido em
    /// ~118 s. `URLSession.shared` corta em 60 s e a UI mostra "conectou e nao
    /// acontece nada" -- exatamente o erro -1001 que apareceu no teste ao vivo.
    /// Por isso a sessao padrao e nossa, com teto acima da latencia local.
    public static let defaultRequestTimeout: TimeInterval = 300

    public init(timeout: TimeInterval = Self.defaultRequestTimeout) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout * 2
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        self.session = URLSession(configuration: configuration)
    }

    /// Para testes injetarem transporte controlado.
    public init(session: URLSession) { self.session = session }

    public func complete(endpoint: URL, apiKey: String, body: Data) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = body
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ChatError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let detail = String(data: data.prefix(500), encoding: .utf8) ?? ""
            throw ChatError.httpStatus(code: httpResponse.statusCode, detail: detail)
        }
        // Backend que ignora nosso `stream:false` viria aqui como SSE. Melhor um
        // erro legível do que "The data couldn't be read because it isn't in the
        // correct format" no meio de uma conversa ao vivo.
        if httpResponse.value(forHTTPHeaderField: "Content-Type")?
            .lowercased().contains("text/event-stream") == true {
            throw ChatError.streamingUnsupported
        }
        return (data, httpResponse)
    }
}

public enum ChatError: Error, LocalizedError, Equatable {
    case invalidResponse
    case noChoices
    case httpStatus(code: Int, detail: String)
    case streamingUnsupported

    public var errorDescription: String? {
        switch self {
        case .invalidResponse: "Resposta inválida do backend de chat"
        case .noChoices: "Backend de chat não retornou escolhas"
        case .httpStatus(let code, let detail): "Backend de chat respondeu \(code): \(detail)"
        case .streamingUnsupported:
            "O backend de chat respondeu em streaming (SSE), que a gente ainda não "
            + "lê. Informe o provedor e tente de novo."
        }
    }
}
