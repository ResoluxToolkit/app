import AVFoundation
import ResoluxDesignSystem
import SwiftUI

public struct CameraDevice: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let isContinuityCamera: Bool

    public init(id: String, name: String, isContinuityCamera: Bool) {
        self.id = id
        self.name = name
        self.isContinuityCamera = isContinuityCamera
    }
}

public enum CameraDeviceSelector {
    public static func continuityCameras(from devices: [CameraDevice]) -> [CameraDevice] {
        devices.filter(\.isContinuityCamera)
    }

    public static func preferredID(from devices: [CameraDevice], currentID: String?) -> String? {
        if let currentID, devices.contains(where: { $0.id == currentID }) {
            return currentID
        }
        return devices.first?.id
    }
}

@MainActor
public final class ContinuityCameraModel: ObservableObject {
    @Published public private(set) var devices: [CameraDevice] = []
    @Published public private(set) var selectedDeviceID: String?
    @Published public private(set) var permissionGranted = false
    @Published public private(set) var running = false
    @Published public private(set) var errorMessage: String?

    public let session = AVCaptureSession()

    public init() {}

    public func refreshDevices() {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.external, .continuityCamera],
            mediaType: .video,
            position: .unspecified
        )

        devices = CameraDeviceSelector.continuityCameras(
            from: discovery.devices.map { device in
                CameraDevice(
                    id: device.uniqueID,
                    name: device.localizedName,
                    isContinuityCamera: device.isContinuityCamera)
            }
        )
        selectedDeviceID = CameraDeviceSelector.preferredID(from: devices, currentID: selectedDeviceID)
    }

    public func start() async {
        errorMessage = nil
        guard await requestPermission() else {
            errorMessage = "Acesso à câmera negado. Libere em Ajustes → Privacidade e Segurança → Câmera."
            return
        }

        guard let device = devices.first(where: { $0.id == selectedDeviceID }) else {
            errorMessage = "Nenhuma câmera disponível. Verifique se o iPhone está próximo, desbloqueado e com Wi-Fi/Bluetooth ligados."
            return
        }

        do {
            let input = try AVCaptureDeviceInput(device: try camera(for: device))
            session.beginConfiguration()
            session.inputs.forEach(session.removeInput)
            guard session.canAddInput(input) else {
                session.commitConfiguration()
                throw NSError(
                    domain: "dev.smartium.resoluxtoolkit.camera",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Não foi possível conectar a câmera selecionada."])
            }
            session.addInput(input)
            session.commitConfiguration()

            if !session.isRunning {
                session.startRunning()
            }
            running = true
            permissionGranted = true
        } catch {
            running = false
            errorMessage = error.localizedDescription
        }
    }

    public func stop() {
        if session.isRunning {
            session.stopRunning()
        }
        running = false
    }

    private func requestPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            permissionGranted = true
            return true
        case .notDetermined:
            let granted = await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .video) { granted in
                    continuation.resume(returning: granted)
                }
            }
            permissionGranted = granted
            return granted
        default:
            permissionGranted = false
            return false
        }
    }

    private func camera(for device: CameraDevice) throws -> AVCaptureDevice {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.external, .continuityCamera],
            mediaType: .video,
            position: .unspecified
        )
        guard
            let camera = discovery.devices.first(where: {
                $0.uniqueID == device.id && $0.isContinuityCamera
            })
        else {
            throw NSError(
                domain: "dev.smartium.resoluxtoolkit.camera",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "A câmera selecionada não está mais disponível."])
        }
        return camera
    }

}

public struct ContinuityCameraView: View {
    @StateObject private var model = ContinuityCameraModel()

    public init() {}

    public var body: some View {
        ScreenShell(
            title: "Continuity Camera",
            subtitle: "AVFoundation · vídeo local",
            symbol: "video.fill",
            tone: .cyan,
            status: model.running ? "ativa" : "parada",
            statusTone: model.running ? .green : .amber) {
                ScrollView {
                    VStack(spacing: 18) {
                        preview
                        controls
                    }
                    .frame(maxWidth: 900)
                    .frame(maxWidth: .infinity)
                }
            }
        .frame(minWidth: 720, minHeight: 480)
        .onAppear {
            model.refreshDevices()
            Task { await model.start() }
        }
        .onDisappear { model.stop() }
    }

    @ViewBuilder
    private var preview: some View {
        GlassCard(cornerRadius: 22) {
            VStack(alignment: .leading, spacing: 12) {
                if model.running {
                    CameraPreview(session: model.session)
                        .frame(height: 360)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "video.slash")
                            .font(.system(size: 34, weight: .medium))
                            .foregroundStyle(Palette.muted)
                        Text(model.errorMessage ?? "Aguardando câmera…")
                            .font(.subheadline)
                            .foregroundStyle(Palette.muted)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 260)
                }
            }
        }
    }

    private var controls: some View {
        GlassCard(cornerRadius: 22) {
            VStack(alignment: .leading, spacing: 14) {
                if model.devices.isEmpty {
                    Text("Nenhuma câmera encontrada.")
                        .font(.subheadline)
                        .foregroundStyle(Palette.muted)
                } else {
                    Text(model.devices.first?.name ?? "")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.foreground)
                }

                HStack(spacing: 10) {
                    GlowButton(
                        title: model.running ? "Parar" : "Iniciar",
                        symbol: model.running ? "stop.fill" : "play.fill",
                        beam: model.running) {
                            if model.running {
                                model.stop()
                            } else {
                                Task { await model.start() }
                            }
                        }

                    GlowButton(
                        title: "Atualizar",
                        symbol: "arrow.clockwise",
                        beam: false) {
                            model.refreshDevices()
                        }
                }

                Text("Sem transmissão de rede nesta tacada. Zero NDI no iOS.")
                    .font(.caption)
                    .foregroundStyle(Palette.muted)
            }
        }
    }
}

private struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> CameraPreviewView {
        let view = CameraPreviewView()
        view.wantsLayer = true
        guard let previewLayer = view.previewLayer else { return view }
        previewLayer.session = session
        previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateNSView(_ nsView: CameraPreviewView, context: Context) {
        guard let previewLayer = nsView.previewLayer, previewLayer.session !== session else { return }
        previewLayer.session = session
    }
}

private final class CameraPreviewView: NSView {
    override func makeBackingLayer() -> CALayer {
        AVCaptureVideoPreviewLayer()
    }

    override func layout() {
        super.layout()
        previewLayer?.frame = bounds
    }

    var previewLayer: AVCaptureVideoPreviewLayer? {
        layer as? AVCaptureVideoPreviewLayer
    }
}
