import Foundation

/// Gate de execução de ferramentas. O modelo escolhe a ferramenta, mas quem
/// decide se ela pode tocar no set é daqui.
///
/// Motivo real: num teste com o Arena aberto e set em uso, um modelo local de
/// 1,7B decidiu sozinho chamar `transport { action: "set", bpm: 120 }` e o
/// Arena aplicou em plena performance. Sem gate, um modelo burro com escrita
/// livre é uma colherada na mesa do VJ.
public struct ToolPolicy: Sendable, Equatable {
    public enum Mode: String, Sendable, Codable, CaseIterable {
        /// Só lê o set. É o padrão e é o modo sensato.
        case readOnly
        /// Deixa escrever. Só faz sentido com modelo confiável e set de teste.
        case readWrite
    }

    public var mode: Mode

    public init(mode: Mode = .readOnly) { self.mode = mode }

    public static let readOnly = ToolPolicy(mode: .readOnly)
    public static let readWrite = ToolPolicy(mode: .readWrite)

    /// Resultado da avaliação de uma chamada.
    public enum Decision: Sendable, Equatable {
        case allow
        /// Seria lícita, mas o modo atual é somente leitura.
        case readOnly(_ target: String)
        /// Proibida em modo algum.
        case never(_ target: String)

        public var isNever: Bool {
            if case .never = self { return true }
            return false
        }
    }

    /// Ações que não alteram nada. Monta do enum real devolvido pelo
    /// `tools/list` do Arena — não de chute meu. Ferramenta ou ação ausente
    /// desta tabela é tratada como escrita e bloqueada.
    static let safeActions: [String: Set<String>] = [
        "parameter": ["get", "get_animation"],
        "clip": ["get", "list", "find", "thumbnail", "dashboard_get", "get_transport"],
        "layer": ["get", "list", "dashboard_get"],
        "group": ["get", "list", "dashboard_get"],
        "column": ["get", "list"],
        "deck": ["get", "list"],
        "color_code": ["get", "list"],
        "composition": ["get", "list", "diff", "playing", "dashboard_get"],
        "effect": ["get", "list"],
        "transport": ["get"],
        "crossfader": ["get"],
        // catalog só enumera o que existe no produto.
        "catalog": ["effects", "sources", "blendmodes", "codecs", "autopilot", "monitoring",
                    "parameters", "animation", "palettes", "product", "transitions",
                    "trigger_pipeline", "gui", "audio", "dashboard", "transport"],
        "diagnose": ["get"],
        // "instructions" é o gate de leitura do próprio servidor.
        "status": ["get", "instructions"],
        "file": ["browse", "info", "loaded"],
        "autopilot": ["get", "list"],
        "transform": ["get"],
        "transition": ["get", "list", "options"],
        // monitor: só o que devolve estado textual. "snapshot" grava imagem em
        // disco e "motion" mexe no reactivity — nenhum dos dois é leitura clara.
        "monitor": ["inspect", "layers", "list", "diff"],
    ]

    /// Ações barradas em modo ALGUM — nem com "Permitir alterações" ligado.
    ///
    /// O critério aqui não é "é escrita?". É "irreversível ou re-temporiza o
    /// show?". As três famílias abaixo são piores que o bug do BPM:
    /// - `clip.set_transport` converte o clipe de Timeline (o padrão) para BPM
    ///   sync. O operador foi literal: BPM global ninguém usa, mas converter o
    ///   clipe "aí fodeu tudo" — ele sai do transporte em que o set roda e o
    ///   resto da noite fica torto.
    /// - `composition.open|new|save*` substituem ou gravam o estado do Arena. O
    ///   `.avc` é fotografia do estado atual, não "um projeto"; escrever por
    ///   cima é perder o show do operador, e Arena é intocável por decisão.
    /// - `batch` executa uma lista de operações quaisquer e o payload não é
    ///   inspecionável ação por ação — seria a porta dos fundos das duas acima.
    /// Nomes conferidos no `tools-schema.json` (Arena 7.28.0-rev24303 vivo).
    /// Um caso leva `chute:` no comentário: prefiro recusar demais a inventar
    /// comportamento do produto.
    static let neverActions: [String: Set<String>] = [
        "clip": ["set_transport", "clear", "clear_track", "merge", "eject"],
        "layer": ["delete", "clear", "clear_clips", "ungroup"],
        "group": ["delete", "clear"],
        "column": ["delete", "clear"],
        "deck": ["delete", "clear", "eject", "open"],
        "composition": ["open", "new", "save", "save_as", "grow", "eject", "undo", "redo"],
        "effect": ["remove", "clear"],
        // chute: `set` do autopilot entrega ao Arena a troca automática de
        // conteúdo. Com um bot no circuito, dois autômatos brigando pelo mesmo
        // crossfader não tem como dar certo.
        "autopilot": ["set"],
    ]

    /// Avaliação completa de uma chamada.
    public func decide(tool: String, arguments: [String: MCPValue]) -> Decision {
        let action = arguments["action"]?.stringValue
        let target = action.map { "\(tool).\($0)" } ?? tool
        // batch não tem enum de action: nunca passa, em modo nenhum.
        guard tool != "batch" else { return .never(target) }
        if let action, Self.neverActions[tool]?.contains(action) == true {
            return .never(target)
        }
        guard mode == .readOnly else { return .allow }
        guard let action else {
            // style/technique e companhia: ação é tema criativo, não leitura.
            return .readOnly(target)
        }
        if Self.safeActions[tool]?.contains(action) ?? false { return .allow }
        return .readOnly(target)
    }

    /// `true` quando a chamada pode rodar.
    public func allows(tool: String, arguments: [String: MCPValue]) -> Bool {
        decide(tool: tool, arguments: arguments) == .allow
    }

    /// Texto devolvido ao modelo quando bloqueamos. Precisa ser acionável: sem
    /// dica ele entra em loop tentando a mesma escrita. Também não pode mentir
    /// sobre o motivo — bloqueio no modo escrita não é "modo somente leitura".
    public static func refusal(tool: String, action: String?, alwaysBlocked: Bool = false) -> String {
        let alvo = action.map { "\(tool).\($0)" } ?? tool
        let motivo = alwaysBlocked
            ? "\(alvo) é proibida em qualquer modo: destrói ou re-temporiza o show"
            : "Modo somente leitura: \(alvo) alteraria o set"
        return """
        {"blocked":true,"reason":"\(motivo). \
        Responda a partir das ferramentas de leitura já chamadas (layer/composition/transport/status \
        com action get ou list) e peça confirmação explícita do operador antes de sugerir mudanças."}
        """
    }
}
