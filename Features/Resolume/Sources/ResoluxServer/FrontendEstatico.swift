import Foundation
import Resolume

/// Servidor do bundle estático do frontend em modo release. O debug continua
/// usando o Vite; o release usa o `dist/` já construído pela mesma origem
/// do daemon, sem processo web extra.
struct FrontendEstatico: Sendable {
    let raiz: URL

    init(raiz: URL) {
        self.raiz = raiz.standardizedFileURL
    }

    /// Bundle estático do frontend. Só existe com `RESOLUX_FRONT_DIST`
    /// apontando para o `dist/` — modo debug sobe sem a variável e fica
    /// apenas com a API na 1980; o `release.sh` define o caminho.
    static func localizar(
        ambiente: [String: String] = ProcessInfo.processInfo.environment) -> FrontendEstatico? {
        guard let caminho = ambiente["RESOLUX_FRONT_DIST"], !caminho.isEmpty else { return nil }
        return FrontendEstatico(raiz: URL(fileURLWithPath: caminho))
    }

    func resposta(_ pedido: PedidoHttp) -> RespostaHttp {
        guard pedido.metodo == "GET" || pedido.metodo == "HEAD" else {
            return RespostaHttp.erro(
                codigo: "method_not_allowed",
                mensagem: "Use GET ou HEAD.",
                status: 405)
        }

        let rota = pedido.rota
        guard rota.hasPrefix("/") else {
            return .erro(codigo: "not_found", mensagem: "Caminho inválido.", status: 400)
        }

        var caminho = rota
        if caminho == "/" || caminho == "/index.html" {
            caminho = "/index.html"
        }

        let destino = raiz.appendingPathComponent(
            String(caminho.dropFirst()).removingPercentEncoding ?? String(caminho.dropFirst())
        ).standardizedFileURL
        let prefixoRaiz = raiz.standardizedFileURL.path
        guard destino.path == prefixoRaiz || destino.path.hasPrefix(prefixoRaiz + "/") else {
            return .erro(codigo: "not_found", mensagem: "Caminho fora do bundle.", status: 404)
        }

        if let corpo = FileManager.default.contents(atPath: destino.path) {
            return RespostaHttp(
                status: 200,
                contentType: Self.mime(for: destino),
                corpo: corpo)
        }

        if !rota.contains("."), let index = FileManager.default.contents(
            atPath: raiz.appendingPathComponent("index.html").path) {
            return RespostaHttp(
                status: 200,
                contentType: "text/html; charset=utf-8",
                corpo: index)
        }

        return .erro(codigo: "not_found", mensagem: "Arquivo não encontrado.", status: 404)
    }

    private static func mime(for arquivo: URL) -> String {
        switch arquivo.pathExtension.lowercased() {
        case "html": return "text/html; charset=utf-8"
        case "js", "mjs": return "text/javascript; charset=utf-8"
        case "css": return "text/css; charset=utf-8"
        case "json": return "application/json; charset=utf-8"
        case "map": return "application/json; charset=utf-8"
        case "webmanifest": return "application/manifest+json"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "svg": return "image/svg+xml"
        case "ico": return "image/x-icon"
        case "woff": return "font/woff"
        case "woff2": return "font/woff2"
        default: return "application/octet-stream"
        }
    }
}
