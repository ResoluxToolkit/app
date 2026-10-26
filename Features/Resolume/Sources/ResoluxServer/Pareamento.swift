import Darwin
import Foundation

/// Pareamento por QR (proposta do cliente em `docs/PAREAMENTO.md`): o Mac
/// pede um código rotativo, o celular devolve o código e ganha um token de
/// aparelho. Tudo em memória — reiniciar o daemon desfaz os pareamentos.
actor Pareamento {
    struct Codigo: Sendable, Equatable {
        let valor: String
        let expiraEm: Int
    }

    enum Falha: Error, Equatable {
        case invalido
        case excessoTentativas
    }

    private var codigoAtual: Codigo?
    private var tokens: Set<String> = []
    private var falhas: [String: [Date]] = [:]
    private let duracaoCodigo: TimeInterval
    private let maximoFalhas: Int
    private let janelaFalhas: TimeInterval

    init(
        duracaoCodigo: TimeInterval = 300,
        maximoFalhas: Int = 5,
        janelaFalhas: TimeInterval = 60) {
        self.duracaoCodigo = duracaoCodigo
        self.maximoFalhas = maximoFalhas
        self.janelaFalhas = janelaFalhas
    }

    func codigo(agora: Date = Date()) -> Codigo {
        if let atual = codigoAtual, Double(atual.expiraEm) > agora.timeIntervalSince1970 {
            return atual
        }
        let novo = Codigo(
            valor: Self.aleatorio(bytes: 16),
            expiraEm: Int(agora.addingTimeInterval(duracaoCodigo).timeIntervalSince1970))
        codigoAtual = novo
        return novo
    }

    func parear(codigo: String, cliente: String, agora: Date = Date()) throws -> String {
        var recentes = (falhas[cliente] ?? []).filter {
            agora.timeIntervalSince($0) < janelaFalhas
        }
        falhas[cliente] = recentes
        guard recentes.count < maximoFalhas else { throw Falha.excessoTentativas }

        guard let atual = codigoAtual,
              Double(atual.expiraEm) > agora.timeIntervalSince1970 else {
            codigoAtual = nil
            recentes.append(agora)
            falhas[cliente] = recentes
            throw Falha.invalido
        }
        guard Self.iguaisEmTempoConstante(atual.valor, codigo) else {
            recentes.append(agora)
            falhas[cliente] = recentes
            throw Falha.invalido
        }

        // Uso único: o código morre aqui e o próximo GET gera outro.
        codigoAtual = nil
        falhas[cliente] = []
        let token = Self.aleatorio(bytes: 32)
        tokens.insert(token)
        return token
    }

    func tokenValido(_ token: String?) -> Bool {
        guard let token, !token.isEmpty else { return false }
        return tokens.contains(token)
    }

    func revogar(_ token: String?) {
        guard let token else { return }
        tokens.remove(token)
    }

    static func aleatorio(bytes: Int) -> String {
        var gerador = SystemRandomNumberGenerator()
        var dados = [UInt8]()
        dados.reserveCapacity(bytes)
        for _ in 0..<bytes {
            dados.append(UInt8.random(in: .min ... .max, using: &gerador))
        }
        return Data(dados).base64URL()
    }

    static func iguaisEmTempoConstante(_ lhs: String, _ rhs: String) -> Bool {
        let a = Array(lhs.utf8)
        let b = Array(rhs.utf8)
        var diferenca = a.count ^ b.count
        let limite = max(a.count, b.count)
        for indice in 0..<limite {
            let byteA = indice < a.count ? a[indice] : 0
            let byteB = indice < b.count ? b[indice] : 0
            diferenca |= Int(byteA ^ byteB)
        }
        return diferenca == 0
    }
}

