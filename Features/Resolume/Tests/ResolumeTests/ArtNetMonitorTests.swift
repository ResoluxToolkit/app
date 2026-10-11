import Foundation
import Testing
@testable import Resolume

func artNetHeader(opcodeHigh: UInt8) -> [UInt8] {
    Array("Art-Net\0".utf8) + [0x00, opcodeHigh]
}

@Test("Parser Art-Net extrai opcode e universo do ArtDMX")
func artNetParserDMX() {
    let datagram = artNetHeader(opcodeHigh: 0x50)
        + [0x00, 0x0E, 0x00, 0x00, 0x2A, 0x01, 0x00, 0x04, 0xFF, 0x00, 0xFF, 0x00]
    let packet = ArtNetParser.packet(in: datagram)
    #expect(packet?.kind == .dmx)
    #expect(packet?.universe == 0x012A)
}

@Test("Parser Art-Net distingue poll, reply, sync e lixo")
func artNetParserKinds() {
    #expect(ArtNetParser.packet(in: artNetHeader(opcodeHigh: 0x20) + [0x00, 0x0E, 0x00])?.kind == .poll)
    #expect(ArtNetParser.packet(in: artNetHeader(opcodeHigh: 0x21) + [0x00, 0x0E])?.kind == .pollReply)
    #expect(ArtNetParser.packet(in: artNetHeader(opcodeHigh: 0x52) + [0x00, 0x0E])?.kind == .sync)
    #expect(ArtNetParser.packet(in: Array("lixo".utf8)) == nil)
    #expect(ArtNetParser.packet(in: artNetHeader(opcodeHigh: 0x50)) == nil)
}

@Test("Parser ArtPollReply extrai IP, nomes e status")
func artNetParserNode() {
    var datagram = artNetHeader(opcodeHigh: 0x21)
    datagram += [0xC0, 0xA8, 0x07, 0x2A]
    datagram += [0x19, 0x36]
    datagram += [0x00, 0x0E]
    datagram += [0x00, 0x00]
    datagram += [0x00, 0x00]
    datagram += [0x00]
    datagram += [0x08]
    datagram += [0x7F, 0xFF]
    let shortName = Array("VJ-Node".utf8)
    let longName = Array("VJ-Node Longo".utf8)
    datagram += shortName + Array(repeating: 0, count: 18 - shortName.count)
    datagram += longName + Array(repeating: 0, count: 64 - longName.count)
    let node = ArtNetParser.node(from: datagram)
    #expect(node?.ipAddress == "192.168.7.42")
    #expect(node?.shortName == "VJ-Node")
    #expect(node?.longName == "VJ-Node Longo")
    #expect(node?.status1 == 0x08)
}

@Test("ArtPoll ao vivo no loopback devolve resultado sem travar")
func artNetLivePoll() async {
    let probe = ArtNetPollProbe(timeout: 0.5)
    let result = await probe.poll(broadcast: false)
    #expect(result.error == nil)
    for node in result.nodes {
        #expect(!node.shortName.isEmpty || !node.longName.isEmpty)
        #expect(node.ipAddress.contains("."))
    }
}
