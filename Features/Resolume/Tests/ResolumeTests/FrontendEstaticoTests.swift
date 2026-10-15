import Foundation
import Testing
@testable import ResoluxServer

@Test("frontend estático serve index e assets")
func serveIndexEAssets() throws {
    let raiz = FileManager.default.temporaryDirectory
        .appendingPathComponent("resolux-front-" + UUID().uuidString)
    try FileManager.default.createDirectory(
        at: raiz.appendingPathComponent("assets"),
        withIntermediateDirectories: true)
    try Data("<!doctype html><title>ok</title>".utf8)
        .write(to: raiz.appendingPathComponent("index.html"))
    try Data("console.log('ok')".utf8)
        .write(to: raiz.appendingPathComponent("assets/app.test.js"))

    let front = FrontendEstatico(raiz: raiz)
    let index = front.resposta(PedidoHttp.fixe("/"))
    #expect(index.status == 200)
    #expect(index.contentType.contains("text/html"))
    #expect(String(decoding: index.corpo, as: UTF8.self).contains("<title>ok</title>"))

    let asset = front.resposta(PedidoHttp.fixe("/assets/app.test.js"))
    #expect(asset.status == 200)
    #expect(asset.contentType.contains("text/javascript"))
    #expect(String(decoding: asset.corpo, as: UTF8.self) == "console.log('ok')")
}

@Test("frontend estático bloqueia caminho fora da raiz")
func bloqueiaForaDaRaiz() throws {
    let raiz = FileManager.default.temporaryDirectory
        .appendingPathComponent("resolux-front-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: raiz, withIntermediateDirectories: true)
    try Data("ok".utf8).write(to: raiz.appendingPathComponent("index.html"))
    let front = FrontendEstatico(raiz: raiz)
    let resposta = front.resposta(PedidoHttp.fixe("/../package.json"))
    #expect(resposta.status == 404)
}

extension PedidoHttp {
    static func fixe(_ caminho: String) -> PedidoHttp {
        PedidoHttp(
            metodo: "GET",
            caminho: caminho,
            cabecalhos: [:],
            corpo: Data())
    }
}
