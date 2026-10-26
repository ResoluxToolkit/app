import Foundation
import AppKit
import Network
import WebKit
import Resolume

/// Daemon da Resolux API v1. É o único processo do cliente web: escuta em
/// `127.0.0.1:1980` por default (`RESOLUX_BIND=0.0.0.0` abre todas as
/// interfaces, ex. Tailscale), fala HTTP+WS com o front e mantém para si o
/// contato read-only com o REST do Arena. Sem MCP, sem modelo, sem escrita
/// nesta build — honestidade de estado na cara da API.
    @main
    struct ResoluxServerMain {
        static func main() async {
            let persistencia = PersistenciaDisco()
            let restaurada = try? await persistencia.preparar()
            let estado = EstadoSessao(sessao: restaurada ?? SessaoV1())
            let gateway = ArenaGateway()
            let monitor = MonitorHub(provedor: { try await gateway.composition() })
            let sistemaMonitor = Resolume.MonitorHub()
            let sistemaHTTP = Resolume.MonitorHTTPServer(hub: sistemaMonitor)
            let front = FrontendEstatico.localizar()
            let conversa = ConversaHub()
            await persistencia.definirPublicador { corpo in
                await conversa.publicar(corpo)
            }
            let motor = MotorChat()
            let pareamento = Pareamento()

        let bandeja = BandejaResolux(urlPublica: urlFrontendTray())
        let aplicacao = NSApplication.shared
        aplicacao.setActivationPolicy(.accessory)
        aplicacao.delegate = bandeja
        bandeja.instalar()

        let parametros = NWParameters.tcp
        let host = hostEscuta() ?? .any
        parametros.requiredLocalEndpoint = NWEndpoint.hostPort(
            host: .ipv4(host),
            port: 1980)
        let listener = try! NWListener(using: parametros)
        bandeja.vincular(listener: listener)
        listener.stateUpdateHandler = { estado in
            if case .failed(let erro) = estado {
                Task { @MainActor in bandeja.marcarFalha() }
                FileHandle.standardError.write(
                    Data("[ResoluxServer] falha ao escutar na 1980: \(erro)\n".utf8))
                exit(1)
            } else if case .ready = estado {
                Task { @MainActor in bandeja.marcarRodando() }
            }
        }
        listener.newConnectionHandler = { conexao in
            Task {
                await atender(
                    conexao,
                    estado: estado,
                    gateway: gateway,
                    monitor: monitor,
                    sistema: sistemaHTTP,
                    conversa: conversa,
                    motor: motor,
                    front: front,
                    persistencia: persistencia,
                    pareamento: pareamento)
            }
        }
        listener.start(queue: .global(qos: .userInitiated))
        aplicacao.run()
    }

    /// Host de escuta. Default `127.0.0.1`; `RESOLUX_BIND=0.0.0.0` devolve
    /// `nil` e o listener abre todas as interfaces (LAN, Tailscale).
    static func hostEscuta(
        ambiente: [String: String] = ProcessInfo.processInfo.environment) -> IPv4Address? {
        let bruto = ambiente["RESOLUX_BIND"] ?? ""
        if bruto == "0.0.0.0" || bruto == "*" { return nil }
        return IPv4Address(bruto.isEmpty ? "127.0.0.1" : bruto) ?? .loopback
    }

    // MARK: - Ciclo de conexão

    private static func atender(
        _ conexao: NWConnection,
        estado: EstadoSessao,
        gateway: ArenaGateway,
        monitor: MonitorHub,
        sistema: Resolume.MonitorHTTPServer,
        conversa: ConversaHub,
        motor: MotorChat,
        front: FrontendEstatico?,
        persistencia: PersistenciaDisco,
        pareamento: Pareamento) async {
        conexao.start(queue: .global(qos: .userInitiated))
        let peer = enderecoRemoto(conexao)
        var emWebSocket = false
        var buffer = Data()
        var decodificador = WsDecodificador()
        var assinatura: UUID?
        var assinaturaConversa: UUID?
        var idMonitor: String?

        while true {
            let dados: Data
            do {
                dados = try await receber(conexao)
            } catch {
                await despedir(
                    conexao,
                    emWebSocket: emWebSocket,
                    assinatura: assinatura,
                    monitor: monitor,
                    idMonitor: idMonitor,
                    conversa: conversa,
                    assinaturaConversa: assinaturaConversa)
                return
            }

            if dados.isEmpty {
                await despedir(
                    conexao,
                    emWebSocket: emWebSocket,
                    assinatura: assinatura,
                    monitor: monitor,
                    idMonitor: idMonitor,
                    conversa: conversa,
                    assinaturaConversa: assinaturaConversa)
                return
            }

            buffer.append(dados)

            if !emWebSocket {
                guard let pedido = PedidoHttp.parse(buffer) else { continue }
                let cliente = AcessoDaemon.clienteReal(
                    peer: peer,
                    encaminhado: pedido.cabecalhos["x-forwarded-for"])
                let local = AcessoDaemon.ehLocal(cliente)
                let tokenValido = await pareamento.tokenValido(
                    AcessoDaemon.tokenDoPedido(pedido))
                let autorizado = local || tokenValido
                if pedido.rota == "/monitor" || pedido.rota.hasPrefix("/monitor/processes/") {
                    guard autorizado else {
                        await enviar(conexao, RespostaHttp.erro(
                            codigo: "unauthorized",
                            mensagem: "Pareie este aparelho lendo o QR do painel.",
                            status: 401).serializar())
                        await despedir(
                            conexao,
                            emWebSocket: false,
                            assinatura: nil,
                            monitor: monitor,
                            idMonitor: nil,
                            conversa: conversa,
                            assinaturaConversa: nil)
                        return
                    }
                    await sistema.atender(conexao, pedido: buffer, iniciar: false)
                    return
                }
                if pedido.rota == "/api/v1/ws" {
                    guard let chave = pedido.cabecalhos["sec-websocket-key"],
                          origemAceita(pedido.cabecalhos["origin"]) else {
                        let resposta = RespostaHttp.erro(
                            codigo: "invalid_message",
                            mensagem: "Handshake WebSocket recusado",
                            status: 400)
                        await enviar(conexao, resposta.serializar())
                        await despedir(
                            conexao,
                            emWebSocket: false,
                            assinatura: nil,
                            monitor: monitor,
                            idMonitor: nil,
                            conversa: conversa,
                            assinaturaConversa: nil)
                        return
                    }

                    guard autorizado else {
                        let resposta = RespostaHttp.erro(
                            codigo: "unauthorized",
                            mensagem: "Pareie este aparelho lendo o QR do painel.",
                            status: 401)
                        await enviar(conexao, resposta.serializar())
                        await despedir(
                            conexao,
                            emWebSocket: false,
                            assinatura: nil,
                            monitor: monitor,
                            idMonitor: nil,
                            conversa: conversa,
                            assinaturaConversa: nil)
                        return
                    }

                    let resposta = "HTTP/1.1 101 Switching Protocols\r\n" +
                        "Upgrade: websocket\r\n" +
                        "Connection: Upgrade\r\n" +
                        "Sec-WebSocket-Accept: \(WsHandshake.aceitar(chave: chave))\r\n" +
                        "\r\n"
                    await enviar(conexao, Data(resposta.utf8))
                    emWebSocket = true
                    buffer.removeAll()
                    continue
                }

                let resposta = await responderHttp(
                    pedido,
                    estado: estado,
                    gateway: gateway,
                    motor: motor,
                    front: front,
                    persistencia: persistencia,
                    pareamento: pareamento,
                    local: local,
                    autorizado: autorizado,
                    cliente: cliente)
                await enviar(
                    conexao,
                    resposta.serializar(semCorpo: pedido.metodo == "HEAD"))
                await despedir(conexao, emWebSocket: false)
                return
            }

            for mensagem in decodificador.alimentar(buffer) {
                buffer.removeAll()
                switch mensagem.opcode {
                case 1:
                    let tratou = await tratar(
                        mensagem.payload,
                        idMonitor: &idMonitor,
                        assinatura: &assinatura,
                        assinaturaConversa: &assinaturaConversa,
                        conexao: conexao,
                        estado: estado,
                        monitor: monitor,
                        conversa: conversa,
                        motor: motor,
                        persistencia: persistencia)
                    if !tratou {
                        await despedir(
                            conexao,
                            emWebSocket: true,
                            assinatura: assinatura,
                            monitor: monitor,
                            idMonitor: idMonitor,
                            conversa: conversa,
                            assinaturaConversa: assinaturaConversa)
                        return
                    }
                case 8:
                    await despedir(
                        conexao,
                        emWebSocket: true,
                        assinatura: assinatura,
                        monitor: monitor,
                        idMonitor: idMonitor,
                        conversa: conversa,
                        assinaturaConversa: assinaturaConversa)
                    return
                case 9:
                    await enviar(conexao, WsDecodificador.pong(payload: mensagem.payload))
                default:
                    break
                }
            }
        }
    }

    /// Frontend mostrado pelo menu de barra. `RESOLUX_PUBLIC_URL` permite
    /// apontar para o endereço público (Tailscale/proxy), sem mudar o bind.
    static let urlPublicaPadrao = URL(string: "https://mac.tail17794.ts.net:8443")!

    static func urlFrontendTray(
        ambiente: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        let publico = ambiente["RESOLUX_PUBLIC_URL"] ?? ""
        if !publico.isEmpty, let url = URL(string: publico) {
            return url
        }
        return urlPublicaPadrao
    }

    @MainActor
    private final class BandejaResolux: NSObject, NSApplicationDelegate {
        private let urlPublica: URL
        private var listener: NWListener?
        private var statusItem: NSStatusItem?
        private var rotuloEstado: NSMenuItem?
        private var janelaFrontend: NSWindow?
        private var webviewFrontend: WKWebView?

        init(urlPublica: URL) {
            self.urlPublica = urlPublica
        }

        func vincular(listener: NWListener) {
            self.listener = listener
        }

        func instalar() {
            let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            statusItem.button?.title = "Resolux"
            if let imagem = NSImage(
                systemSymbolName: "rectangle.on.rectangle",
                accessibilityDescription: "Resolux") {
                statusItem.button?.image = imagem
            }

            let menu = NSMenu()
            let rotulo = NSMenuItem(title: "Iniciando — \(urlPublica.absoluteString)", action: nil, keyEquivalent: "")
            let abrir = NSMenuItem(title: "Abrir Webview", action: #selector(abrirFrontend), keyEquivalent: "")
            abrir.target = self
            let sair = NSMenuItem(title: "Sair do Resolux", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

            menu.addItem(rotulo)
            menu.addItem(.separator())
            menu.addItem(abrir)
            menu.addItem(sair)
            statusItem.menu = menu

            self.statusItem = statusItem
            rotuloEstado = rotulo
        }

        func marcarRodando() {
            rotuloEstado?.title = "Rodando — \(urlPublica.absoluteString)"
        }

        func marcarFalha() {
            rotuloEstado?.title = "Falha na porta 1980"
        }

        @objc private func abrirFrontend() {
            if let janela = janelaFrontend {
                janela.makeKeyAndOrderFront(nil)
                NSApplication.shared.activate(ignoringOtherApps: true)
                return
            }

            let webview = WKWebView(frame: .zero)
            webview.autoresizingMask = [.width, .height]
            webview.load(URLRequest(url: urlPublica))

            let janela = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1180, height: 760),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false)
            janela.title = "Resolux"
            janela.contentView = webview
            janela.isReleasedWhenClosed = false
            janela.center()
            janela.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)

            janelaFrontend = janela
            webviewFrontend = webview
        }
    }

    // MARK: - WebSocket

    private static func tratar(
        _ payload: Data,
        idMonitor: inout String?,
        assinatura: inout UUID?,
        assinaturaConversa: inout UUID?,
        conexao: NWConnection,
        estado: EstadoSessao,
        monitor: MonitorHub,
        conversa: ConversaHub,
        motor: MotorChat,
        persistencia: PersistenciaDisco) async -> Bool {
        guard let dados = try? JSONDecoder().decode([String: MCPValue].self, from: payload),
              case .string(let tipo) = dados["type"] ?? .string("") else {
            await enviarErro(conexao, codigo: "invalid_message", id: nil)
            return true
        }

        let id = dados["id"]?.stringValue

        switch tipo {
        case "monitor.subscribe":
            if let anterior = assinatura, let idAnterior = idMonitor {
                await monitor.cancelar(anterior)
                _ = idAnterior
            }
            let identificador = id ?? "mon-1"
            let identificadorSeguro = identificador
            let entrega: MonitorHub.Entregador = { evento in
                await enviarEventoMonitor(evento, id: identificadorSeguro, conexao: conexao)
            }
            assinatura = await monitor.assinar(entrega)
            idMonitor = identificador
        case "conversa.subscribe":
            if let anterior = assinaturaConversa {
                await conversa.cancelar(anterior)
            }
            let identificador = id ?? "conv-1"
            let identificadorSeguro = identificador
            let entrega: ConversaHub.Entregador = { corpo in
                await enviar(
                    conexao,
                    WsDecodificador.texto(mensagemConversa(id: identificadorSeguro, corpo: corpo)))
            }
            assinaturaConversa = await conversa.assinar(entrega)
            // Snapshot imediato: o assinante já nasce com o estado do disco.
            let corpo = await persistencia.conversaJson()
            await enviar(
                conexao,
                WsDecodificador.texto(mensagemConversa(id: identificadorSeguro, corpo: corpo)))
        case "session.update":
            let patch: [String: MCPValue] = switch dados["payload"] {
            case .object(let objeto): objeto
            default: [:]
            }
            do {
                _ = try await estado.aplicar(patch)
                let sessao = await estado.json()
                await enviar(
                    conexao,
                    WsDecodificador.texto(
                        #"{"type":"session.updated","id":\#(identificadorJson(id)),"payload":\#(String(decoding: sessao, as: UTF8.self))}"#))
            } catch let erro as RecusaSessao {
                await enviar(conexao, WsDecodificador.texto(descricaoErroSessao(erro, id: id)))
            } catch {
                await enviarErro(conexao, codigo: "backend_unavailable", id: id)
            }
        case "chat.send":
            let texto: String? = switch dados["payload"] {
            case .object(let objeto): objeto["text"]?.stringValue
            default: nil
            }
            guard let texto, !texto.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                await enviarErro(
                    conexao,
                    codigo: "invalid_message",
                    id: id,
                    mensagem: "chat.send precisa de payload.text.")
                return true
            }
            await enviar(
                conexao,
                WsDecodificador.texto(
                    #"{"type":"chat.started","id":\#(identificadorJson(id))}"#))
            await persistencia.registrarEntrada(papel: "usuario", texto: texto)
            do {
                let resposta = try await motor.responder(texto, sessao: await estado.snapshot())
                await estado.definirFerramentas(await motor.totalFerramentas())
                await persistencia.registrarEntrada(papel: "agente", texto: resposta)
                await enviar(conexao, WsDecodificador.texto(mensagemResultadoChat(resposta, id: id)))
            } catch let falha as MotorChat.Falha {
                await estado.definirFerramentas(await motor.totalFerramentas())
                await enviar(conexao, WsDecodificador.texto(descricaoErroChat(falha, id: id)))
            } catch {
                await enviarErro(conexao, codigo: "backend_unavailable", id: id, mensagem: "O turno de chat falhou.")
            }
        case "ping":
            await enviar(
                conexao,
                WsDecodificador.texto(
                    #"{"type":"pong","id":\#(identificadorJson(id))}"#))
        default:
            await enviarErro(conexao, codigo: "invalid_message", id: id)
        }
        return true
    }

    private static func enviarEventoMonitor(
        _ evento: MonitorHub.Evento,
        id: String,
        conexao: NWConnection) async {
        let idJson = identificadorJson(id)
        let mensagem: String
        switch evento {
        case .update(let corpo):
            mensagem =
                #"{"type":"monitor.update","id":\#(idJson),"payload":{"composition":\#(String(decoding: corpo, as: UTF8.self))}}"#
        case .erro(let codigo, let texto):
            mensagem =
                #"{"type":"monitor.error","id":\#(idJson),"payload":{"code":"\#(codigo)","message":"\#(texto)"}}"#
        }
        await enviar(conexao, WsDecodificador.texto(mensagem))
    }

    private static func mensagemConversa(id: String, corpo: Data) -> String {
        #"{"type":"conversa.update","id":\#(identificadorJson(id)),"payload":\#(String(decoding: corpo, as: UTF8.self))}"#
    }

    private static func mensagemResultadoChat(_ resposta: String, id: String?) -> String {
        let payload: [String: MCPValue] = [
            "message": .object([
                "role": .string("assistant"),
                "content": .string(resposta),
            ]),
        ]
        let corpo = (try? JSONEncoder().encode(payload)) ?? Data("{}".utf8)
        return #"{"type":"chat.result","id":\#(identificadorJson(id)),"payload":\#(String(decoding: corpo, as: UTF8.self))}"#
    }

    private static func descricaoErroChat(_ falha: MotorChat.Falha, id: String?) -> String {
        let codigo: String
        let mensagem: String
        switch falha {
        case .turnoOcupado:
            codigo = "busy"
            mensagem = "Já existe um turno de chat em andamento."
        case .backendIndisponivel(let texto):
            codigo = "backend_unavailable"
            mensagem = texto
        case .tokenAusente(let texto):
            codigo = "backend_unavailable"
            mensagem = texto
        case .arenaMcpIndisponivel(let texto):
            codigo = "arena_unavailable"
            mensagem = texto
        case .modeloFalhou(let texto):
            codigo = "backend_unavailable"
            mensagem = "O backend de chat falhou: \(texto)"
        }
        return
            #"{"type":"chat.error","id":\#(identificadorJson(id)),"payload":{"code":"\#(codigo)","message":"\#(mensagem)"}}"#
    }

    private static func enviarErro(
        _ conexao: NWConnection,
        codigo: String,
        id: String?,
        mensagem: String = "Mensagem fora do contrato v1.") async {
        await enviar(
            conexao,
            WsDecodificador.texto(
                #"{"type":"error","id":\#(identificadorJson(id)),"payload":{"code":"\#(codigo)","message":"\#(mensagem)"}}"#))
    }

    private static func descricaoErroSessao(_ erro: RecusaSessao, id: String?) -> String {
        let codigo: String
        let mensagem: String
        switch erro {
        case .campoDesconhecido(let campo):
            codigo = "campo_desconhecido"
            mensagem = "Campo não aceito em session.update: \(campo)"
        case .valorInvalido(let campo, let valor):
            codigo = "valor_invalido"
            mensagem = "Valor inválido em \(campo): \(valor)"
        case .corpoInvalido:
            codigo = "corpo_invalido"
            mensagem = "Payload de session.update inválido."
        }
        return
            #"{"type":"error","id":\#(identificadorJson(id)),"payload":{"code":"\#(codigo)","message":"\#(mensagem)"}}"#
    }

    private static func identificadorJson(_ id: String?) -> String {
        guard let id else { return "" }
        guard let dados = try? JSONEncoder().encode(id) else { return "" }
        return String(decoding: dados, as: UTF8.self)
    }

    // Aceita origens locais e da LAN: loopback, faixas privadas (incluindo o
    // CGNAT do Tailscale) e nomes de máquina sem ponto ("mac", "mac.local").
    // Origem externa sempre tem ponto no host, então site de fora continua
    // de fora — o celular/PWA entra porque fala com o Vite na mesma LAN.
    static func origemAceita(_ origem: String?) -> Bool {
        guard let origem else { return true }
        if origem == "null" { return true }
        guard let url = URL(string: origem), let host = url.host else { return false }
        return hostOrigemAceito(host.lowercased())
    }

    static func hostOrigemAceito(_ host: String) -> Bool {
        if host == "localhost" || host == "::1" { return true }
        if !host.contains(".") || host.hasSuffix(".local") { return true }
        return faixaPrivadaAceita(host)
    }

    /// Peer TCP da conexão aceita. É por aqui que o daemon sabe se o pedido
    /// veio do próprio Mac ou de outro aparelho da rede.
    static func enderecoRemoto(_ conexao: NWConnection) -> String? {
        guard case let .hostPort(host, _) = conexao.endpoint else { return nil }
        switch host {
        case .ipv4(let endereco): return "\(endereco)"
        case .ipv6(let endereco): return "\(endereco)"
        case .name(let nome, _): return nome
        @unknown default: return nil
        }
    }

    private static func faixaPrivadaAceita(_ host: String) -> Bool {
        let octetos = host.split(separator: ".").compactMap { UInt8($0) }
        guard octetos.count == 4 else { return false }
        let (primeiro, segundo) = (octetos[0], octetos[1])
        if primeiro == 127 { return true }
        if primeiro == 10 { return true }
        if primeiro == 192 && segundo == 168 { return true }
        if primeiro == 172 && (16...31).contains(segundo) { return true }
        if primeiro == 100 && (64...127).contains(segundo) { return true }
        return false
    }

    private static func despedir(
        _ conexao: NWConnection,
        emWebSocket: Bool = false,
        assinatura: UUID? = nil,
        monitor: MonitorHub? = nil,
        idMonitor: String? = nil,
        conversa: ConversaHub? = nil,
        assinaturaConversa: UUID? = nil) async {
        if let assinatura {
            await monitor?.cancelar(assinatura)
        }
        if let assinaturaConversa {
            await conversa?.cancelar(assinaturaConversa)
        }
        if idMonitor != nil {
            // nada a fazer: o identificador só existe para o log do cliente
        }
        if emWebSocket {
            await enviar(conexao, WsDecodificador.fechar())
        }
        conexao.cancel()
    }

    // MARK: - HTTP

    static func responderHttp(
        _ pedido: PedidoHttp,
        estado: EstadoSessao,
        gateway: ArenaGateway,
        motor: MotorChat,
        front: FrontendEstatico?,
        persistencia: PersistenciaDisco,
        pareamento: Pareamento,
        local: Bool,
        autorizado: Bool,
        cliente: String?) async -> RespostaHttp {
        if pedido.rota == "/api/v1/pareamento" {
            return await responderPareamento(
                pedido,
                pareamento: pareamento,
                local: local,
                cliente: cliente)
        }
        if !autorizado && AcessoDaemon.exigeToken(pedido) {
            return RespostaHttp.erro(
                codigo: "unauthorized",
                mensagem: "Pareie este aparelho lendo o QR do painel.",
                status: 401)
        }
        switch pedido.rota {
        case "/api/v1/health":
            return .json(Data(#"{"protocol":"resolux-api/1","status":"online"}"#.utf8))
        case "/api/v1/session":
            return await responderSessao(pedido, estado: estado, persistencia: persistencia)
        case "/api/v1/tools":
            let lista = await motor.listaFerramentas()
            guard !lista.isEmpty else {
                return .json(Data(#"{"tools":[]}"#.utf8))
            }
            let entradas: [MCPValue] = lista.map { entrada in
                var objeto: [String: MCPValue] = ["name": .string(entrada["name"] ?? "")]
                if let descricao = entrada["description"] {
                    objeto["description"] = .string(descricao)
                }
                return .object(objeto)
            }
            let corpo: [String: MCPValue] = ["tools": .array(entradas)]
            let dados = (try? JSONEncoder().encode(corpo)) ?? Data(#"{"tools":[]}"#.utf8)
            return .json(dados)
        case "/api/v1/conversa":
            return await responderConversa(pedido, persistencia: persistencia)
        default:
            if pedido.rota.hasPrefix("/api/v1/arena") {
                return await responderArena(pedido, gateway: gateway)
            }
            if let front, !pedido.rota.hasPrefix("/api/") {
                return front.resposta(pedido)
            }
            return RespostaHttp.erro(
                codigo: "not_found",
                mensagem: "Rota fora do contrato v1.",
                status: 404)
        }
    }

    static func responderPareamento(
        _ pedido: PedidoHttp,
        pareamento: Pareamento,
        local: Bool,
        cliente: String?) async -> RespostaHttp {
        switch pedido.metodo {
        case "GET":
            guard local else {
                return RespostaHttp.erro(
                    codigo: "forbidden",
                    mensagem: "O código de pareamento só é gerado no Mac.",
                    status: 403)
            }
            let codigo = await pareamento.codigo()
            var corpo: [String: MCPValue] = [
                "codigo": .string(codigo.valor),
                "expiraEm": .int(codigo.expiraEm),
            ]
            if let base = AcessoDaemon.baseDeRede(host: pedido.cabecalhos["host"]) {
                corpo["base"] = .string(base)
            }
            let dados = (try? JSONEncoder().encode(corpo))
                ?? Data(#"{"codigo":"","expiraEm":0}"#.utf8)
            return .json(dados)
        case "POST":
            guard let corpo = try? JSONDecoder().decode(
                [String: MCPValue].self,
                from: pedido.corpo),
                case .string(let codigo) = corpo["codigo"] ?? .null,
                !codigo.isEmpty else {
                return RespostaHttp.erro(
                    codigo: "corpo_invalido",
                    mensagem: "Payload de POST /pareamento inválido.",
                    status: 400)
            }
            do {
                let token = try await pareamento.parear(
                    codigo: codigo,
                    cliente: cliente ?? "desconhecido")
                let dados = (try? JSONEncoder().encode(["token": MCPValue.string(token)]))
                    ?? Data(#"{"token":""}"#.utf8)
                return .json(dados)
            } catch Pareamento.Falha.excessoTentativas {
                return RespostaHttp.erro(
                    codigo: "rate_limited",
                    mensagem: "Muitas tentativas de pareamento. Espere um minuto.",
                    status: 429)
            } catch {
                return RespostaHttp.erro(
                    codigo: "pairing_invalid",
                    mensagem: "Código vencido ou inválido.",
                    status: 401)
            }
        default:
            return RespostaHttp.erro(
                codigo: "method_not_allowed",
                mensagem: "Apenas GET e POST.",
                status: 405)
        }
    }

    private static func responderSessao(
        _ pedido: PedidoHttp,
        estado: EstadoSessao,
        persistencia: PersistenciaDisco) async -> RespostaHttp {
        if pedido.metodo == "GET" {
            return .json(await estado.json())
        }
        if pedido.metodo == "PATCH" {
            guard let patch = try? JSONDecoder().decode([String: MCPValue].self, from: pedido.corpo) else {
                return RespostaHttp.erro(
                    codigo: "corpo_invalido",
                    mensagem: "Payload de PATCH /session inválido.",
                    status: 400)
            }
            do {
                _ = try await estado.aplicar(patch)
                await persistencia.salvarSessao(await estado.snapshot())
                return .json(await estado.json())
            } catch let erro as RecusaSessao {
                switch erro {
                case .campoDesconhecido(let campo):
                    return RespostaHttp.erro(
                        codigo: "campo_desconhecido",
                        mensagem: "Campo não aceito em PATCH /session: \(campo)",
                        status: 400)
                case .valorInvalido(let campo, let valor):
                    return RespostaHttp.erro(
                        codigo: "valor_invalido",
                        mensagem: "Valor inválido em \(campo): \(valor)",
                        status: 400)
                case .corpoInvalido:
                    return RespostaHttp.erro(
                        codigo: "corpo_invalido",
                        mensagem: "Payload de PATCH /session inválido.",
                        status: 400)
                }
            } catch {
                return RespostaHttp.erro(
                    codigo: "backend_unavailable",
                    mensagem: "Não foi possível aplicar o PATCH.",
                    status: 500)
            }
        }
        return RespostaHttp.erro(
            codigo: "method_not_allowed",
            mensagem: "Apenas GET e PATCH.",
            status: 405)
    }

    private static func responderConversa(
        _ pedido: PedidoHttp,
        persistencia: PersistenciaDisco) async -> RespostaHttp {
        switch pedido.metodo {
        case "GET":
            return .json(await persistencia.conversaJson())
        case "DELETE":
            await persistencia.limparConversa()
            return .json(Data(#"{"turnos":[]}"#.utf8))
        default:
            return RespostaHttp.erro(
                codigo: "method_not_allowed",
                mensagem: "Apenas GET e DELETE.",
                status: 405)
        }
    }

    private static func responderArena(
        _ pedido: PedidoHttp,
        gateway: ArenaGateway) async -> RespostaHttp {
        guard pedido.metodo == "GET" || pedido.metodo == "HEAD" else {
            return RespostaHttp.erro(
                codigo: "method_not_allowed",
                mensagem: "O proxy do Arena é read-only.",
                status: 405)
        }
        var caminho = String(pedido.rota.dropFirst("/api/v1/arena".count))
        if caminho.hasPrefix("/api/v1") {
            caminho = String(caminho.dropFirst("/api/v1".count))
        }
        do {
            let resposta = try await gateway.requisitar(
                metodo: pedido.metodo,
                caminho: caminho)
            let contentType = resposta.contentType ?? "application/octet-stream"
            return RespostaHttp(
                status: resposta.status,
                contentType: contentType,
                corpo: resposta.corpo)
        } catch {
            return RespostaHttp.erro(
                codigo: "arena_unavailable",
                mensagem: "Arena REST unavailable",
                status: 502)
        }
    }

    // MARK: - Transporte

    private static func receber(_ conexao: NWConnection) async throws -> Data {
        try await withCheckedThrowingContinuation { continuacao in
            conexao.receive(
                minimumIncompleteLength: 1,
                maximumLength: 65536) { dados, _, completo, erro in
                if let erro {
                    continuacao.resume(throwing: erro)
                } else if let dados, !dados.isEmpty {
                    continuacao.resume(returning: dados)
                } else {
                    _ = completo
                    continuacao.resume(returning: Data())
                }
            }
        }
    }

    private static func enviar(_ conexao: NWConnection, _ dados: Data) async {
        await withCheckedContinuation { continuacao in
            conexao.send(content: dados, completion: .contentProcessed { _ in
                continuacao.resume()
            })
        }
    }
}
