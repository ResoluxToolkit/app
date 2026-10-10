import Foundation

/// Mensagem WS decodificada de um fluxo de frames (RFC 6455, lado servidor).
/// Opcode segue o RFC: 1 = texto, 2 = binário, 8 = close, 9 = ping, 10 = pong.
public struct WsMensagem: Equatable, Sendable {
    public let opcode: UInt8
    public let fin: Bool
    public let payload: Data
}

/// Decodificador incremental: o frame do cliente chega quebrado ou junto.
/// Frames do cliente são sempre mascarados; os nossos saem sem máscara.
public struct WsDecodificador: Sendable {
    private var buffer = Data()
    private var emAndamento: (opcode: UInt8, payload: Data)?

    public init() {}

    public mutating func alimentar(_ dados: Data) -> [WsMensagem] {
        buffer.append(dados)
        var mensagens: [WsMensagem] = []
        while let (mensagem, consumido) = Self.extrair(buffer) {
            buffer.removeFirst(consumido)
            if mensagem.opcode == 0, let anterior = emAndamento {
                var payload = anterior.payload
                payload.append(mensagem.payload)
                if mensagem.fin {
                    emAndamento = nil
                    mensagens.append(WsMensagem(
                        opcode: anterior.opcode,
                        fin: true,
                        payload: payload))
                } else {
                    emAndamento = (anterior.opcode, payload)
                }
                continue
            }
            if !mensagem.fin {
                emAndamento = (mensagem.opcode, mensagem.payload)
                continue
            }
            if let anterior = emAndamento {
                emAndamento = nil
                mensagens.append(WsMensagem(
                    opcode: anterior.opcode,
                    fin: mensagem.fin,
                    payload: anterior.payload + mensagem.payload))
            } else {
                mensagens.append(mensagem)
            }
        }
        return mensagens
    }

    /// Frame completo mais próximo do buffer e quantos bytes ele consome.
    private static func extrair(_ dados: Data) -> (WsMensagem, Int)? {
        guard dados.count >= 2 else { return nil }
        let primeiro = dados[dados.startIndex]
        let opcode = primeiro & 0x0F
        let fin = primeiro & 0x80 != 0
        let mascarado = dados[dados.startIndex + 1] & 0x80 != 0
        let seteBits = Int(dados[dados.startIndex + 1] & 0x7F)
        var indice = dados.startIndex + 2
        var comprimento = seteBits
        if seteBits == 126 {
            guard dados.count - 2 >= 2 else { return nil }
            comprimento = (Int(dados[indice]) << 8) | Int(dados[indice + 1])
            indice += 2
        } else if seteBits == 127 {
            guard dados.count - 2 >= 8 else { return nil }
            comprimento = 0
            for _ in 0..<8 {
                comprimento = (comprimento << 8) | Int(dados[indice])
                indice += 1
            }
        }
        var chaveMascara: Data?
        if mascarado {
            guard dados.endIndex - indice >= 4 else { return nil }
            chaveMascara = dados.subdata(in: indice..<indice + 4)
            indice += 4
        }
        guard dados.endIndex - indice >= comprimento else { return nil }
        var payload = dados.subdata(in: indice..<indice + comprimento)
        if let chave = chaveMascara {
            payload = Data((0..<payload.count).map { offset in
                payload[payload.startIndex + offset] ^ chave[chave.startIndex + offset % 4]
            })
        }
        return (
            WsMensagem(opcode: opcode, fin: fin, payload: payload),
            indice + comprimento - dados.startIndex)
    }

    // MARK: - Server → cliente (frames sem máscara)

    public static func texto(_ conteudo: String) -> Data {
        var frame = Data([0x81])
        frame.append(encabezado(comprimento: conteudo.utf8.count))
        frame.append(Data(conteudo.utf8))
        return frame
    }

    public static func pong(payload: Data = Data()) -> Data {
        var frame = Data([0x8A])
        frame.append(encabezado(comprimento: payload.count))
        frame.append(payload)
        return frame
    }