extension Data {
    func base64URL() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

/// Quem é o próprio Mac e o que exige token. O peer TCP pode ser o Vite em
/// loopback; nesse caso o `X-Forwarded-For` (confiado só para peer loopback)
/// diz quem realmente chamou.
enum AcessoDaemon {
    static func texto(_ buffer: [CChar]) -> String {
        String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    static func normalizar(_ endereco: String) -> String {
        var texto = endereco.trimmingCharacters(in: .whitespacesAndNewlines)
        if texto.hasPrefix("["), texto.hasSuffix("]") {
            texto = String(texto.dropFirst().dropLast())
        }
        if let indice = texto.firstIndex(of: "%") {
            texto = String(texto[..<indice])
        }
        let minusculo = texto.lowercased()
        if minusculo.hasPrefix("::ffff:") {
            return String(minusculo.dropFirst(7))
        }
        return minusculo
    }

    static func ehLoopback(_ endereco: String?) -> Bool {
        guard let endereco else { return false }
        let normalizado = normalizar(endereco)
        return normalizado == "127.0.0.1"
            || normalizado == "::1"
            || normalizado == "localhost"
            || normalizado.hasPrefix("127.")
    }

    static func clienteReal(peer: String?, encaminhado: String?) -> String? {
        guard let peer else { return nil }
        let peerNormalizado = normalizar(peer)
        if ehLoopback(peerNormalizado), let encaminhado,
           let primeiro = encaminhado.split(separator: ",").first {
            let texto = primeiro.trimmingCharacters(in: .whitespaces)
            if !texto.isEmpty { return normalizar(texto) }
        }
        return peerNormalizado
    }

    /// IPs desta máquina (loopback e interfaces). O painel aberto pelo
    /// endereço de rede do próprio Mac continua sendo o próprio Mac.
    static func enderecosLocais() -> Set<String> {
        var resultado: Set<String> = ["127.0.0.1", "::1"]
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let primeiro = ifaddr else { return resultado }
        defer { freeifaddrs(ifaddr) }
        var atual: UnsafeMutablePointer<ifaddrs>? = primeiro
        while let ponteiro = atual {
            defer { atual = ponteiro.pointee.ifa_next }
            guard let endereco = ponteiro.pointee.ifa_addr else { continue }
            let familia = endereco.pointee.sa_family
            guard familia == UInt8(AF_INET) || familia == UInt8(AF_INET6) else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(
                endereco,
                socklen_t(endereco.pointee.sa_len),
                &host,
                socklen_t(host.count),
                nil,
                0,
                NI_NUMERICHOST) == 0 else { continue }
            resultado.insert(normalizar(texto(host)))
        }
        return resultado
    }

    static func ehLocal(_ cliente: String?, locais: Set<String> = enderecosLocais()) -> Bool {
        guard let cliente else { return false }
        return locais.contains(normalizar(cliente))
    }

    /// IPv4 de rede, com `en0` (Wi-Fi/Ethernet) na frente. É o endereço que
    /// vai no QR quando o painel foi aberto por `localhost`.
    static func enderecosIPv4DeRede() -> [String] {
        var encontrados: [(nome: String, ip: String)] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let primeiro = ifaddr else { return [] }
        defer { freeifaddrs(ifaddr) }
        var atual: UnsafeMutablePointer<ifaddrs>? = primeiro
        while let ponteiro = atual {
            defer { atual = ponteiro.pointee.ifa_next }
            guard let endereco = ponteiro.pointee.ifa_addr,
                  endereco.pointee.sa_family == UInt8(AF_INET) else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(
                endereco,
                socklen_t(endereco.pointee.sa_len),
                &host,
                socklen_t(host.count),
                nil,
                0,
                NI_NUMERICHOST) == 0 else { continue }
            let ip = texto(host)
            guard !ehLoopback(ip) else { continue }
            let nome: String = if let ponteiroNome = ponteiro.pointee.ifa_name {
                String(cString: ponteiroNome)
            } else {
                ""
            }
            encontrados.append((nome, ip))
        }
        var vistos: Set<String> = []
        let ordenados = encontrados.filter { $0.nome == "en0" }
            + encontrados.filter { $0.nome != "en0" }
        return ordenados.compactMap { item in
            guard vistos.insert(item.ip).inserted else { return nil }
            return item.ip
        }
    }

    static func decomporHost(_ host: String) -> (nome: String?, porta: String?) {
        if host.hasPrefix("[") {
            guard let fim = host.firstIndex(of: "]") else { return (nil, nil) }
            let nome = String(host[host.index(after: host.startIndex)..<fim])
            let resto = host[host.index(after: fim)...]
            let porta = resto.hasPrefix(":") ? String(resto.dropFirst()) : nil
            return (nome.isEmpty ? nil : nome, porta)
        }
        let partes = host.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard let primeira = partes.first, !primeira.isEmpty else { return (nil, nil) }
        let porta = partes.count == 2 && !partes[1].isEmpty ? String(partes[1]) : nil
        return (String(primeira), porta)
    }

    /// `base` do QR: preserva o host que o painel usou; se ele é loopback,
    /// troca pelo IP de rede desta máquina mantendo a porta (Vite ou daemon).
    static func baseDeRede(
        host: String?,
        locais: [String] = enderecosIPv4DeRede()) -> String? {
        guard let host, !host.isEmpty else { return nil }
        let (nome, porta) = decomporHost(host)
        guard let nome else { return nil }
        if ehLoopback(nome) || nome.lowercased() == "localhost" {
            guard let ip = locais.first else { return nil }
            return porta.map { "http://\(ip):\($0)" } ?? "http://\(ip)"
        }
        return "http://\(host)"
    }

    static func tokenDoPedido(_ pedido: PedidoHttp) -> String? {
        if let autorizacao = pedido.cabecalhos["authorization"] {
            let partes = autorizacao.split(
                separator: " ",
                maxSplits: 1,
                omittingEmptySubsequences: true)
            if partes.count == 2, partes[0].lowercased() == "bearer" {
                let token = String(partes[1]).trimmingCharacters(in: .whitespaces)
                if !token.isEmpty { return token }
            }
        }
        if let token = pedido.consulta["token"], !token.isEmpty { return token }
        return nil
    }

    /// Fora do Mac, só `GET /health`, o bundle estático e o POST de
    /// pareamento passam sem token. O GET de pareamento é tratado antes
    /// (403) e não entra aqui.
    static func exigeToken(_ pedido: PedidoHttp) -> Bool {
        let rota = pedido.rota
        if rota == "/api/v1/health" { return false }
        if !rota.hasPrefix("/api/") && rota != "/monitor" && !rota.hasPrefix("/monitor/") {
            return false
        }
        return true
    }
}
