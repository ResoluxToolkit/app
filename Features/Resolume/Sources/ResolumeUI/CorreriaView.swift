import Combine
import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

public enum CorreriaContent: Equatable, Hashable {
    case image(URL)
    case video(URL)
}

public struct CorreriaView: View {
    private let content: CorreriaContent
    private let onConfirm: () -> Void
    private let onVideoEnded: () -> Void
    private let onCancel: () -> Void

    @State private var image: NSImage?
    @State private var player: AVPlayer?
    @State private var playerItem: AVPlayerItem?
    @State private var videoStarted = false

    public init(
        content: CorreriaContent,
        onConfirm: @escaping () -> Void,
        onVideoEnded: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.content = content
        self.onConfirm = onConfirm
        self.onVideoEnded = onVideoEnded
        self.onCancel = onCancel
    }

    public var body: some View {
        ZStack {
            background
                .ignoresSafeArea()

            Color.black.opacity(0.35)
                .ignoresSafeArea()

            if case .video = content, videoStarted {
                EmptyView()
            } else {
                VStack(spacing: 22) {
                    Text("Correria!")
                        .font(.system(size: 36, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)

                    Button {
                        activate()
                    } label: {
                        Text("vrau...")
                            .font(.system(size: 64, weight: .black, design: .rounded))
                            .padding(.horizontal, 42)
                            .padding(.vertical, 24)
                            .background(
                                Capsule().fill(.white.opacity(0.16))
                            )
                            .overlay(
                                Capsule().strokeBorder(.white.opacity(0.28), lineWidth: 1.5)
                            )
                            .shadow(color: .black.opacity(0.35), radius: 22, y: 8)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.defaultAction)

                    Text("Enter confirma · Esc cancela")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
        }
        .id(content)
        .onAppear(perform: prepare)
        .onReceive(
            NotificationCenter.default.publisher(
                for: .AVPlayerItemDidPlayToEndTime,
                object: playerItem
            )
        ) { _ in
            onVideoEnded()
        }
        .onDisappear(perform: cleanup)
        .onExitCommand(perform: onCancel)
    }

    @ViewBuilder
    private var background: some View {
        switch content {
        case .image:
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.gray
            }

        case .video:
            if let player {
                VideoBackgroundView(player: player)
            } else {
                Color.gray
            }
        }
    }

    private func prepare() {
        switch content {
        case .image(let url):
            image = NSImage(contentsOfFile: url.path)

        case .video(let url):
            let item = AVPlayerItem(url: url)
            let player = AVPlayer(playerItem: item)
            self.playerItem = item
            self.player = player
        }
    }

    private func activate() {
        switch content {
        case .image:
            onConfirm()

        case .video:
            videoStarted = true
            player?.play()
        }
    }

    private func cleanup() {
        player?.pause()
        player = nil
        playerItem = nil
        image = nil
    }
}

private struct VideoBackgroundView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        view.wantsLayer = true
        let layer = AVPlayerLayer()
        layer.videoGravity = .resizeAspectFill
        view.layer = layer
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        (view.layer as? AVPlayerLayer)?.player = player
    }
}

public extension View {
    func correriaDropTarget(
        snapshot: (() -> Void)? = nil,
        restore: (() -> Void)? = nil
    ) -> some View {
        modifier(CorreriaDropTargetModifier(snapshot: snapshot, restore: restore))
    }
}

private struct CorreriaDropTargetModifier: ViewModifier {
    @State private var content: CorreriaContent?
    @State private var isReceivingDrop = false

    private let snapshot: (() -> Void)?
    private let restore: (() -> Void)?

    init(
        snapshot: (() -> Void)? = nil,
        restore: (() -> Void)? = nil
    ) {
        self.snapshot = snapshot
        self.restore = restore
    }

    func body(content: Content) -> some View {
        content
            .onDrop(
                of: [UTType.movie, UTType.image],
                delegate: CorreriaDropDelegate(isTargeted: $isReceivingDrop) { result in
                    isReceivingDrop = false
                    self.content = result
                }
            )
            .overlay {
                if isReceivingDrop {
                    CorreriaDropHint()
                }
            }
            .overlay {
                if let droppedContent = self.content {
                    CorreriaView(content: droppedContent) {
                        self.content = nil
                    } onVideoEnded: {
                        self.content = nil
                    } onCancel: {
                        self.content = nil
                    }
                    .onAppear(perform: snapshot)
                    .onDisappear(perform: restore)
                }
            }
    }
}

private struct CorreriaDropDelegate: DropDelegate {
    @Binding var isTargeted: Bool
    private let onItem: (CorreriaContent?) -> Void

    init(isTargeted: Binding<Bool>, onItem: @escaping (CorreriaContent?) -> Void) {
        _isTargeted = isTargeted
        self.onItem = onItem
    }

    func dropEntered(info: DropInfo) {
        isTargeted = true
    }

    func dropExited(info: DropInfo) {
        isTargeted = false
    }

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [UTType.movie.identifier, UTType.image.identifier])
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .copy)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let provider = info.itemProviders(for: [UTType.fileURL.identifier]).first else {
            return false
        }

        provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
            let result = data.flatMap { URL(dataRepresentation: $0, relativeTo: nil) }
                .flatMap(CorreriaContentFactory.content(from:))

            Task { @MainActor in
                isTargeted = false
                onItem(result)
            }
        }

        return true
    }
}

private enum CorreriaContentFactory {
    static func content(from url: URL) -> CorreriaContent? {
        guard let contentType = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType else {
            return nil
        }

        if contentType.conforms(to: .movie) {
            return .video(url)
        }

        if contentType.conforms(to: .image) {
            return .image(url)
        }

        return nil
    }
}

private struct CorreriaDropHint: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()

            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .strokeBorder(
                    .white.opacity(0.8),
                    style: StrokeStyle(lineWidth: 3, dash: [14, 10])
                )
                .padding(28)

            VStack(spacing: 14) {
                Image(systemName: "square.and.arrow.down.fill")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(.white)

                Text("Solte o arquivo")
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)

                Text("Vídeo ou imagem para a Correria!")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
    }
}