    public static func fechar() -> Data {
        Data([0x88, 0x00])
    }

    private static func encabezado(comprimento: Int) -> Data {
        if comprimento < 126 {
            return Data([UInt8(comprimento)])
        }
        if comprimento <= 0xFFFF {
            return Data([126, UInt8(comprimento >> 8), UInt8(comprimento & 0xFF)])
        }
        var longo = Data([127])
        for deslocamento in stride(from: 56, through: 0, by: -8) {
            longo.append(UInt8((comprimento >> deslocamento) & 0xFF))
        }
        return longo
    }
}

/// Handshake de upgrade (RFC 6455 §4.2.2): resposta canônica com o
/// `Sec-WebSocket-Accept` calculado com SHA-1 + GUID.
public enum WsHandshake {
    public static let guia = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

    public static func aceitar(chave: String) -> String {
        sha1(Data((chave + guia).utf8)).base64EncodedString()
    }

    /// SHA-1 puro para o handshake WS (20 bytes). O handshake só precisa
    /// disso — sem puxar dependência nova nem ferir o contrato.
    static func sha1(_ dados: Data) -> Data {
        var mensagem = Data(dados)
        let bitsOriginais = UInt64(dados.count) * 8
        mensagem.append(0x80)
        while mensagem.count % 64 != 56 {
            mensagem.append(0x00)
        }
        for deslocamento in stride(from: 56, through: 0, by: -8) {
            mensagem.append(UInt8((bitsOriginais >> UInt64(deslocamento)) & 0xFF))
        }

        var estado: [UInt32] = [
            0x67452301, 0xEFCDAB89, 0x98BADCFE, 0x10325476, 0xC3D2E1F0,
        ]

        for inicio in stride(from: 0, to: mensagem.count, by: 64) {
            var w: [UInt32] = []
            for indice in 0..<16 {
                let base = inicio + indice * 4
                let valor =
                    (UInt32(mensagem[base]) << 24) |
                    (UInt32(mensagem[base + 1]) << 16) |
                    (UInt32(mensagem[base + 2]) << 8) |
                    UInt32(mensagem[base + 3])
                w.append(valor)
            }
            for indice in 16..<80 {
                let valor = w[indice - 3] ^ w[indice - 8] ^ w[indice - 14] ^ w[indice - 16]
                w.append((valor << 1) | (valor >> 31))
            }

            var a = estado[0]
            var b = estado[1]
            var c = estado[2]
            var d = estado[3]
            var e = estado[4]
            for indice in 0..<80 {
                let funcao: UInt32
                let constante: UInt32
                switch indice {
                case 0..<20:
                    funcao = (b & c) | ((~b) & d)
                    constante = 0x5A827999
                case 20..<40:
                    funcao = b ^ c ^ d
                    constante = 0x6ED9EBA1
                case 40..<60:
                    funcao = (b & c) | (b & d) | (c & d)
                    constante = 0x8F1BBCDC
                default:
                    funcao = b ^ c ^ d
                    constante = 0xCA62C1D6
                }
                let novoA = ((a << 5) | (a >> 27)) &+ funcao &+ e &+ constante &+ w[indice]
                let novoB = a
                let novoC = (b << 30) | (b >> 2)
                let novoD = c
                let novoE = d
                a = novoA
                b = novoB
                c = novoC
                d = novoD
                e = novoE
            }
            estado[0] &+= a
            estado[1] &+= b
            estado[2] &+= c
            estado[3] &+= d
            estado[4] &+= e
        }

        var saida = Data()
        for palavra in estado {
            saida.append(UInt8((palavra >> 24) & 0xFF))
            saida.append(UInt8((palavra >> 16) & 0xFF))
            saida.append(UInt8((palavra >> 8) & 0xFF))
            saida.append(UInt8(palavra & 0xFF))
        }
        return saida
    }
}
