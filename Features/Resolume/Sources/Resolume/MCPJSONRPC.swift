import Foundation

public struct MCPRequest: Encodable, Sendable {
    public let jsonrpc = "2.0"
    public let id: Int
    public let method: String
    public let params: [String: MCPValue]?
}

public struct MCPNotification: Encodable, Sendable {
    public let jsonrpc = "2.0"
    public let method: String
}

public struct MCPResponse: Decodable, Sendable {
    public struct Error: Decodable, Sendable, CustomStringConvertible {
        public let code: Int
        public let message: String
        public var description: String { "JSON-RPC \(code): \(message)" }
    }

    public let id: Int?
    public let result: MCPValue?
    public let error: Error?
}
