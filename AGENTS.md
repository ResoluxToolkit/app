# ResoluxToolkit — fluxo de trabalho função a função

O trabalho segue o ciclo **um recurso por tacada**:

1. O operador pede uma alteração.
2. Você altera apenas o necessário para aquele recurso; nada de refatoração lateral.
3. Você verifica o menor escopo possível (teste focado, `swift test` do pacote ou build do app afetado).
4. Você registra a tacada em `docs/ITERACOES.md` com: pedido, arquivos, verificação, onde ver no app e status `aguardando revisão`.
5. Você para a execução e espera o operador aprovar, pedir ajuste ou escolher o próximo recurso.

No ciclo atual, a revisão do operador é sempre o próximo passo: build, abrir o app, aprovar/ajustar e só então pedir outra função. Se o pedido exigir mais de uma função/superfície, divida em tacadas e execute só a primeira; finalize dizendo exatamente onde ver a mudança e como buildar. O registro em `docs/ITERACOES.md` é append-only: atualize status sem apagar histórico.

# ResoluxToolkit — o que é

Swift monorepo (SwiftPM local packages + Xcode apps, Swift tools 6.0, floor macOS 15 / iOS 18) que dá suporte a um operador de VJ: chat com loop de ferramentas MCP controlando o Resolume Arena.

- `Packages/ResoluxCore` — puro, sem framework. Base de tudo.
- `Packages/ResoluxPlatform` — abstração compartilhada; depende só de Core.
- `Packages/ResoluxPlatformMac` (AppKit) / `ResoluxPlatformiOS` (UIKit) — divergência de plataforma é por pacote separado; `#if os()` fica confinado à Platform.
- `Packages/ResoluxDesignSystem` — peças MEVOLIT (Palette, Tone, Aurora, GlassCard, GlowButton, CapabilityBadge); depende só de Core.
- `Features/Starter` — utilitário (relatório de capacidades, backup); alvo duplo macOS+iOS, UI separada em `StarterUI`.
- `Features/Resolume` — **o produto**, macOS-only. Alvos `Resolume` (motor) e `ResolumeUI` (views); depende só de Core + DesignSystem.
- `Apps/macOS/ResoluxMac` e `Apps/iOS/ResoluxIOS` — apps finais plugados em `ResoluxToolkit.xcworkspace`; iOS é scaffold (Haptics), Resolume não roda nele.

# Verificação

- Pacote: `swift test --package-path Features/Resolume` (e idem para outros pacotes).
- App: build do workspace, scheme `ResoluxMac` (`xcodebuild` ou via Xcode).
- 1 teste do Resolume exige Arena aberto com REST; o resto roda offline.

# Regras de domínio (Resolume)

- Arena é imutável: nunca configurar/tocar na instalação ou preferências dele. `ArenaREST` e MCP são leitura pura por default.
- `ToolPolicy`: read-only e deny-by-default, com vetos permanentes (`clip.set_transport`, `composition.open/new/save*`, destruição, `batch`) — mexer nisso é voto do operador, ver `docs/DUVIDAS.md`.
- `OperationMode`/`ModeGate`: Timeline (calcula+monitora) vs Performance (só monitora, recusa acionável).
- Chat local apenas: `LocalChatBackend` usa Apple FM (:1976) primeiro, Ollama (:11434) como rede de segurança. Nunca nuvem, nunca download de modelo, nunca embutir weights. Apple FM não devolve `tool_calls` nativo — o resgate é o `ToolCallTextRescue`.
- `WriteJournal` registra toda escrita permitida em JSONL.

# Gotchas

- Os `.xcodeproj` usam o formato novo (`project.xcproj`), **não** existe `project.pbxproj` para editar.
- `ENABLE_APP_SANDBOX = NO` no app macOS é deliberado (precisa spawnar o processo MCP do Arena como filho). Não reativar.
- `.spike-remote/` é resíduo de sessão; nunca entra em commit.

# Identidade do agente (commits/PRs ≠ terminal do operador)

- Commits, pushes e `gh` do agente saem como `resolux-org`; o terminal do operador segue `Luiz Neto <lmoraes@me.com>` (git config do repo).
- Antes de commit, push ou `gh`, carregar: `set -a; source ~/.spike/resolux-org.env; set +a` — define autor/comitter `resolux-org`, a key SSH `~/.ssh/resolux_org_ed25519` e o `GH_TOKEN` dele.
- Nunca alterar `git config` global, trocar remote nem tocar nas preferências do Arena.
- Quando o teste exigir Arena REST, abrir o Arena antes de rodar (`/Applications/Resolume Arena/Arena.app`), leitura pura.

# Documentação (ler antes de mexer em área sensível)

- `docs/HANDOFF.md` — fonte de verdade do estado da sessão/projeto.
- `docs/DUVIDAS.md` — votos pendentes do operador; anote dúvidas novas lá, não pergunte no meio do trabalho.
- `docs/ESTADO-E-ROADMAP.md` — o que existe e a ordem do roadmap; pegue a próxima tacada de lá.
- `docs/ITERACOES.md` — registro de tacadas (append-only).

Marcas de confiança usadas nos docs: **(medido)** = observado nesta máquina, **(docs)** = documentado, **(chute)** = inferência, precisa veto.
