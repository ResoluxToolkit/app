import Foundation

/// Diário em JSON-lines de tudo que nossa automação **escreveu** no set.
///
/// Por que isso existe (palavra do operador): nada do que fazemos via MCP entra
/// no undo/redo do Arena. O `composition { action: "diff" }` dele devolve uma
/// baseline, não histórico, e `composition.undo|redo` está vetado pra sempre —
/// então o Cmd-Z do VJ não alcança nenhuma das nossas mudanças. Sem diário
/// nosso, uma escrita virava fato consumado sem rastro. Este arquivo é o rastro.
///
/// Escolhas conscientes: só grava execução **permitida** (recusa de política não
/// toca o set e poluiria a leitura); um arquivo por sessão, sem porta nova e sem
/// escrever em pasta do Arena; pré-leitura do valor antigo só onde ela existe de
/// forma limpa (`parameter`), porque os próprios `instructions` do servidor avisam
/// que snapshot universal custa token.
public actor WriteJournal {
    /// Uma linha do diário. `previous` só vem preenchido onde há leitura espelhada.
    public struct Entry: Sendable, Codable, Equatable {
        /// **Epoch segundos** desde 1970-01-01 (regra do operador para data/hora).
        /// Zero fuso, zero locale, zero string: quem precisa de "18:04:31" calcula
        /// na apresentação, nunca aqui. Int encosta de propósito -- fração de segundo
        /// não ordena nada que a posição no arquivo já não ordene.
        public let timestamp: Int
        public let session: String
        public let tool: String
        public let action: String?
        public let arguments: [String: MCPValue]
        public let previous: String?
        public let isError: Bool
        public let result: String
    }

    /// Do resultado guarda só um trecho. O payload inteiro do Arena é grande
    /// demais pra um registro que se quer ler de olho numa tela de "últimas mudanças".
    public static let resultLimit = 200

    public let sessionID: String
    private let directory: URL

    public init(
        directory: URL = WriteJournal.defaultDirectory(),
        sessionID: String? = nil,
        now: Date = Date()
    ) {
        self.directory = directory
        self.sessionID = sessionID ?? WriteJournal.makeSessionID(now: now)
    }

    /// Pasta nossa, dentro do nosso domínio de aplicação. Nada aqui encosta em
    /// arquivo do Arena (regra da imutabilidade).
    public nonisolated static func defaultDirectory() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return support
            .appendingPathComponent("Resolux", isDirectory: true)
            .appendingPathComponent("journal", isDirectory: true)
    }

    public nonisolated var url: URL {
        directory.appendingPathComponent("\(sessionID).jsonl")
    }

    /// Registra uma execução permitida. Falha de disco nunca interrompe o turno:
    /// quem chama usa `try?`, o show vem antes do log.
    public func record(
        tool: String,
        arguments: [String: MCPValue],
        result: String,
        isError: Bool,
        previous: String?,
        now: Date = Date()
    ) throws {
        let entry = Entry(
            timestamp: Self.stamp(now),
            session: sessionID,
            tool: tool,
            action: arguments["action"]?.stringValue,
            arguments: arguments,
            previous: previous,
            isError: isError,
            result: Self.cap(result))
        var line = try JSONEncoder().encode(entry)
        line.append(Data("\n".utf8))

        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: directory, withIntermediateDirectories: true, attributes: nil)
        let destination = url
        if !fileManager.fileExists(atPath: destination.path) {
            // Cria vazio de propósito: escrever sem existir pelo FileHandle falha,
            // e apagar/recriar o arquivo jogaria fora o turno anterior da sessão.
            fileManager.createFile(atPath: destination.path, contents: nil, attributes: nil)
        }
        let handle = try FileHandle(forWritingTo: destination)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: line)
    }

    /// Lê o diário do mais recente pro mais antigo — é a ordem que a tela
    /// "últimas mudanças" precisa. Linha ilegível é pulada, não derruba a leitura
    /// do resto: meio arquivo ainda conta mais que arquivo nenhum.
    public nonisolated static func entries(at url: URL) -> [Entry] {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        let parsed = content.split(separator: "\n").compactMap { line in
            try? JSONDecoder().decode(Entry.self, from: Data(line.utf8))
        }
        return Array(parsed.reversed())
    }

    /// Argimentos da leitura espelhada de uma escrita, ou `nil` quando não há
    /// paridade leitura/escrita. `parameter` é o único tool onde isso vale —
    /// `get` ↔ `set` e `get_animation` ↔ `set_animation`. Ler o `get` de outro
    /// tool seria inventar argumento que o schema não declara, e ler `parameter`
    /// no meio de uma escrita de `transport` seria chamar o tool errado.
    public nonisolated static func mirroredRead(
        tool: String, arguments: [String: MCPValue]) -> [String: MCPValue]? {
        guard tool == "parameter" else { return nil }
        guard let action = arguments["action"]?.stringValue else { return nil }
        let readAction: String
        switch action {
        case "set": readAction = "get"
        case "set_animation": readAction = "get_animation"
        default: return nil
        }
        var copy = arguments
        copy["action"] = .string(readAction)
        return copy
    }

    public nonisolated static func cap(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > resultLimit else { return trimmed }
        return String(trimmed.prefix(resultLimit)) + "…"
    }

    /// Nome de arquivo começa em epoch segundos também (mesma regra: nada de data/hora
    /// em string local, que muda com fuso e fica ambígua num diário lido depois). A
    /// cauda aleatória evita colisão quando duas sessões abrem no mesmo segundo.
    nonisolated static func makeSessionID(now: Date) -> String {
        String(stamp(now)) + "-" + String(UUID().uuidString.prefix(6)).lowercased()
    }

    /// O único lugar onde o diário enxerga relógio, e devolve **epoch segundos**.
    /// Trocado de ISO-8601 pra cá em 2026-09-27 por voto dele: *"Sempre que envolver
    /// Data/Hora."* Formato em disco jovem na época (nenhum `.jsonl` nosso existia),
    /// então não houve migração -- se houver arquivo antigo, ele não decodifica como
    /// `Entry` e cai no caminho de linha ilegível (pulado, sem derrubar a leitura).
    nonisolated static func stamp(_ date: Date) -> Int {
        Int(date.timeIntervalSince1970.rounded(.down))
    }
}
