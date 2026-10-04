import Foundation
import FoundationModels
import Resolume

@available(macOS 26.0, *)
struct MCPFoundationModelTool: Tool {
    typealias Arguments = GeneratedContent
    typealias Output = String

    let name: String
    let description: String
    let parameters: GenerationSchema
    private let mcpName: String
    private let client: MCPClient
    private let policy: ToolPolicy

    init(
        info: MCPToolInfo,
        client: MCPClient,
        policy: ToolPolicy
    ) throws {
        mcpName = info.name
        name = info.name
        description = info.description ?? "Ferramenta MCP do Resolume Arena."
        self.client = client
        self.policy = policy
        parameters = try GenerationSchema(
            root: Self.schema(
                for: ToolSchemaNormalizer.normalize(info.inputSchema),
                name: info.name,
                required: []),
            dependencies: [])
    }

    func call(arguments: Arguments) async throws -> Output {
        let decoder = JSONDecoder()
        let value = try decoder.decode(
            MCPValue.self, from: Data(arguments.jsonString.utf8))
        let mcpArguments: [String: MCPValue]
        if case .object(let object) = value {
            mcpArguments = object
        } else if value == .null {
            mcpArguments = [:]
        } else {
            return "Erro MCP: argumentos precisam ser um objeto JSON."
        }

        guard policy.allows(tool: mcpName, arguments: mcpArguments) else {
            return ToolPolicy.refusal(
                tool: mcpName,
                action: mcpArguments["action"]?.stringValue)
        }

        let result = try await client.callTool(mcpName, arguments: mcpArguments)
        let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.isError {
            return "Erro MCP: \(text)"
        }
        return text.isEmpty ? "ok" : text
    }

    private static func schema(
        for value: MCPValue,
        name: String,
        required: Set<String>
    ) throws -> DynamicGenerationSchema {
        guard let object = value.objectValue else {
            return DynamicGenerationSchema(type: String.self)
        }

        let requiredNames = Set(object["required"]?.arrayValue?.compactMap(\.stringValue) ?? [])
        let mergedRequired = required.isEmpty ? requiredNames : required
        if let properties = object["properties"]?.objectValue {
            return try DynamicGenerationSchema(
                name: name,
                description: object["description"]?.stringValue,
                properties: properties.keys.sorted().compactMap { property in
                    guard let propertySchema = properties[property] else { return nil }
                    return try DynamicGenerationSchema.Property(
                        name: property,
                        description: propertySchema["description"]?.stringValue,
                        schema: schema(for: propertySchema, name: property, required: []),
                        isOptional: !mergedRequired.contains(property))
                })
        }

        if let type = object["type"]?.stringValue {
            return primitive(type, name: name, description: object["description"]?.stringValue, schema: object)
        }

        if let choices = object["enum"]?.arrayValue?.compactMap(\.stringValue), !choices.isEmpty {
            return DynamicGenerationSchema(
                name: name,
                description: object["description"]?.stringValue,
                anyOf: choices)
        }

        return DynamicGenerationSchema(type: String.self)
    }

    private static func primitive(
        _ type: String,
        name: String,
        description: String?,
        schema object: [String: MCPValue]
    ) -> DynamicGenerationSchema {
        if let choices = object["enum"]?.arrayValue?.compactMap(\.stringValue), !choices.isEmpty {
            return DynamicGenerationSchema(name: name, description: description, anyOf: choices)
        }

        switch type {
        case "boolean":
            return DynamicGenerationSchema(type: Bool.self)
        case "number":
            return DynamicGenerationSchema(type: Double.self)
        case "integer":
            return DynamicGenerationSchema(type: Int.self)
        case "array":
            let itemSchema = object["items"].flatMap {
                try? schema(for: $0, name: "\(name)Item", required: [])
            }
            return DynamicGenerationSchema(
                arrayOf: itemSchema ?? DynamicGenerationSchema(type: String.self))
        case "object":
            return DynamicGenerationSchema(name: name, description: description, properties: [])
        default:
            return DynamicGenerationSchema(type: String.self)
        }
    }
}

@available(macOS 26.0, *)
enum MCPFoundationModelToolFactory {
    static func makeTools(
        from infos: [MCPToolInfo],
        client: MCPClient,
        policy: ToolPolicy
    ) -> [any Tool] {
        infos.compactMap { info in
            try? MCPFoundationModelTool(info: info, client: client, policy: policy)
        }
    }
}
