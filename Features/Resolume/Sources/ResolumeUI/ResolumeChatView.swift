import Resolume
import ResoluxDesignSystem
import BorderBeamKit
import SwiftUI

/// Chat com o Arena no tema MEVOLIT.
///
/// Zero campo de configuração: a pessoa abre o Arena, abre este app e o app
/// descobre o provedor local sozinho. Pedir IP, porta ou API key aqui seria
/// jogar no operador um trabalho que é nosso.
public struct ResolumeChatView: View {
    @State private var model = ResolumeChatModel()
    @State private var policyMode: ToolPolicy.Mode = .readOnly

    public init(product: ResolumeProduct = .arena) {
        _model = State(initialValue: ResolumeChatModel(product: product))
    }

    public var body: some View {
        ZStack {
            AuroraBackground()

            VStack(spacing: 0) {
                header
                transcript
                inputBar
            }
            .frame(maxWidth: 620)
            .padding(.horizontal, 16)
        }
        .foregroundStyle(Palette.foreground)
        .frame(minWidth: 460, minHeight: 440)
        .preferredColorScheme(.dark)
    }

    // MARK: - Cabeçalho

    private var header: some View {
        HStack(spacing: 12) {
            ToneIcon(symbol: "waveform.path.ecg", tone: .violet, size: 42)

            VStack(alignment: .leading, spacing: 2) {
                Text("Resolux")
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                Text(subtitulo)
                    .font(.caption)
                    .foregroundStyle(Palette.muted)
                    .lineLimit(2)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 8)
            StatusPill(text: statusTexto, tone: statusTom)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 12)
        #if os(macOS)
        // Com a barra de titulo oculta os semaforos ficam soltos no canto
        // superior esquerdo. Em janela larga eles caem na margem e nao
        // incomodam; em janela estreita o cabecalho encosta neles, entao o
        // topo respira um pouco mais aqui do que no Mevolit, que nunca
        // encolhe alem de 480.
        .padding(.top, 14)
        #endif
    }

    private var subtitulo: String {
        if let backend = model.backend {
            return "\(model.productName) · \(backend.displayName)"
        }
        return "\(model.productName) · procurando provedor local"
    }

    private var statusTexto: String {
        switch model.phase {
        case .idle: "desligado"
        case .connecting: "conectando"
        case .ready(let tools): statusFerramentas(totalServidor: tools)
        case .failed: "sem conexão"
        }
    }

    /// Com o Apple no ar, anunciar "22 ferramentas" seria mentira -- o servidor
    /// declara 22 e a gente só consegue oferecer 10. Anunciamos o recorte.
    private func statusFerramentas(totalServidor: Int) -> String {
        if let oferecidas = model.backend?.toolAllowlist?.count, oferecidas < totalServidor {
            return "\(oferecidas) de \(totalServidor) ferramentas"
        }
        return "\(totalServidor) ferramentas"
    }
    private var statusTom: Tone {
        switch model.phase {
        case .idle: .neutral
        case .connecting: .amber
        case .ready: .green
        case .failed: .coral
        }
    }

    /// Total de ferramentas que o **servidor** declarou (antes do nosso filtro).
    /// É o denominador honesto do aviso de capenga: 22 é o que medimos no Arena
    /// 7.28.0, mas quem manda o número é o `tools/list` vivo, não eu.
    private var toolTotal: Int {
        if case .ready(let count) = model.phase { return count }
        return 22
    }

