import Foundation
import Pulse

/// Auditoria de rede do motor: todo HTTP de saida (REST do Arena, proxy do
/// daemon, sondas de backend e transporte de chat) passa por um
/// `NetworkLogger` do Pulse gravando num `LoggerStore` em disco — arquivo
/// `.pulse` que o Pulse Pro abre direto ("View Previously Shared Logs").
///
/// O Pulse so registra o que o motor ja fala: nao altera pedidos nem
/// respostas, entao a leitura pura do REST continua valendo.
public enum PulseAudit {
    /// Local padrao do registro (`.pulse` e uma pasta-bundle com SQLite).
    public static let defaultStoreURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appending(path: "Resolux/Network.pulse")
    }()

    private static let compartilhada = AuditorCompartilhada()

    /// Auditor compartilhada: cria o store no disco na primeira sessao pedida.
    /// Se o disco falhar, cai para memoria -- auditoria nunca trava o motor.
    public static func shared() -> PulseAuditor {
        compartilhada.getOrCreate()
    }
}

private final class AuditorCompartilhada: @unchecked Sendable {
    private let lock = NSLock()
    private var auditor: PulseAuditor?

    func getOrCreate() -> PulseAuditor {
        lock.lock()
        defer { lock.unlock() }
        if let auditor { return auditor }
        let nova: PulseAuditor
        if let disco = try? PulseAuditor(storeURL: PulseAudit.defaultStoreURL) {
            nova = disco
        } else {
            nova = try! PulseAuditor(storeURL: PulseAudit.defaultStoreURL, emMemoria: true)
        }
        auditor = nova
        return nova
    }
}

/// Um `NetworkLogger` + `LoggerStore` e as sessoes `URLSession` que passam
/// por eles. Sessoes novas gravam automaticamente: criacao, corpo, resposta
/// e metricas de cada task (macOS 13+ loga a criacao via `didCreateTask`).
public final class PulseAuditor: @unchecked Sendable {
    public let store: LoggerStore
    public let networkLogger: NetworkLogger

    /// Store em disco (`emMemoria: false`, modo append — cada sessao soma ao
    /// mesmo registro e `.sweep` corta o arquivo ao passar do limite) ou
    /// apenas na memoria (`true`, testes e fallback).
    public init(storeURL: URL, emMemoria: Bool = false) throws {
        if emMemoria {
            self.store = try LoggerStore(storeURL: storeURL, options: [.inMemory, .synchronous])
        } else {
            try FileManager.default.createDirectory(
                at: storeURL.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            self.store = try LoggerStore(storeURL: storeURL, options: [.create, .sweep])
        }
        self.networkLogger = NetworkLogger(store: store) { configuration in
            configuration.label = "Resolux"
            configuration.sensitiveHeaders = ["Authorization", "Proxy-Authorization"]
        }
    }

    /// Proxy async do Pulse: `data(for:)`, `data(from:)` e `bytes(for:)` saem
    /// gravados de ponta a ponta. Motivo do proxy: o `data(for:)` async do
    /// Foundation nao repassa os eventos ao session delegate — o Pulse entra
    /// como task delegate e registra corpo/resposta no fim da task. Mocking
    /// desligado: sem mock registrado, o MockingURLProtocol falharia o trafego.
    public func makeProxy(
        configuration: URLSessionConfiguration = .ephemeral,
        delegate: (any URLSessionDelegate)? = nil) -> URLSessionProxy {
        var options = URLSessionProxy.Options()
        options.isMockingEnabled = false
        return URLSessionProxy(
            configuration: configuration,
            delegate: delegate,
            delegateQueue: nil,
            logger: networkLogger,
            options: options)
    }

    /// Tasks de rede gravadas ate agora (diagnostico e testes).
    public func tasks() throws -> [NetworkTaskEntity] {
        try store.tasks()
    }
}
