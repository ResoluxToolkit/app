import Foundation
import Resolume

/// Pedido HTTP mínimo (uma requisição por conexão; o daemon responde com
/// `Connection: close`). Basta para o /api/v1 do contrato — sem upload, sem
/// streaming, sem keep-alive.
public struct PedidoHttp: Sendable {
    public var metodo: String
    public var caminho: String
    public var cabecalhos: [String: String]
    public var corpo: Data

    /// Parse de um buffer. Devolve `nil` enquanto os cabeçalhos ou o corpo
    /// (por Content-Length) não chegarem por completo.
    public static func parse(_ dados: Data) -> PedidoHttp? {
        guard let separador = dados.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let cabecalhoTexto = String(data: dados.subdata(in: dados.startIndex..<separador.lowerBound), encoding: .utf8) ?? ""
        var linhas = cabecalhoTexto.components(separatedBy: "\r\n")
        guard !linhas.isEmpty else { return nil }
        let primeira = linhas.removeFirst().split(separator: " ", omittingEmptySubsequences: true)
        guard primeira.count >= 2 else { return nil }
        var cabecalhos: [String: String] = [:]
        for linha in linhas {
            guard let pos = linha.firstIndex(of: ":") else { continue }
            let nome = linha[..<pos].trimmingCharacters(in: .whitespaces).lowercased()
            let valor = linha[linha.index(after: pos)...].trimmingCharacters(in: .whitespaces)
            cabecalhos[nome] = valor
        }
        let comprimento = Int(cabecalhos["content-length"] ?? "0") ?? 0
        let indiceCorpo = separador.upperBound
        guard dados.count - indiceCorpo >= comprimento else { return nil }
        return PedidoHttp(
            metodo: String(primeira[0]).uppercased(),
            caminho: String(primeira[1]),
            cabecalhos: cabecalhos,
            corpo: dados.subdata(in: indiceCorpo..<indiceCorpo + comprimento))
    }

    /// Caminho sem query string (o proxy do Arena usa caminhos puros).
    public var rota: String {
        if let pos = caminho.firstIndex(of: "?") { String(caminho[..<pos]) }
        else { caminho }
    }
}

public struct RespostaHttp: Sendable {
    public var status: Int
    public var contentType: String
    public var corpo: Data

    public init(status: Int, contentType: String, corpo: Data) {
        self.status = status
        self.contentType = contentType
        self.corpo = corpo
    }

    public static func json(_ data: Data, status: Int = 200) -> RespostaHttp {
        RespostaHttp(status: status, contentType: "application/json; charset=utf-8", corpo: data)
    }

    public static func erro(codigo: String, mensagem: String, status: Int) -> RespostaHttp {
        let corpo: [String: MCPValue] = [
            "error": .object([
                "code": .string(codigo),
                "message": .string(mensagem),
            ])
        ]
        let data = (try? JSONEncoder().encode(corpo)) ?? Data(#"{"error":{"code":"erro","message":""}}"#.utf8)
        return json(data, status: status)
    }

    public func serializar(semCorpo: Bool = false) -> Data {
        var saida = Data("HTTP/1.1 \(status) \(Self.frase(status))\r\n".utf8)
        saida.append(Data("Content-Type: \(contentType)\r\n".utf8))
        saida.append(Data("Content-Length: \(corpo.count)\r\n".utf8))
        saida.append(Data("Connection: close\r\n\r\n".utf8))
        saida.append(semCorpo ? Data() : corpo)
        return saida
    }

    static func frase(_ status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 400: return "Bad Request"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 502: return "Bad Gateway"
        default: return "OK"
        }
    }
}
