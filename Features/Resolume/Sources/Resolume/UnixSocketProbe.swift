import Darwin
import Foundation

/// Sonda de disponibilidade para unix sockets de app desktop.
///
/// Presença do arquivo `.sock` no disco não prova nada: o socket continua lá
/// depois que o app fecha. Só um `connect()` aceito prova que algo atende.
public enum UnixSocketProbe {
    public static func isAcceptingConnections(atPath path: String) -> Bool {
        guard
            let pathOffset = MemoryLayout<sockaddr_un>.offset(of: \.sun_path),
            path.utf8.count + 1 <= MemoryLayout.size(ofValue: sockaddr_un().sun_path)
        else { return false }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { Darwin.close(fd) }
        // Non-blocking para nunca travar a UI num socket órfão ou com backlog cheio.
        _ = Darwin.fcntl(fd, F_SETFL, Darwin.fcntl(fd, F_GETFL, 0) | O_NONBLOCK)
        let outcome: Int32 = path.withCString { source in
            withUnsafeMutablePointer(to: &address) { pointer in
                memcpy(UnsafeMutableRawPointer(pointer) + pathOffset, source, path.utf8.count + 1)
                let length = socklen_t(pathOffset + path.utf8.count + 1)
                return pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                    Darwin.connect(fd, socketAddress, length)
                }
            }
        }
        if outcome == 0 { return true }
        // EINPROGRESS/EAGAIN com non-blocking significa que o backlog aceitou.
        return errno == EINPROGRESS || errno == EAGAIN
    }
}
