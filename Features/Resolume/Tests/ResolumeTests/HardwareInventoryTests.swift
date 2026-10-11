import Foundation
import Testing
@testable import Resolume

@Test("Dispositivos de captura ao vivo têm nome e conexão")
func captureDevicesLive() async {
    let probe = AVCaptureDeviceProbe()
    let devices = await probe.devices()
    for device in devices {
        #expect(!device.name.isEmpty)
        #expect(!device.uniqueID.isEmpty)
        if let position = device.position {
            #expect(position == "frontal" || position == "traseira")
        }
        #expect(device.hasVideo || device.hasAudio)
    }
}

@Test("Dispositivos de áudio ao vivo têm defaults únicos e streams")
func audioDevicesLive() async {
    let source = CoreAudioDeviceSource()
    let devices = await source.devices()
    #expect(devices.count >= 1)
    #expect(devices.filter { $0.isDefaultInput }.count <= 1)
    #expect(devices.filter { $0.isDefaultOutput }.count <= 1)
    for device in devices {
        #expect(!device.uid.isEmpty)
        #expect(!device.name.isEmpty)
        #expect(device.inputStreams >= 0)
        #expect(device.outputStreams >= 0)
    }
}

@Test("Displays ao vivo têm exatamente um principal")
func displaysLive() {
    let displays = DisplaySource.displays()
    #expect(displays.count >= 1)
    #expect(displays.filter { $0.isMain }.count == 1)
    for display in displays {
        #expect(display.pointWidth > 0)
        #expect(display.pixelWidth >= display.pointWidth)
        #expect(display.pixelHeight >= display.pointHeight)
        #expect(display.refreshRate >= 0)
    }
}
