import Foundation
import Network
import Resolume

/// Daemon da Resolux API v1. É o único processo do cliente web: escuta em
/// `127.0.0.1:1980`, fala HTTP+WS com o front e mantém para si o contato
/// read-only com o REST do Arena. Sem MCP, sem modelo, sem escrita nesta
/// build — honestidade de estado na cara da API.
@main
struct ResoluxServerMain {
    static func main() async {
        let estado = EstadoSessao()
        let gateway = ArenaGateway()
        let monitor = MonitorHub(provedor: { try await gateway.composition() })

        let parametros = NWParameters.tcp
        parametros.requiredLocalEndpoint = NWEndpoint.hostPort(
            host: .ipv4(.loopback),
            port: 1980)
        let listener = try! NWListener(using: parametros)
        listener.newConnectionHandler = { conexao in
            Task {
                await atender(
                    conexao,
                    estado: estado,
                    gateway: gateway,
                    monitor: monitor)
            }
        }
        listener.start(queue: .global(qos: .userInitiated))
        await manterAcordado()
    }

    // MARK: - Ciclo de conexão

    private static func atender(
        _ conexao: NWConnection,
        estado: EstadoSessao,
        gateway: ArenaGateway,
        monitor: MonitorHub) async {
        var emWebSocket = false
        var buffer = Data()
        var decodificador = WsDecodificador()
        var assinatura: UUID?
        var idMonitor: String?

        while true {
            let dados: Data
            do {
                dados = try await receber(conexao)
            } catch {
                await despedir(
                    conexao,
                    assinatura: assinatura,
                    monitor: monitor,
                    idMonitor: idMonitor)
                return
            }

            if dados.isEmpty {
                await despedir(
                    conexao,
                    assinatura: assinatura,
                    monitor: monitor,
                    idMonitor: idMonitor)
                return
            }

            buffer.append(dados)

            if !emWebSocket {
                guard let pedido = PedidoHttp.parse(buffer) else { continue }
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
                            assinatura: nil,
                            monitor: monitor,
                            idMonitor: nil)
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

                let resposta = await responderHttp(pedido, estado: estado, gateway: gateway)
                await enviar(
                    conexao,
                    resposta.serializar(semCorpo: pedido.metodo == "HEAD"))
                await despedir(conexao)
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
                        conexao: conexao,
                        estado: estado,
                        monitor: monitor)
                    if !tratou {
                        await despedir(
                            conexao,
                            assinatura: assinatura,
                            monitor: monitor,
                            idMonitor: idMonitor)
                        return
                    }
                case 8:
                    await despedir(
                        conexao,
                        assinatura: assinatura,
                        monitor: monitor,
                        idMonitor: idMonitor)
                    return
                case 9:
                    await enviar(conexao, WsDecodificador.pong(payload: mensagem.payload))
                default:
                    break
                }
            }
        }
    }

    private static func manterAcordado() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 10_000_000_000)
        }
    }

    // MARK: - WebSocket

    private static func tratar(
        _ payload: Data,
        idMonitor: inout String?,
        assinatura: inout UUID?,
        conexao: NWConnection,
        estado: EstadoSessao,
        monitor: MonitorHub) async -> Bool {
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
                        #"{"type":"session.updated","id":"\#(identificadorJson(id))","payload":\#(String(decoding: sessao, as: UTF8.self))}"#))
            } catch let erro as RecusaSessao {
                await enviar(conexao, WsDecodificador.texto(descricaoErroSessao(erro, id: id)))
            } catch {
                await enviarErro(conexao, codigo: "backend_unavailable", id: id)
            }
        case "chat.send":
            await enviarErro(
                conexao,
                codigo: "not_implemented",
                id: id,
                mensagem: "ChatEngine ainda não está plugada nesta build.")
        case "ping":
            await enviar(
                conexao,
                WsDecodificador.texto(
                    #"{"type":"pong","id":"\#(identificadorJson(id))"}"#))
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
                #"{"type":"monitor.update","id":"\#(idJson)","payload":{"composition":\#(String(decoding: corpo, as: UTF8.self))}}"#
        case .erro(let codigo, let texto):
            mensagem =
                #"{"type":"monitor.error","id":"\#(idJson)","payload":{"code":"\#(codigo)","message":"\#(texto)"}}"#
        }
        await enviar(conexao, WsDecodificador.texto(mensagem))
    }

    private static func enviarErro(
        _ conexao: NWConnection,
        codigo: String,
        id: String?,
        mensagem: String = "Mensagem fora do contrato v1.") async {
        await enviar(
            conexao,
            WsDecodificador.texto(
                #"{"type":"error","id":"\#(identificadorJson(id))","payload":{"code":"\#(codigo)","message":"\#(mensagem)"}}"#))
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
            #"{"type":"error","id":"\#(identificadorJson(id))","payload":{"code":"\#(codigo)","message":"\#(mensagem)"}}"#
    }

    private static func identificadorJson(_ id: String?) -> String {
        guard let id else { return "" }
        guard let dados = try? JSONEncoder().encode(id) else { return "" }
        return String(decoding: dados, as: UTF8.self)
    }

    private static func origemAceita(_ origem: String?) -> Bool {
        guard let origem else { return true }
        if origem == "null" { return true }
        guard let url = URL(string: origem), let host = url.host else { return false }
        return ["localhost", "127.0.0.1", "::1"].contains(host.lowercased())
    }

    private static func despedir(
        _ conexao: NWConnection,
        assinatura: UUID? = nil,
        monitor: MonitorHub? = nil,
        idMonitor: String? = nil) async {
        if let assinatura {
            await monitor?.cancelar(assinatura)
        }
        if idMonitor != nil {
            // nada a fazer: o identificador só existe para o log do cliente
        }
        await enviar(conexao, WsDecodificador.fechar())
        conexao.cancel()
    }

    // MARK: - HTTP

    private static func responderHttp(
        _ pedido: PedidoHttp,
        estado: EstadoSessao,
        gateway: ArenaGateway) async -> RespostaHttp {
        switch pedido.rota {
        case "/api/v1/health":
            return .json(Data(#"{"protocol":"resolux-api/1","status":"online"}"#.utf8))
        case "/api/v1/session":
            return await responderSessao(pedido, estado: estado)
        case "/api/v1/tools":
            return .json(Data(#"{"tools":[]}"#.utf8))
        default:
            if pedido.rota.hasPrefix("/api/v1/arena") {
                return await responderArena(pedido, gateway: gateway)
            }
            return RespostaHttp.erro(
                codigo: "not_found",
                mensagem: "Rota fora do contrato v1.",
                status: 404)
        }
    }

    private static func responderSessao(
        _ pedido: PedidoHttp,
        estado: EstadoSessao) async -> RespostaHttp {
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
