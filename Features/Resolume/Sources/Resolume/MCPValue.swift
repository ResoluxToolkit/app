import Foundation

/// Valor JSON dinâmico para payloads JSON-RPC do servidor MCP da Resolume.
public enum MCPValue: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([MCPValue])
    case object([String: MCPValue])

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([MCPValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: MCPValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "MCPValue: valor JSON não suportado")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    public var objectValue: [String: MCPValue]? {
        if case .object(let value) = self { value } else { nil }
    }

    public var arrayValue: [MCPValue]? {
        if case .array(let value) = self { value } else { nil }
    }

    public var stringValue: String? {
        if case .string(let value) = self { value } else { nil }
    }

    public subscript(key: String) -> MCPValue? {
        objectValue?[key]
    }
}
