# Estado e Roadmap — ResoluxToolkit (2026-09-29)

Marcas: **(medido)** = verificado nesta máquina hoje; **(docs)** = documentado em HANDOFF/DÚVIDAS.

## 1. O que já está implementado

### Estrutura
- Monorepo com um `.xcodeproj` por OS: `Apps/macOS/ResoluxMac` e `Apps/iOS/ResoluxIOS`, plugados no workspace. **(medido)**
- Pacotes: `ResoluxCore` (puro), `ResoluxPlatform` (compartilhada), `ResoluxPlatformMac` (AppKit), `ResoluxPlatformiOS` (UIKit), `ResoluxDesignSystem` (peças MEVOLIT: Palette, Tone, Aurora, GlassCard, GlowButton, CapabilityBadge). **(medido)**
- Regra de arquitetura funcionando: divergência de plataforma por pacote separado, `#if os()` confinado à Platform. **(docs)**

### Feature Starter (macOS)
- `CapabilityReport` + catálogo de capacidades com badge por plataforma. **(medido)**
- UI Starter com Aurora/GlassCard: card de backup (contador de tempo), botão "Backup agora", card QR do Telegram. **(medido, não commitado)**
- `BackupService`: tar.gz de `~/.spike` + `~/.openclaw` → `~/Backups/Resolux/`, com timestamp em `last-backup.json`. **(medido, não commitado)**

### Feature Resolume (o produto)
- **Descoberta**: `ResolumeLocator` acha o binário/socket; Bonjour `_http._tcp` devolve "Resolume Arena 7.28.0 - Webserver & Rest API". **(medido)**
- **Sessão MCP stdio**: `MCPClient` (JSON-RPC), `ProcessMCPTransport`, timeout de 300 s, gate de prontidão pelo socket, `UnixSocketProbe` (servidor morto/mudo/órfão → falha legível). **(medido)**
- **Motor de chat**: `ChatEngine` com loop de ferramentas; `LocalChatBackend` com Apple FM (:1976) primeiro e Ollama (:11434) como rede de segurança — voto do operador em código + `BackendPreferenceTests`. **(medido)**
- **Resgate de tool call em texto** (`ToolCallTextRescue`) para o Apple FM, que não devolve `tool_calls` nativo. **(medido)**
- **Instruções e schema**: gate de instruções, `ToolSchemaNormalizer`, fixture das 22 ferramentas do Arena (`tools-schema.json`). **(medido)**
- **Política de escrita**: `ToolPolicy` read-only por default, deny-by-default; vetos permanentes em `clip.set_transport`, `composition.open/new/save*`, destruição de conteúdo e `batch`. **(medido)**
- **UI de chat macOS**: `ResolumeChatView` sem campos de API key, botão "Conectar ao Arena", aviso honesto "capenga" (10 de 22 ferramentas no Apple). **(medido)**
- **Diário de escrita**: `WriteJournal` (JSONL por sessão, só execução permitida, corte de 200 chars, espelho do valor anterior em `parameter`) injetado no `ChatEngine` com default `nil`. **(medido, não commitado)**
- **Chave Timeline/Performance**: `OperationMode` + `ModeGate` (Timeline calcula+monitora, Performance só monitora, recusa acionável). **(medido, não commitado)**
- **Calculadora de tempo**: `TimelineModel` (taxonomia de slots, delta time em ms, regimes de piloto transporte/segundos/batidas), `TimelineCalculator` (grade 9x3, rolo encadeado em bloco único, BPM), `ArenaREST` de leitura (:8080/api/v1, endpoint injetável). **(medido, não commitado)**
- **Monitor do Arena**: `ArenaMonitorView` read-only, poll de 1 s, grade + clipe ativo + contador — vitrine do set. **(medido, não commitado)**

### Qualidade
- Testes medidos hoje: Resolume **85** (84 verdes; 1 exige Arena aberto com REST — "depois de falhar dá para reconectar"), Starter 1, Core 2, Platform 1. **(medido)**
- `xcodebuild -scheme ResoluxMac` BUILD SUCCEEDED no último checkpoint registrado. **(docs)**

### Estado do git
- 6 commits; HEAD `454f53e`. Árvore com lote não commitado (journal, calculadora/REST, Monitor, Starter backup/QR) esperando aprovação no olho — plano §9 do HANDOFF. **(medido)**
- `.spike-remote/` é resíduo de sessão; não entra em commit.

## 2. Roadmap (ordem do HANDOFF §5, um item por tacada)

### Imediato
1. **Ver o humano↔bot funcionando no olho** antes de commit (pedido do operador).
2. **Despejar os lotes pendentes**: journal, calculadora/Timeline, Monitor, Starter — ordem do §9.
3. **Devolver entrada do chat na UI**: o `ContentView` atual (não commitado) mostra só Monitor + Starter; `ResolumeChatView` ficou sem host.
4. **Fechar votos pendentes** (DÚVIDAS): `autopilot.set` (veto permanente ou liberar no modo escrita); `parameter.set` genérico consegue virar `clip.type`?; posse da sessão do journal (DÚVIDAS §10.4).

### Curto prazo
5. **Plugar `ModeGate` no `ChatEngine`** — recusar cálculo quando o modo é Performance.
6. **UI "últimas mudanças"** lendo o journal, com cabeçalho honesto: *estas são nossas; o Cmd-Z do Arena não desfaz*.
7. **Tela completa do projeto**: transporte por clipe, relógio, saída por display (o Monitor cobre grade + ativo; falta o resto). Leitura pura; sem Ollama, sem mentira.
8. **Conectar automático vs botão** (DÚVIDAS §6) + Bonjour na descoberta, sem digitar IP.

### Médio prazo
9. **Telemetria do modo Performance**: módulo próprio de CPU/RAM/GPU (probes já calibrados em `/tmp`); limiar de aviso é voto do operador.
10. **Diagnóstico de barramento**: varredura de porta pelo protocolo, relatório nunca configuração (fim de projeto).

### Adiado / decisão
11. **PhotoLibrary**: ficou no planejamento (gateway + permission gate), nenhum código — retomar ou arquivar.
12. **iOS**: app é scaffold (só Haptics); Resolume é macOS-only — definir o papel do iOS.
13. **NDI (`libndi` 6.1.1 vs 6.3.2)**: só monitoramento, sem link, até haver pixel pra mover.
14. **DXV / Advanced Output**: conversão e presets — só leitura até nova regra (DÚVIDAS §2, §9, §8).
