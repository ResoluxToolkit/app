import Darwin
import Foundation
import Testing
@testable import Resolume

/// Regressão do falso-positivo de prontidão: o `rest-api.sock` sobrevive ao
/// fechamento do Arena, então `fileExists` respondia "pronto" e o app ficava
/// preso em "Conectando…" falando com um socket morto.
@Test("socket com listen passa na sonda", .timeLimit(.minutes(1)))
func liveSocketPassesProbe() throws {
    let server = try TestSocket(listening: true)
    #expect(UnixSocketProbe.isAcceptingConnections(atPath: server.path))
}

@Test("socket órfão sem listen reprova na sonda", .timeLimit(.minutes(1)))
func orphanedSocketFailsProbe() throws {
    // bind sem listen: arquivo existe no disco e ninguém aceita conexão —
    // exatamente o estado depois que o Arena é fechado.
    let orphan = try TestSocket(listening: false)
    #expect(FileManager.default.fileExists(atPath: orphan.path))
    #expect(!UnixSocketProbe.isAcceptingConnections(atPath: orphan.path))
}

@Test("arquivo comum reprova na sonda")
func plainFileFailsProbe() throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("resolux-probe-\(UUID().uuidString.prefix(8)).txt")
    try Data().write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }
    #expect(!UnixSocketProbe.isAcceptingConnections(atPath: url.path))
}

@Test("caminho maior que sun_path reprova sem estourar buffer")
func overlongPathFailsProbe() {
    let long = "/tmp/" + String(repeating: "a", count: 200) + ".sock"
    #expect(!UnixSocketProbe.isAcceptingConnections(atPath: long))
}

// MARK: - Infraestrutura de socket efêmero

private struct SocketFailure: Error, CustomStringConvertible {
    let operation: String
    let code: Int32
    var description: String { "\(operation): \(String(cString: strerror(code)))" }
}

/// Unix socket efêmero, vivo enquanto o teste durar. Caminho curto para caber no
/// `sun_path` (104 bytes) e único por pid para não colidir em execução paralela.
private final class TestSocket {
    let path: String
    private let fd: Int32

    init(listening: Bool) throws {
        var last: SocketFailure?
        for _ in 0 ..< 8 {
            let candidate = "/tmp/rx\(getpid())\(Int.random(in: 0 ..< 1_000_000)).sock"
            try? FileManager.default.removeItem(atPath: candidate)
            do {
                self.fd = try TestSocket.openBound(path: candidate, listening: listening)
                self.path = candidate
                return
            } catch let error as SocketFailure where error.operation == "bind" {
                last = error
                continue
            } catch let error as SocketFailure {
                last = error
                break
            }
        }
        throw last ?? SocketFailure(operation: "bind", code: EADDRINUSE)
    }

    deinit {
        Darwin.close(fd)
        try? FileManager.default.removeItem(atPath: path)
    }

    private static func openBound(path: String, listening: Bool) throws -> Int32 {
        guard let offset = MemoryLayout<sockaddr_un>.offset(of: \.sun_path) else {
            throw SocketFailure(operation: "layout", code: EINVAL)
        }
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw SocketFailure(operation: "socket", code: errno) }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bound: Int32 = path.withCString { source in
            withUnsafeMutablePointer(to: &address) { pointer in
                memcpy(UnsafeMutableRawPointer(pointer) + offset, source, path.utf8.count + 1)
                let length = socklen_t(offset + path.utf8.count + 1)
                return pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { addr in
                    Darwin.bind(fd, addr, length)
                }
            }
        }
        guard bound == 0 else {
            Darwin.close(fd)
            throw SocketFailure(operation: "bind", code: errno)
        }
        if listening, Darwin.listen(fd, 4) != 0 {
            Darwin.close(fd)
            throw SocketFailure(operation: "listen", code: errno)
        }
        return fd
    }
}
