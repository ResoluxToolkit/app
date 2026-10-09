import Testing
@testable import ResolumeUI

struct ContinuityCameraSelectionTests {
    @Test func keepsExistingContinuitySelectionWhenStillAvailable() {
        let devices = [
            CameraDevice(id: "iphone-1", name: "iPhone de Luizinho", isContinuityCamera: true),
            CameraDevice(id: "iphone-2", name: "iPhone de Palco", isContinuityCamera: true),
        ]

        #expect(CameraDeviceSelector.preferredID(from: devices, currentID: "iphone-1") == "iphone-1")
    }

    @Test func picksFirstContinuityCameraWhenNothingIsSelected() {
        let devices = [
            CameraDevice(id: "iphone-1", name: "iPhone de Luizinho", isContinuityCamera: true),
            CameraDevice(id: "iphone-2", name: "iPhone de Palco", isContinuityCamera: true),
        ]

        #expect(CameraDeviceSelector.preferredID(from: devices, currentID: nil) == "iphone-1")
    }

    @Test func acceptsEmptyCameraList() {
        #expect(CameraDeviceSelector.preferredID(from: [], currentID: nil) == nil)
    }

    @Test func keepsOnlyContinuityCameras() {
        let devices = [
            CameraDevice(id: "usb-1", name: "USB3 Video", isContinuityCamera: false),
            CameraDevice(id: "facetime-1", name: "Câmera FaceTime HD", isContinuityCamera: false),
            CameraDevice(id: "iphone-1", name: "Câmera do iPhone", isContinuityCamera: true),
        ]

        let filtered = CameraDeviceSelector.continuityCameras(from: devices)

        #expect(filtered.map(\.id) == ["iphone-1"])
    }
}
