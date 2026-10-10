import Foundation
import Resolume

/// Sessão que o daemon expõe ao cliente web na v1. O motor completo (MCP
/// real, journal, ModeGate) é tacada própria; aqui vive só o que o contrato
/// v1 expõe — sem fingir capacidade: nesta build o daemon anuncia zero
/// ferramentas e journal desligado até o ChatEngine ser plugado.
public struct SessaoV1: Equatable, Sendable {
    public var mode: String
    public var backend: String
    public var model: String
    public var toolAllowlist: [String]?

    public init(
        mode: String = "timeline",
        backend: String = "ollama",
        model: String = "",
        toolAllowlist: [String]? = nil) {
        self.mode = mode
        self.backend = backend
        self.model = model
        self.toolAllowlist = toolAllowlist
    }
}

public enum RecusaSessao: Error, Equatable {
    case corpoInvalido
    case campoDesconhecido(String)
    case valorInvalido(campo: String, valor: String)
}

public enum SessaoV1Regras {
    static let modos = ["timeline", "performance"]
    static let backends = ["ollama", "applefm"]

    /// Aplica um PATCH campo a campo. Campo fora do contrato vira
    /// `.campoDesconhecido` (contrato: 400) e valor fora do domínio vira
    /// `.valorInvalido`.
    public static func aplicar(
        _ patch: [String: MCPValue],
        em sessao: SessaoV1) throws -> SessaoV1 {
        var nova = sessao
        for (campo, valor) in patch {
            switch campo {
            case "mode":
                guard let texto = valor.stringValue else {
                    throw RecusaSessao.valorInvalido(campo: campo, valor: texto(valor))
                }
                guard modos.contains(texto) else {
                    throw RecusaSessao.valorInvalido(campo: campo, valor: texto)
                }
                nova.mode = texto
            case "backend":
                guard let nome = valor.stringValue else {
                    throw RecusaSessao.valorInvalido(campo: campo, valor: texto(valor))
                }
                guard backends.contains(nome) else {
                    throw RecusaSessao.valorInvalido(campo: campo, valor: nome)
                }
                nova.backend = nome
            case "model":
                guard let nome = valor.stringValue else {
                    throw RecusaSessao.valorInvalido(campo: campo, valor: texto(valor))
                }
                nova.model = nome
            case "toolAllowlist":
                if case .null = valor {
                    nova.toolAllowlist = nil
                } else if let lista = valor.arrayValue {
                    var nomes: [String] = []
                    for item in lista {
                        guard let nome = item.stringValue else {
                            throw RecusaSessao.valorInvalido(campo: campo, valor: texto(valor))
                        }
                        nomes.append(nome)
                    }
                    nova.toolAllowlist = nomes
                } else {
                    throw RecusaSessao.valorInvalido(campo: campo, valor: texto(valor))
                }
            default:
                throw RecusaSessao.campoDesconhecido(campo)
            }
        }
        return nova
    }

    /// Snapshot no formato exato do contrato v1. `toolAllowlist` é interno:
    /// o cliente web não consome (GET /session não devolve) — por isso o
    /// aviso "visão local" vive no front até a engine devolver a lista.
    public static func json(_ sessao: SessaoV1) -> Data {
        let dicionario: [String: MCPValue] = [
            "protocol": .string("resolux-api/1"),
            "mode": .string(sessao.mode),
            "backend": .string(sessao.backend),
            "model": .string(sessao.model),
            "toolPolicy": .string("readOnly"),
            "toolsAllowed": .int(sessao.toolAllowlist?.count ?? 0),
            "journalEnabled": .bool(false),
        ]
        return (try? JSONEncoder().encode(dicionario)) ?? Data(#"{"protocol":"resolux-api/1"}"#.utf8)
    }

    private static func texto(_ valor: MCPValue) -> String {
        switch valor {
        case .null: return "null"
        case .bool(let valorBool): return String(valorBool)
        case .int(let valorInt): return String(valorInt)
        case .double(let valorDouble): return String(valorDouble)
        case .string(let valorString): return valorString
        default: return "valor"
        }
    }
}

/// Estado mutável compartilhado por todas as conexões (HTTP e WS).
public actor EstadoSessao {
    private var sessao: SessaoV1

    public init(sessao: SessaoV1 = SessaoV1()) {
        self.sessao = sessao
    }

    public func snapshot() -> SessaoV1 { sessao }

    public func json() -> Data { SessaoV1Regras.json(sessao) }

    public func aplicar(_ patch: [String: MCPValue]) throws -> SessaoV1 {
        sessao = try SessaoV1Regras.aplicar(patch, em: sessao)
        return sessao
    }
}
