import Foundation

/// Cliente minimo do REST embutido no Arena (`http://127.0.0.1:8080/api/v1`).
///
/// Por que REST e nao MCP: o MCP das 22 ferramentas **não devolve duracao** de
/// clipe (nem `clip.get`, nem `layer.get` -- medido). O REST devolve, e devolve
/// numerico. Medido no Arena 7.28.0-rev24303 vivo:
/// - `GET /composition` traz a grade inteira (`layers[].clips[]`, inclusive os
///   slots vazios) com `transport.controls.duration` em **segundos absolutos**;
/// - `POST /file-info` aceita **array** de arquivos numa chamada e devolve
///   `duration_ms`, `framerate{num,denom}`, resolucao e bloco `audio`.
///
/// Leitura pura: nenhuma rota daqui escreve no set. Valem as regras da casa --
/// porta dele nao muda (8080), nada de Preferences/Wire.
public struct ArenaREST: Sendable {
    public enum Failure: Error, Equatable, CustomStringConvertible {
        case http(Int)
        case transporte(String)

        public var description: String {
            switch self {
            case .http(let code): return "REST do Arena devolveu HTTP \(code)"
            case .transporte(let motivo): return "REST do Arena indisponivel: \(motivo)"
            }
        }
    }

    /// Transporte injetavel, para os testes rodarem sem Arena aberto.
    public struct Endpoint: Sendable {
        public var get: @Sendable (String) async throws -> Data
        public var post: @Sendable (String, Data) async throws -> Data

        public init(
            get: @escaping @Sendable (String) async throws -> Data,
            post: @escaping @Sendable (String, Data) async throws -> Data) {
            self.get = get
            self.post = post
        }

        public static func localhost(port: Int = 8080, timeout: TimeInterval = 10) -> Endpoint {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = timeout
            configuration.waitsForConnectivity = false
            let session = URLSession(configuration: configuration)
            let base = "http://127.0.0.1:\(port)/api/v1"

            let status: @Sendable (URLResponse, String) throws -> Int = { response, path in
                guard let http = response as? HTTPURLResponse else {
                    throw Failure.transporte("sem resposta HTTP em \(path)")
                }
                return http.statusCode
            }

            return Endpoint(
                get: { path in
                    guard let url = URL(string: base + path) else {
                        throw Failure.transporte("URL invalida: \(path)")
                    }
                    let (data, response) = try await session.data(from: url)
                    let code = try status(response, path)
                    guard (200..<300).contains(code) else { throw Failure.http(code) }
                    return data
                },
                post: { path, body in
                    guard let url = URL(string: base + path) else {
                        throw Failure.transporte("URL invalida: \(path)")
                    }
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json",
                                     forHTTPHeaderField: "Content-Type")
                    request.httpBody = body
                    let (data, response) = try await session.data(for: request)
                    let code = try status(response, path)
                    guard (200..<300).contains(code) else { throw Failure.http(code) }
                    return data
                })
        }
    }

    public var endpoint: Endpoint

    public init(endpoint: Endpoint = .localhost()) { self.endpoint = endpoint }

    /// Composicao inteira numa chamada. Daqui sai camada por camada com a grade
    /// completa e o `autopilot` de cada camada -- que e o detector de intencao.
    public func composition() async throws -> MCPValue {
        try decode(try await endpoint.get("/composition"))
    }

    /// Duracao de N arquivos numa chamada so. Arquivo sem trilha de video (um
    /// `.drift`, um `.DS_Store`) vem sem o bloco `video`: isso e sinal legitimo,
    /// nao erro.
    public func fileInfo(_ paths: [String]) async throws -> [MCPValue] {
        let body = try JSONEncoder().encode(paths.map { Self.fileURI($0) })
        guard let values = try decode(try await endpoint.post("/file-info", body)).arrayValue
        else { throw Failure.transporte("file-info não devolveu array") }
        return values
    }

    /// Percent-encoding obrigatorio: medido com "Hello World.drift" -- espaco
    /// cru fazia o servidor responder como se o arquivo nao existisse.
    static func fileURI(_ path: String) -> String {
        let allowed = CharacterSet(charactersIn: "/:").union(.alphanumerics)
        let encoded = path.addingPercentEncoding(withAllowedCharacters: allowed) ?? path
        return "file://" + encoded
    }

    private func decode(_ data: Data) throws -> MCPValue {
        try JSONDecoder().decode(MCPValue.self, from: data)
    }
}
