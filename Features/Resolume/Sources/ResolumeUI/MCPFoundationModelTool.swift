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
    private let journal: WriteJournal?

    init(
        info: MCPToolInfo,
        client: MCPClient,
        policy: ToolPolicy,
        journal: WriteJournal? = nil
    ) throws {
        mcpName = info.name
        name = info.name
        description = info.description ?? "Ferramenta MCP do Resolume Arena."
        self.client = client
        self.policy = policy
        self.journal = journal
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

        // Escrita permitida: mesma regra do ChatEngine -- capturamos o valor
        // antigo onde existe leitura espelhada e registramos no diário. Sem isso,
        // o fallback FM mudaria o set sem rastro nenhum.
        let previous = await previousValue(tool: mcpName, arguments: mcpArguments)
        do {
            let result = try await client.callTool(mcpName, arguments: mcpArguments)
            await record(
                tool: mcpName, arguments: mcpArguments, result: result.text,
                isError: result.isError, previous: previous)
            let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if result.isError {
                return "Erro MCP: \(text)"
            }
            return text.isEmpty ? "ok" : text
        } catch {
            await record(
                tool: mcpName, arguments: mcpArguments,
                result: error.localizedDescription, isError: true, previous: previous)
            throw error
        }
    }

    /// Valor anterior só faz sentido em escrita de `parameter`; igual ao ChatEngine.
    private func previousValue(
        tool: String, arguments: [String: MCPValue]) async -> String? {
        guard journal != nil, ToolPolicy.isWrite(tool: tool, arguments: arguments) else { return nil }
        guard let readArguments = WriteJournal.mirroredRead(tool: tool, arguments: arguments) else { return nil }
        return try? await client.callTool("parameter", arguments: readArguments).text
    }

    private func record(
        tool: String, arguments: [String: MCPValue], result: String,
        isError: Bool, previous: String?) async {
        guard let journal, ToolPolicy.isWrite(tool: tool, arguments: arguments) else { return }
        try? await journal.record(
            tool: tool, arguments: arguments, result: result,
            isError: isError, previous: previous.map { WriteJournal.cap($0) })
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
        policy: ToolPolicy,
        journal: WriteJournal? = nil
    ) -> [any Tool] {
        infos.compactMap { info in
            try? MCPFoundationModelTool(info: info, client: client, policy: policy, journal: journal)
        }
    }
}