    // MARK: transcript
    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    avisoInicial
                    avisoCapenga
                    ForEach(model.lines) { linha in
                        bubble(for: linha)
                            .id(linha.id)
                    }
                    if model.isBusy {
                        thinkingRow
                    }
                }
                .padding(.vertical, 10)
            }
            .scrollBounceBehavior(.basedOnSize)
            .onChange(of: model.lines.count) {
                // `proxy.animate` nao existe; o certo e envolver o scrollTo em
                // withAnimation. Sem o .id() na bolha acima isto nao acha nada.
                if let last = model.lines.last {
                    withAnimation(.easeOut(duration: 0.25)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    @ViewBuilder private var avisoInicial: some View {
        if model.engine == nil, case .idle = model.phase {
            GlassCard(cornerRadius: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Abra o Arena e clique em conectar", systemImage: "sparkles")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                    Text("A gente acha o Arena e o modelo sozinho -- nada pra configurar.")
                        .font(.footnote)
                        .foregroundStyle(Palette.muted)
                    Picker("Modo", selection: $policyMode) {
                        Text("Somente leitura").tag(ToolPolicy.Mode.readOnly)
                        Text("Permitir alterações").tag(ToolPolicy.Mode.readWrite)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .controlSize(.small)
                    // Sem isto o segmento ativo sai no azul padrao do macOS, que
                    // nao e a paleta dele. deepViolet e o tom de acao do MEVOLIT.
                    .tint(Palette.deepViolet)
                    .colorScheme(.dark)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// "Você está capenga."
    ///
    /// Regra do operador: *o que não der pra fazer, a gente explica* -- não
    /// escondemos limitação. O `fm serve` da Apple aceita só as 10 ferramentas
    /// baratas (medido: a 11ª derruba HTTP 500) e `layer` está fora dela, então
    /// pergunta de camada/efeito fica sem resposta honesta por esse caminho.
    /// Ele votou Apple de cara mesmo assim; o acordo é ele ficar sabendo.
    @ViewBuilder private var avisoCapenga: some View {
        if model.backend?.kind == .appleFoundationModels {
            GlassCard(cornerRadius: 18) {
                HStack(alignment: .top, spacing: 10) {
                    ToneIcon(symbol: "exclamationmark.triangle", tone: .amber, size: 26)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Você está capenga")
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundStyle(.white)
                        Text("Modelo da Apple só enxerga \(model.backend?.toolAllowlist?.count ?? 0) de \(toolTotal) ferramentas do Arena — camada e efeito ficaram de fora. Caindo pro gateway local a gente fala com tudo.")
                            .font(.caption)
                            .foregroundStyle(Palette.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func bubble(for linha: ResolumeChatModel.Line) -> some View {
        HStack {
            if linha.role == "user" { Spacer(minLength: 56) }
            Text(linha.text)
                .textSelection(.enabled)
                .font(.system(size: 14))
                .foregroundStyle(Palette.foreground)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(bubbleFill(for: linha), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Palette.hairline, lineWidth: 1))
            if linha.role != "user" { Spacer(minLength: 56) }
        }
    }

    /// Usuário = violeta (quem manda); bot = vidro fumê (o Arena respondendo).
    private func bubbleFill(for linha: ResolumeChatModel.Line) -> AnyShapeStyle {
        if linha.role == "user" {
            return AnyShapeStyle(Palette.deepViolet.opacity(0.45))
        }
        if linha.role == "system" {
            return AnyShapeStyle(Palette.coral.opacity(0.18))
        }
        return AnyShapeStyle(.ultraThinMaterial)
    }

    /// O modelo está trabalhando. Um turno local com as 22 ferramentas leva ~2
    /// minutos, então isso aqui precisa existir -- sem ele a tela parece morta.
    private var thinkingRow: some View {
        HStack(spacing: 10) {
            ThinkingOrb()
            Text(model.isBusy ? "pensando e consultando o Arena…" : "")
                .font(.footnote)
                .foregroundStyle(Palette.muted)
            Spacer(minLength: 0)
        }
        .padding(.leading, 4)
    }

    // MARK: - Entrada
    private var inputBar: some View {
        VStack(spacing: 8) {
            botaoConectar
            HStack(spacing: 10) {
                TextField("Fala com o Arena…", text: $model.draft, axis: .vertical)
                    .lineLimit(1...4)
                    .font(.system(size: 15))
                    .foregroundStyle(.white)
                    .textFieldStyle(.plain)
                    .onSubmit { Task { await model.sendDraft() } }
                    .disabled(!podeEnviar)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .environment(\.colorScheme, .dark)
                            .opacity(0.7)
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.15), lineWidth: 1))
                    .borderBeam(
                        .line,
                        colorVariant: .ocean,
                        theme: .dark,
                        active: model.isBusy,
                        borderRadius: 18
                    )

                Button {
                    Task { await model.sendDraft() }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(Palette.primaryGradient)
                }
                .buttonStyle(.plain)
                .disabled(!podeEnviar)
            }
        }
        .padding(.vertical, 12)
    }

    private var podeEnviar: Bool {
        model.engine != nil && !model.isBusy && !model.draft.isEmpty
    }

    @ViewBuilder private var botaoConectar: some View {
        if model.engine != nil {
            HStack {
                Spacer()
                Button("Desconectar") { model.disconnect() }
                    .buttonStyle(.plain)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.muted)
            }
        } else if model.phase != .connecting {
            GlowButton(
                title: model.phase == .idle ? "Conectar ao Arena" : "Tentar de novo",
                symbol: "bolt.horizontal.circle",
                spinning: model.phase == .connecting
            ) {
                model.connect(policyMode: policyMode)
            }
        }
    }
}
