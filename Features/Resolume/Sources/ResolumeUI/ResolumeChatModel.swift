import Foundation
import Observation
import Resolume

@Observable
@MainActor
public final class ResolumeChatModel {
    public struct Settings {
        public var apiKey: String
        public var baseURL: URL
        public var model: String

        public init(
            apiKey: String = "",
            baseURL: URL = URL(string: "https://api.openai.com/v1")!,
            model: String = "gpt-5.6"
        ) {
            self.apiKey = apiKey
            self.baseURL = baseURL
            self.model = model
        }
    }

    public enum Phase: Equatable {
        case idle
        case connecting
        case ready(toolCount: Int)
        case failed(String)
    }

    public struct Line: Identifiable, Equatable {
        public let id = UUID()
        public let role: String
        public let text: String
    }

    public private(set) var phase: Phase = .idle
    public private(set) var lines: [Line] = []
    public var draft: String = ""
    public var isBusy = false

    private let product: ResolumeProduct
    private var mcpTask: Task<Void, Never>?

    public init(product: ResolumeProduct = .arena) {
        self.product = product
    }

    public var installationReady: Bool { product.isRunning() }
    public var executablePresent: Bool {
        FileManager.default.isExecutableFile(atPath: product.mcpExecutablePath)
    }

    public func connect(settings: Settings) {
        guard case .idle = phase else { return }
        guard executablePresent, installationReady else {
            phase = .failed("\(product.appName) precisa estar aberto (socket REST ausente)")
            return
        }
        guard !settings.apiKey.isEmpty else {
            phase = .failed("Informe a API key do backend de chat")
            return
        }
        phase = .connecting
        let transport = ProcessMCPTransport(
            executableURL: URL(fileURLWithPath: product.mcpExecutablePath))
        let client = MCPClient(transport: transport)
        mcpTask = Task { [weak self] in
            do {
                try await client.connect()
                let tools = try await client.listTools()
                self?.engine = ChatEngine(
                    config: .init(baseURL: settings.baseURL, apiKey: settings.apiKey, model: settings.model),
                    mcp: client)
                await MainActor.run { self?.phase = .ready(toolCount: tools.count) }
            } catch {
                await MainActor.run { self?.phase = .failed(error.localizedDescription) }
                await client.disconnect()
            }
        }
    }

    public func disconnect() {
        mcpTask?.cancel()
        mcpTask = nil
        engine = nil
        phase = .idle
    }

    private(set) var engine: ChatEngine?

    public func sendDraft() async {
        let text = draft.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, let engine else { return }
        draft = ""
        lines.append(Line(role: "user", text: text))
        isBusy = true
        defer { isBusy = false }
        do {
            let answer = try await engine.send(text)
            lines.append(Line(role: "assistant", text: answer))
        } catch {
            lines.append(Line(role: "system", text: "⚠️ \(error.localizedDescription)"))
        }
    }
}
