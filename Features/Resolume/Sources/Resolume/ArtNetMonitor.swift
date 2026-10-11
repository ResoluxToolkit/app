import Darwin
import Foundation

public struct ArtNetNode: Sendable, Equatable, Codable {
    public let ipAddress: String
    public let shortName: String
    public let longName: String
    public let status1: UInt8
}

public struct ArtNetPollResult: Sendable, Equatable, Codable {
    public let nodes: [ArtNetNode]
    public let replyCount: UInt64
    public let error: String?
}

public struct ArtNetPacket: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case dmx
        case nzs
        case poll
        case pollReply
        case timeCode
        case sync
        case other
    }

    public let kind: Kind
    public let universe: UInt16?
}

public enum ArtNetParser {
    public static let artNetPort: UInt16 = 6454

    static func packet(in datagram: [UInt8]) -> ArtNetPacket? {
        guard datagram.count >= 12, Array(datagram[0..<8]) == Array("Art-Net\0".utf8) else { return nil }
        let opcode = UInt16(datagram[8]) | (UInt16(datagram[9]) << 8)
        var universe: UInt16?
        switch opcode {
        case 0x5000, 0x5400:
            guard datagram.count >= 18 else { return nil }
            universe = UInt16(datagram[14]) | (UInt16(datagram[15]) << 8)
        default:
            universe = nil
        }
        let kind: ArtNetPacket.Kind
        switch opcode {
        case 0x5000: kind = .dmx
        case 0x5400: kind = .nzs
        case 0x2000: kind = .poll
        case 0x2100: kind = .pollReply
        case 0x6100: kind = .timeCode
        case 0x5200: kind = .sync
        default: kind = .other
        }
        return ArtNetPacket(kind: kind, universe: universe)
    }

    static func node(from datagram: [UInt8]) -> ArtNetNode? {
        guard datagram.count >= 26, Array(datagram[0..<8]) == Array("Art-Net\0".utf8) else { return nil }
        let opcode = UInt16(datagram[8]) | (UInt16(datagram[9]) << 8)
        guard opcode == 0x2100 else { return nil }
        let ipAddress = "\(datagram[10]).\(datagram[11]).\(datagram[12]).\(datagram[13])"
        let shortName = cString(datagram, start: 26, maxLength: 18)
        let longName = datagram.count >= 108 ? cString(datagram, start: 44, maxLength: 64) : ""
        return ArtNetNode(ipAddress: ipAddress, shortName: shortName, longName: longName, status1: datagram[23])
    }

    static func pollDatagram(talkToMe: UInt8 = 0) -> [UInt8] {
        var datagram = Array("Art-Net\0".utf8)
        datagram += [0x00, 0x20, 0x00, 0x0E, talkToMe]
        return datagram
    }

    private static func cString(_ datagram: [UInt8], start: Int, maxLength: Int) -> String {
        let end = min(start + maxLength, datagram.count)
        var bytes = datagram[start..<end]
        if let zero = bytes.firstIndex(of: 0) {
            bytes = bytes[..<zero]
        }
        return String(decoding: bytes, as: UTF8.self)
    }
}

public actor ArtNetPollProbe {
    private let timeout: TimeInterval

    public init(timeout: TimeInterval = 1.0) {
        self.timeout = timeout
    }

    public func poll(broadcast: Bool = true) async -> ArtNetPollResult {
        let fileDescriptor = socket(AF_INET, SOCK_DGRAM, 0)
        guard fileDescriptor >= 0 else {
            return ArtNetPollResult(nodes: [], replyCount: 0, error: "socket: errno \(errno)")
        }
        defer { Darwin.close(fileDescriptor) }
        if broadcast {
            var one: Int32 = 1
            _ = setsockopt(fileDescriptor, SOL_SOCKET, SO_BROADCAST, &one, socklen_t(MemoryLayout<Int32>.size))
        }
        var destination = sockaddr_in()
        destination.sin_family = sa_family_t(AF_INET)
        destination.sin_port = ArtNetParser.artNetPort.bigEndian
        destination.sin_addr.s_addr = broadcast ? INADDR_BROADCAST : INADDR_LOOPBACK
        let datagram = ArtNetParser.pollDatagram()
        var sendErrno: Int32 = 0
        let sent = datagram.withUnsafeBufferPointer { payload in
            withUnsafePointer(to: destination) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { address in
                    sendto(
                        fileDescriptor,
                        payload.baseAddress,
                        payload.count,
                        0,
                        address,
                        socklen_t(MemoryLayout<sockaddr_in>.size)
                    )
                }
            }
        }
        if sent < 0 { sendErrno = errno }
        guard sent == datagram.count else {
            return ArtNetPollResult(nodes: [], replyCount: 0, error: "send: errno \(sendErrno)")
        }
        let deadline = Date().addingTimeInterval(timeout)
        var replyCount: UInt64 = 0
        var nodes: [ArtNetNode] = []
        while Date() < deadline {
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else { break }
            var pollDescriptor = pollfd(fd: fileDescriptor, events: Int16(POLLIN), revents: 0)
            let ready = Darwin.poll(&pollDescriptor, 1, Int32((remaining * 1000).rounded(.down)))
            guard ready > 0, pollDescriptor.revents & Int16(POLLIN) != 0 else { continue }
            var buffer = [UInt8](repeating: 0, count: 2048)
            let bytesRead = recv(fileDescriptor, &buffer, buffer.count, 0)
            guard bytesRead > 0 else { continue }
            let datagram = Array(buffer[0..<bytesRead])
            if let node = ArtNetParser.node(from: datagram) {
                replyCount += 1
                if !nodes.contains(node) {
                    nodes.append(node)
                }
            }
        }
        return ArtNetPollResult(
            nodes: nodes.sorted { $0.ipAddress < $1.ipAddress },
            replyCount: replyCount,
            error: nil
        )
    }
}
