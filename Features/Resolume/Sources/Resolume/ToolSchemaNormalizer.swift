import Foundation

/// Adapta o JSON Schema que o servidor MCP da Resolume publica para o subconjunto
/// que os backends locais aceitam.
///
/// Medido nesta máquina, com o `tools/list` real do Arena (22 ferramentas):
/// - Ollama (:11434): aceita o schema cru **e** o normalizado.
/// - `fm serve` (:1976, Apple Foundation Models): devolve **HTTP 400** no schema
///   cru. Não é tamanho -- uma ferramenta só já caía. São quatro construtos:
///   união de tipo (`"type": ["string","null"]`), nó com `anyOf`/`oneOf`,
///   `additionalProperties: {}` vazio e propriedade de objeto sem `type`.
///   Metadado (`$schema`, `title`, `format`, `default`) ele engole tranquilo,
///   então nada disso é descartado aqui.
///
/// Normalizar sempre é a escolha segura (passa nos dois provedores) e dispensa
/// detecção de fornecedor -- convention over configuration.
///
/// Um preço honesto: quando o schema original não declara tipo algum (ex.:
/// `value` em `parameter`, que aceita número, booleano ou string), somos
/// obrigados a declarar alguma coisa e declaramos `string`. Backend que não
/// souber fazer coercão pode receber `"0.5"` onde queria `0.5`. É leitura de
/// argumento de escrita, e escrita já está travada pelo `ToolPolicy` em modo
/// leitura -- por isso aceitamos o troca-galho aqui.
public enum ToolSchemaNormalizer {
    public static func normalize(_ schema: MCPValue) -> MCPValue {
        switch schema {
        case .array(let items):
            return .array(items.map(normalize))
        case .object(let pairs):
            return normalizeObject(pairs)
        default:
            return schema
        }
    }

    private static func normalizeObject(_ input: [String: MCPValue]) -> MCPValue {
        var node: [String: MCPValue] = [:]
        for (key, value) in input {
            node[key] = normalize(value)
        }

        collapseTypeUnion(&node)
        dropEmptyAdditionalProperties(&node)
        for combinator in ["anyOf", "oneOf"] {
            collapseCombinator(combinator, in: &node)
        }
        requirePropertyTypes(&node)
        return .object(node)
    }

    /// `"type": ["string", "null"]` -> `"type": "string"`.
    private static func collapseTypeUnion(_ node: inout [String: MCPValue]) {
        guard case .array(let types) = node["type"] else { return }
        let kept = types.compactMap(\.stringValue).filter { $0 != "null" }
        if let first = kept.first {
            node["type"] = .string(first)
        } else {
            node["type"] = nil
        }
    }

    /// `additionalProperties: {}` não agrega nada e o `fm` recusa.
    private static func dropEmptyAdditionalProperties(_ node: inout [String: MCPValue]) {
        guard case .object(let inner)? = node["additionalProperties"], inner.isEmpty else { return }
        node["additionalProperties"] = nil
    }

    /// Fica o primeiro ramo não-`null` do `anyOf`/`oneOf`, mesclado no próprio nó.
    private static func collapseCombinator(
        _ key: String, in node: inout [String: MCPValue]
    ) {
        guard case .array(let branches)? = node[key] else { return }
        node[key] = nil
        let candidates = branches.filter { $0["type"]?.stringValue != "null" }
        if let branch = candidates.first, case .object(let merged) = normalize(branch) {
            for (name, value) in merged where node[name] == nil {
                node[name] = value
            }
        }
        if node["type"] == nil { node["type"] = .string("string") }
    }

    /// Propriedade de objeto sem `type` derruba o backend.
    private static func requirePropertyTypes(_ node: inout [String: MCPValue]) {
        guard node["type"]?.stringValue == "object",
              case .object(let properties)? = node["properties"]
        else { return }
        var fixed: [String: MCPValue] = [:]
        for (name, property) in properties {
            guard case .object(var fields) = property else { fixed[name] = property; continue }
            if fields["type"] == nil { fields["type"] = .string("string") }
            fixed[name] = .object(fields)
        }
        node["properties"] = .object(fixed)
    }
}
