import Foundation

/// Resgate de `tool_calls` que o backend escreveu como **texto** em vez de usar o
/// campo nativo do wire format.
///
/// Caso real medido nesta máquina: `fm serve` (Apple Foundation Models, :1976)
/// aceita `tools` na requisição, mas devolve a chamada dentro de
/// `message.content` como bloco ```json, com `finish_reason: "stop"`. Sem este
/// arquivo o loop de ferramentas lê aquilo como resposta final e nenhuma
/// ferramenta MCP roda: o operador pergunta algo do set e o modelo chuta.
///
/// Segurança: só voltam chamadas cujo nome está na lista que o **servidor MCP**
/// devolveu em `tools/list`. Nome desconhecido é descartado, nunca executado —
/// texto de modelo pequeno não é fonte de verdade sobre o que existe.
public enum ToolCallTextRescue {
    public struct Outcome: Sendable, Equatable {
        /// Chamadas no formato do wire format, prontas para o histórico.
        public var calls: [ChatMessage.ToolCall]
        /// Texto que sobra depois de remover o bloco que interpretamos como
        /// chamada. Devolver o texto cru ao modelo na rodada seguinte o incentiva
        /// a repetir o mesmo bloco para sempre.
        public var remainingText: String
    }

    public static func rescue(
        from content: String,
        knownTools: Set<String>,
        idPrefix: String = "rescued"
    ) -> Outcome? {
        guard !knownTools.isEmpty else { return nil }
        for candidate in candidates(in: content) {
            guard let calls = calls(from: candidate.json, knownTools: knownTools, idPrefix: idPrefix)
            else { continue }
            var stripped = content
            stripped.removeSubrange(candidate.span)
            return Outcome(
                calls: calls,
                remainingText: stripped.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

    // MARK: - Localização do JSON no texto

    private struct Candidate {
        var json: Substring
        var span: Range<String.Index>
    }

    private static func candidates(in text: String) -> [Candidate] {
        let fenced = fencedBlocks(in: text)
        return fenced + objectSpans(in: text, skipping: fenced.map(\.span))
    }

    /// Blocos delimitados por ``` (com ou sem etiqueta de linguagem).
    private static func fencedBlocks(in text: String) -> [Candidate] {
        var result: [Candidate] = []
        var cursor = text.startIndex
        while let open = text.range(of: "```", range: cursor..<text.endIndex),
              let close = text.range(of: "```", range: open.upperBound..<text.endIndex) {
            let body = open.upperBound..<close.lowerBound
            var json = body
            // Etiqueta de linguagem (```json) fica na primeira linha do bloco.
            if let newline = text.range(of: "\n", range: body) {
                let head = text[body.lowerBound..<newline.lowerBound]
                if !head.isEmpty && !head.contains("{") {
                    json = newline.upperBound..<body.upperBound
                }
            }
            result.append(Candidate(json: text[json], span: open.lowerBound..<close.upperBound))
            cursor = close.upperBound
        }
        return result
    }

    /// Objetos `{...}` soltos no texto, com balanceamento que ignora chaves
    /// dentro de string. Span já usado por um bloco cercado é pulado.
    private static func objectSpans(in text: String, skipping skip: [Range<String.Index>]) -> [Candidate] {
        var result: [Candidate] = []
        var depth = 0
        var openedAt: String.Index?
        var inString = false
        var escaped = false
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            if inString {
                if escaped {
                    escaped = false
                } else if character == #"\"# {
                    escaped = true
                } else if character == "\"" {
                    inString = false
                }
            } else {
                switch character {
                case "\"": inString = true
                case "{":
                    if depth == 0 { openedAt = index }
                    depth += 1
                case "}":
                    if depth > 0 {
                        depth -= 1
                        if depth == 0, let opened = openedAt {
                            let span = opened..<text.index(after: index)
                            if !skip.contains(where: { $0.overlaps(span) }) {
                                result.append(Candidate(json: text[span], span: span))
                            }
                            openedAt = nil
                        }
                    }
                default: break
                }
            }
            index = text.index(after: index)
        }
        return result
    }

    // MARK: - Leitura das chamadas

    private static func calls(
        from json: Substring,
        knownTools: Set<String>,
        idPrefix: String
    ) -> [ChatMessage.ToolCall]? {
        guard let value = try? JSONDecoder().decode(MCPValue.self, from: Data(json.utf8)) else {
            return nil
        }
        let items = value["tool_calls"]?.arrayValue ?? [value]
        var calls: [ChatMessage.ToolCall] = []
        for item in items {
            guard let name = itemName(from: item), knownTools.contains(name) else { continue }
            guard let arguments = argumentsString(from: item) else { continue }
            calls.append(ChatMessage.ToolCall(
                id: "\(idPrefix)_\(calls.count + 1)",
                function: .init(name: name, arguments: arguments)))
        }
        return calls.isEmpty ? nil : calls
    }

    /// Aceita `{"name":...}` e também o aninhado `{"function":{"name":...}}`.
    private static func itemName(from item: MCPValue) -> String? {
        item["name"]?.stringValue ?? item["function"]?["name"]?.stringValue
    }

    /// `arguments` chega como objeto ou, no wire format oficial, como string JSON.
    private static func argumentsString(from item: MCPValue) -> String? {
        guard let raw = item["arguments"] ?? item["function"]?["arguments"] else { return "{}" }
        switch raw {
        case .null:
            return "{}"
        case .string(let encoded):
            guard let data = encoded.data(using: .utf8),
                  (try? JSONDecoder().decode(MCPValue.self, from: data)) != nil
            else { return nil }
            return encoded
        default:
            guard case .object = raw else { return nil }
            guard let data = try? JSONEncoder().encode(raw) else { return nil }
            return String(data: data, encoding: .utf8)
        }
    }
}
