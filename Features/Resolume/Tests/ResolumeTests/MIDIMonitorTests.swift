import Foundation
import Testing
@testable import Resolume

@Test("Contador de pacotes MIDI acumula por fonte")
func midiPacketCounterAccumulates() {
    let counter = MIDIPacketCounter()
    counter.record(uniqueID: 42, packets: 3)
    counter.record(uniqueID: 42, packets: 2)
    counter.record(uniqueID: 43, packets: 1)
    #expect(counter.snapshot(42).count == 5)
    #expect(counter.snapshot(43).count == 1)
    #expect(counter.snapshot(42).lastAt != nil)
}

@Test("MIDI monitor ao vivo mantém cliente e enumera fontes")
func midiLiveStatus() async {
    let source = CoreMIDIMonitorSource()
    let first = await source.status()
    #expect(first.isAvailable)
    #expect(first.error == nil)
    for sourceState in first.sources {
        #expect(!sourceState.name.isEmpty)
        #expect(sourceState.packetCount >= 0)
    }
    let second = await source.status()
    #expect(second.isAvailable)
}
