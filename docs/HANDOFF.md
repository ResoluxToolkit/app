# HANDOFF — ResoluxToolkit (estado frio, para retomar em chat novo)

> Este arquivo é a única fonte de verdade da sessão. Um assistente novo lê isto
> e continua sem precisar da conversa antiga. Se alguma linha aqui contrariar o
> operador, ele manda riscar — autoridade de domínio é dele, sempre.
>
> Como retomar: `swift test --package-path Features/Resolume`, depois
> `git status`. Nada está commitado (ver §1). Marcação: **(medido)** = observado
> nesta máquina; **(docs)** = documentação/catálogo; **(chute)** = inferência
> nossa, precisa veto.
>
> Dúvidas/posturas esperando voto dele ficam em `docs/DUVIDAS.md` — ele pediu pra
> **anotar** e não perguntar no meio do trabalho. Uma unidade de trabalho por tacada,
> depois pausar e ouvir.

## Decisão de direção (2026-10-06) — headless + web

- Operador aprovou migrar o produto para **motor headless (Swift) + cliente web**.
  Apps nativos (`ResoluxMac`/`ResoluxIOS`) e a UI SwiftUI ficam **aposentados como
  código ativo** — nada apagado nesta tacada. **(medido: conversa)**
- Ativo preservado: motor Swift puro (`Features/Resolume/Sources/Resolume`, 19
  arquivos sem import Apple, 85 testes). UI nova = página web vanilla servida pelo
  daemon. **(medido)**
- Arquitetura combinada: `ResoluxServer` (executável SwiftPM, porta `1980`) serve
  o estático + WebSocket do chat + **proxy read-only** `/arena/*` →
  `127.0.0.1:8080/api/v1` (resolve CORS sem tocar no Arena). Backend de chat
  default no web: Ollama (`qwen3:1.7b`, tool_calls nativo); `ToolCallTextRescue`
  fica só para o caminho Apple FM. **(docs)**
- Ideia de hospedar o HTML no webserver do Arena (`:8080`): **arquivada pelo
  operador** (exigiria tocar na pasta dele — viola a regra de imutabilidade).
- Próxima tacada (T37): spike `ResoluxServer` + `web/index.html` — wrapper do
  `ChatEngine` + `MCPClient` + `ToolPolicy`/`ModeGate`/`WriteJournal`, teste do
  proxy com mock injetável, validação no olho (Arena aberto + Ollama de pé,
  browser em `http://localhost:1980`), registro append-only em `ITERACOES.md`.
- Organização acordada: **conversas separadas** (motor Swift numa sessão, front
  web noutra), **mesmo repo** — a fronteira única é o contrato HTTP/WS do daemon.
- Contrato inicial v1 definido em `docs/API-CONTRATO.md`: daemon na `1980`,
  chat por WebSocket turno final, estado por HTTP e proxy read-only do Arena.
  Voto do operador (2026-10-06): fechar o cliente↔daemon em WebSocket; protocolos
  externos pendurados no adaptador do daemon, não no motor puro. Nada implementado.
- Voto do operador (2026-10-06): cliente Meteor; banco fora do workflow local.
  Supabase/Mongo não participam do turno, ficam só para auth/backup enviados pelo
  cliente em idle. Motor segue sem conhecer cliente nem nuvem.
- Nada implementado ainda da nova direção; lote pendente e estado do git (§1)
  continuam valendo.

## Requisitos do operador (2026-10-07) — homologação e mídia

- **Homologação da infraestrutura é gate, não relatório decorativo.** Antes de
  operar, o sistema audita o ambiente real: portas/protocolos, Arena/MCP, rede,
  áudio, recursos de máquina e capacidade estimada para o projeto (ex.: número
  de clipes). Falha crítica bloqueia o modo de operação; limitação aparece
  explicada e, se necessária, dá fallback. Ele não improvisa nem tem "vontade
  própria". O acesso/logon do evento é parte do checklist; sem isso, o fluxo
  não sobe. **(docs: conversa)**
- **Diagnóstico de operação continua passivo:** só leitura/observação, sem
  alterar estado e sem forçar carga no evento. Teste ativo de carga, se algum
  dia existir, é decisão separada do operador. **(docs: conversa)**
- **Porta do REST do Arena é observada, não presumida.** `8080` é default de
  fábrica, mas pode estar ocupada ou ter sido movida; nesta sessão `8008`
  respondeu. O preflight valida a porta configurada; ninguém mexe no Arena.
  **(medido: conversa)**
- **Front continua falando só o contrato do daemon** (`API-CONTRATO.md`). Cada
  fonte externa tem adaptador no daemon; motor puro não conhece Arena, NDI,
  RTC nem protocolo de fonte.
- **Vídeo ao vivo entre dispositivos entra numa camada RTC separada do controle.**
  Continuity Camera é uma fonte possivelmente exposta por essa camada; pixels
  não trafegam no caminho de chat/controle. Ainda sem implementação e sem
  escolha final de tecnologia (WebRTC/WHIP/NDI). **(docs: conversa)**

## 0. Votos recebidos (2026-09-27, checkpoint 5) e o que ainda espera
**Resolvidos por ele nesta tacada:**
- **Backend default -- RESPONDI DO MODO DELE:** *"Foundation Models de cara, se o
  malandro não configurou/não souber. Mas pelo menos ele não fica com nossa principal
  ferramenta sem funcionar."* Virou código: `LocalChatBackend.preferredOrder` põe Apple
  primeiro e Ollama como rede de segurança, com `BackendPreferenceTests` prendendo o
  voto. O custo (10 ferramentas, sem `layer`) ele aceitou, e a regra nova diz que a
  gente não esconde isso -- ver §6 "capenga".
- **Offline é restrição de produto, não melhoria:** *"tem um lugar que não vai ter
  internet... a gente ficar embutindo modelos aí de gigante a gente vai foder um
  software."* Traduzido em regra: preferência entre o que já está de pé na máquina.
  Nunca download de modelo, nunca nuvem, nunca embutir weight.
- **`libndi` 6.1.1 vs 6.3.2 -- ADIADO de propósito:** *"isso a gente não mexe, podemos
  monitorar em algum momento."* Nada é linkado ainda; quando houver pixel pra mover,
  isto vira item de monitoramento, não decisão antecipada. (DUVIDAS §8)

**Ainda esperam ele (2 itens, um nome por linha):**
1. **`autopilot.set` -- mantemos veto permanente ou libero no modo escrita?** Ele só
   citou o título do voto ("segurança do set") e não deu veredito. O veto está em
   `ToolPolicy.neverActions` e foi **chute meu**: dois autômatos (Arena e bot) no mesmo
   crossfader. É regra de VJ, minha opinião não vale. (DUVIDAS §7)
2. **`parameter.set` genérico consegue virar `clip.type`?** Se sim, meu veto do
   transporte está incompleto. Não testei porque testar é mexer no set dele. É palavra,
   não experimento. (DUVIDAS §7)

**Não está feito (não confundir com feito):** o *journal de escrita* -- nossa resposta
ao fato de que automação não entra no undo/redo do Arena -- foi projetado (§5 item 0) mas
**nenhum arquivo existe ainda**: não há `WriteJournal.swift` nem nada chamado journal/audit
no repo. Quem retomar começa por aí.

## 1. Estado verificado (re-medido 2026-09-27, checkpoint 7)
- `swift test --package-path Features/Resolume`: **85/85 passando** (re-medido no checkpoint 9: 69 do checkpoint 7 + 6 da régua do piloto + 7 de sincronia — relógio do clipe). Última medição: **0,48 s**.
  da grade/delta time + 1 dos endereços).. Duração da última medição: **0,5 s** -- e isso NÃO é a suíte
  ficando rápida: os testes vivos têm `.enabled(if:)` amarrado ao provedor real
  (`liveLoopThroughOllama` exige listener na 11434), e nem Ollama nem `fm serve`
  estavam de pé na medição. **Suíte completa com provedor vivo continua ~211 s.**
  Quer medir o loop de verdade: liga o Ollama e roda de novo; julgue pelo resultado,
  nunca pela duração.
- `xcodebuild -workspace ResoluxToolkit.xcworkspace -scheme ResoluxMac -configuration Debug`
  → **BUILD SUCCEEDED** já com o veto novo do §5 item 3. App em
  `~/Library/Developer/Xcode/DerivedData/ResoluxToolkit-*/Build/Products/Debug/ResoluxMac.app`.
- Git: HEAD `454f53e Update working tree` — os docs e todo o resto do checkpoint 5
  **já entraram** (o "nada commitado" do checkpoint 5 ficou desatualizado). Árvore
  agora = **5 modificados + 7 novos**: journal de escrita (§5 item 0) **e** a
  chave Timeline/Performance com a calculadora de linha (§5 item 0b).
  Modificados: `ChatEngine.swift`, `ToolPolicy.swift`, `MCPValue.swift`,
  `docs/HANDOFF.md`, `docs/DUVIDAS.md`. Novos: `WriteJournal.swift`,
  `WriteJournalTests.swift`, `OperationMode.swift`, `TimelineModel.swift`,
  `TimelineCalculator.swift`, `ArenaREST.swift`, `TimelineCalculatorTests.swift`.
  Nada commitado desde `454f53e`. Plano de lote no §9. Lote novo no §9
  — só com ordem dele. Ele quer ver funcionando no olho antes.
- Arena aberto, v7.28.0-rev24303. **Nunca matar o child MCP pertencente ao app
  dele.** Provedores locais de pé: `fm serve` :1976 (`system`,`pcc`) e Ollama
  :11434 (`qwen3:1.7b`, `qwen:0.5b`).
- **Duração por clipe só existe no REST `:8080/api/v1`**, não nas 22 tools MCP
  (varridas: nenhuma devolve duração). É a rota de leitura que ele mandou achar;
  `ArenaREST.swift` é leitura pura, sem escrita, sem tocar nas portas dele.
- O HUD de CPU/RAM/GPU/FPS do Arena **não é exportável**: não está no REST (258
  rotas do swagger varridas), nem no MCP, nem em strings do binário. No modo
  Performance medimos nós (`IOAccelerator` + `proc_pid_rusage`), calibrado contra
  o HUD dele -- detalhes e armadilha do mach tick em DUVIDAS §13.10.
- Disco sem problema. Memória persistente: **nada salvo** — só grava com a palavra
  "salva" dele. Dúvidas abertas ficam em `docs/DUVIDAS.md` (ele pediu pra anotar,
  não pra perguntar no meio do trabalho).
## 2. Regras do operador (valem acima de qualquer decisão técnica)
- **Um operador por vez, quem chega primeiro trava.** Palavra dele (2026-09-27, tarde):
  *"O operador que entrar primeiro trava a sessão. Nunca mais de uma pessoa mandando
  comandos."* Duas topologias que o produto serve, ele mesmo desenhadas:
  1. **Mac**: Humano ↔ IA ↔ MCP ↔ Arena — tudo local.
  2. **iOS**: Humano (remoto) ↔ WAN ↔ IA ↔ MCP ↔ Arena.
  Consequência que aceito como projeto, não como detalhe: escrita precisa de **posse
  única** antes de acontecer. Não é UI ("mostra quem está"), é gate — segunda mão não
  manda comando, e isso vale tanto pro celular quanto pro segundo Mac aberto na mesma
  máquina. Quem decide posse não pode ser o `ChatEngine` (ele morre no "Desconectar");
  tem que ser estado visto pelos dois lados.
  **Refinamento dele (checkpoint 6):** o sistema é monousuário por construção — quem
  "montou" o evento é o super admin, e só esse readquire a posse na reconexão. Mas
  ele vetou preempção: *"não pode sair derrubando quem estiver, tem que ter uma janela
  em que seja seguro isso acontecer."* Então readquirir é **pedido com efeito no
  próximo momento seguro**, não corte imediato.
  **A janela é declarada, não derivada (checkpoint 6):** palavra dele — *"na hora do
  Hino Nacional, trocar de operador, nem fudendo."* Ou seja: existem **blocos críticos**
  no evento, declarados por quem montou, e dentro deles nada muda, sem override
  possível. Estado calmo do Arena (`crossfader {get}`, `transport {get}`) é condição
  necessária, nunca suficiente: quieto e todo-mundo-olhando é justamente o pior caso.
  Detalhe operacional que ele precisa votar: em evento ao vivo horário escrito atrasa,
  então bloco crítico se **arma na mão**; agenda serve de lembrete, não de gatilho.
  Teto de espera continua aberto. Tudo em DUVIDAS §10.
- **Criticalidade vem de fora, nunca do Arena (checkpoint 6, DUVIDAS §11):** não existe
  bit no Arena que diga "isso é crítico"; é propriedade do **evento**. O gate vai ler
  um provedor de criticalidade, cuja implementação hoje é manual (armar/desarmar) e
  amanhã é o **roteiro/rundown** — o mesmo artefato do historyboard que ele quer fazer
  depois. Por isso o gate não conhece roteiro: se nascer amarrado no relógio, quando ele
  chegar eu reescrevo a peça que mais pede confiança. Custos dessa costura e as três
  perguntas restantes (onde o roteiro vive, manual-antes-do-roteiro, binário vs graduado)
  em DUVIDAS §11.
- **Três travas de formato já saem certas hoje (checkpoint 6, DUVIDAS §12).** Ele corrigiu
  duas coisas minhas, e viraram requisito de código, não comentário:
  - *"Isso me lembrou da parte de sync."* Aqui **"relógio" tem dois sentidos** e é onde o
    sync morde: horário do dia (Hino às 18:00 — o gate **não** pode usar, atrasa) vs relógio
    do Arena (transporte/BPM/posição; cada clipe tem seu `clip.type`, daí o system prompt já
    exigir declarar a fonte antes de citar BPM). Em compensação, o `tools/list` do Arena traz
    `create_ltc_timecode_bridge`, `sync_timecode`, `connect_lighting_console_osc` — se a venue
    alimentar **LTC/timecode**, existe um relógio externo confiável (vem do equipamento, não
    da parede nem do BPM). Aí hora no roteiro vira referência visual com marcador ancorado em
    LTC. Gate continua lendo o bloco declarado; LTC corrobora, nunca decide. Esperando ele
    dizer se alguma venue entrega LTC/lightboard com cue por timecode — define se o formato
    nasce com campo de tempo ou sem tempo nenhum.
  - *"DIA? — chega um minuto antes, a última alteração."* Rido merecido: roteiro **muda no
    último minuto com o show correndo**. Então: (a) arquivo **lido quente**, sem snapshot
    eterno e sem restart — se precisar reiniciar pra valer a mudança, o recurso é lixo no dia
    do show; (b) bloco corrente referenciado por **ID estável, nunca por posição** — guardar
    "bloco 3" quer dizer que inserir um bloco às 17:59 pode tirar o evento do estado crítico
    **em silêncio**; (c) editar o rundown **nunca** desarma nem re-escolhe nada sozinho.
    Journal registra ID de bloco, não índice. E como se edita fora do app (ele no console,
    outro no notebook), "arquivo nosso editável por fora" subiu de preferência para requisito.
  **Nenhum código de lock existe ainda** — procurado: só há `NSLock` dentro do
  `ProcessMCPTransport`, que protege fila de requisição de um único processo, não
  identidade de operador. **(medido)**
- **Arena é imutável.** Nada do que vem de fábrica se altera: Preferences, Wire,
  config de OSC/REST/MIDI. A gente se adapta ao que ele entrega, porque "ninguém
  sabe mexer nesse tipo de coisa". Operar o set ao vivo pode (quando ele armar);
  configurar o app nunca.
- **Portas padrão do Arena nunca mudam:** `8080` REST, `7000` OSC in, `7001` OSC
  out. Quem precisa de outro número somos nós.
- **Rede sandboxed.** Nada bindado em `*` disputando infra de venue. Endereço
  fixo + faixa negociada por local. Nunca inventar superfície TCP nossa.
- **Zero campo de configuração.** Abrir Arena + abrir nosso app = anda. No limite,
  um IP — e Bonjour elimina até isso (§5).
- **Toolkit, não app: convenção sobre configuração.** Somos conjunto de ferramentas
  e integrações, então integramos os padrões que já estão no barramento -- OSC
  position na 7001, REST na 8080, Art-Net na 6454, LTC/MTC como vieram de fábrica,
  porta padrão de cada programa -- em vez de inventar protocolo ou formato próprio.
  Consequência prática para o `.tox` nosso: ele já sai com as portas trocadas, o
  operador não mexe em parâmetro de nó nem digita nada.
- **Autoridade de domínio é dele.** Chute sai prefixado `chute:` e ele veta em uma
  linha. Não se inventa regra de VJ, schema de console nem "padrão de mercado".
- **Ritmo:** uma unidade de trabalho por vez (~5–10 min), depois pausar e ouvir.
  "para"/"pausa" no meio = termina só o comando rodando e fica quieto.
- **Nunca ligar pro iPhone dele** (`iphone.local:11434`) sem avisar antes —
  inferência custa caro pra ele.
- **"O que não der pra fazer, a gente explica."** Regra de produto dele, com as
  palavras dele, e ele chamou o formato de **"onboarding" de recursos**. Então quando a
  API não cobre algo (ex.: `Render To File` por clipe, Collect Media), a gente **não**
  automatiza na marra, não simula, não esconde: a nossa tela diz o que o Arena faz
  sozinho, onde isso fica na interface dele, e por que aquilo é dele. Isso casa com o
  que já medimos -- `file { action: "info" }` devolve o diagnóstico pronto ("Transcode
  to DXV with Resolume Alley") -- então a gente mostra a frase deles, nunca uma
  promessa nossa. Corolário: **falta de cobertura não é defeito nosso**, é conteúdo de
  onboarding.

## 3. Produto: quem faz o quê
- **Nosso:** descobrir Arena (Bonjour/locator), ler o set via MCP por stdio (zero
  porta), política de escrita, relógio com lock, diagnóstico de barramento, UI que
  soma o projeto.
- **TouchDesigner (nossa ponte única):** execução — render/3D/**NDI** (não Syphon;
  ver o bloco de vídeo no §4), LTC (`ltcoutCHOP` → `audiodeviceoutCHOP`, cadeia que
  ele comprovou em screenshot), MTC (`midioutCHOP` com "Send MIDI Timecode", nativo
  **(docs)**), OSC de luz.
- **tdmcp** (`/tmp/tdmcp-audit/repo`): ponte WebServer DAT em `127.0.0.1:9980`
  (loopback), 509 ferramentas, `TDMCP_TOOL_PROFILE=safe|directory|full`. Já tem
  `create_ltc_timecode_bridge`, `sync_timecode`, `connect_lighting_console_osc`
  (com `dry_run|approval_required`). lacuna real = lock/drift entre correções é só
  texto de aviso. É aí que nosso valor mora.
- **Nenhum DAW no desenho.** Reaper/QLab não são peça nossa (decisão dele).
- `.tox` nasce dentro do TD e só podemos gravar por API dele -- nunca escrevendo
  bytes no formato. **Correção:** o nome `comp.saveBinaryFile` que estava aqui é
  inventado meu, não existe na doc. Confirmado em doc string do app: existe
  `saveExternalToxs` (salva de volta o `.tox` referenciado por um COMP). Checar o
  nome verdadeiro em `COMP_Class.htm`, na doc offline local (§10), quando formos
  implementar -- e para por aí: o operador mandou não cavar fundo no formato.
  Plano igual: versionar o builder Python + TD de quarentena exportando o binário.
  Projeto aberto dele não se abre.

## 4. Medido nesta máquina (não é crença)
- **OSC do Arena** (`127.0.0.1:7001`): 278 e depois 299 pacotes/s em janelas de
  3 s. Só dois endereços, ~140 Hz cada:
  `/composition/layers/1/clips/1/transport/position` e
  `/composition/selectedclip/transport/position`. Antes de medi-lo, **ninguém**
  escutava a 7001 — ele fala com ele mesmo, a mesa não recebe nada hoje. A taxa
  segue o cook, não é tick estável.
- **Arena publica só camada 1/clip 1 e o clip selecionado.** Escolher outra camada
  seria mexer nele; consumimos o que sai.
- **Arena escuta `UDP *:7000`** e segura ainda `*:6454` (Art-Net, com
  `libArtnet.dylib` embutido: `artnet_get_config`, `artnet_add_rdm_device`),
  `*:8005`, `*:10669`, `*:60000/60001` e afins. Saída de OSC hoje mira `localhost`.
- **Webserver/REST dele:** TCP `*:8080` com `Listen Address 0.0.0.0` — vazamento
  concreto na LAN do venue (config dele; a gente não resolve mexendo nele).
- **libLTC dentro do Arena** (`ltc_encoder_create`, `ltc_decoder_read`, ...) e duas
  entradas SMPTE nativas com framerate e compensação de delay em frames **(docs)**.
  Perdeu prioridade: escravizar o Arena a timecode externo exige configurar o app.
- **Bonjour:** `_http._tcp.local.` devolveu `Resolume Arena 7.28.0 - Webserver &
  Rest API`; multicast ativo no `en0`. `_oscquery._tcp` e `_NDI._tcp`: zero
  anúncios aqui. Descoberta existe sem digitar IP.
- **Portas do TD: o operador estava certo e meu chute morreu.** Re-medido, ele
  segura `UDP *:10000` -- a família 10.000 é dele mesmo. Meu `chute:` de que o
  WebServer DAT usa `8080` está **errado**: o default do bridge é `9980`, e a porta
  vive num PAR custom chamado `Bridgeport` no COMP da ponte
  (`/tmp/tdmcp-audit/repo/td/modules/mcp/install.py:782`) -- ou seja, mudar na mão
  é editar um PAR, exatamente o plano provisório dele. `9000`, `9001`, `1000` e
  `8080`(REST do Arena) conferidas: as três primeiras livres aqui. **(medido)**
- **Ouro dentro do app do TD, local:** `Contents/Resources/tfs/Samples/Learn/
  OfflineHelp/https.docs.derivative.ca/` é a documentação oficial offline (2088
  `.htm`, com `COMP_Class.htm` etc.) e há 796 `.tox` de exemplo, inclusive snippets
  de um nó só. Consultar isso antes de chutar nome de API. Limite posto pelo
  operador: parar antes de mexer no formato binário de `.tox` -- olhar conteúdo de
  arquivo compactado/criptografado é ir fundo demais. **(medido)**
- **Backend local (re-medido 2026-09-27, três afirmações minhas antigas caíram):**
  - `fm serve` (`127.0.0.1:1976`, OpenAI-compatível): **defaulta SSE**
    (`Content-Type: text/event-stream`). Com `stream:false` no body ele devolve
    JSON puro e HTTP 200 -- pedido explicitamente em `ChatCompletionRequest.stream`.
  - Aceita `tools` e devolve a chamada como **texto** num bloco ```json com
    `finish_reason: "stop"`. Isso mata o loop silenciosamente (o turno acaba sem
    rodar nada) -- fechado por `ToolCallTextRescue`, que só aceita nome presente
    em `tools/list`.
  - **Rejeita o `inputSchema` cru do Arena com HTTP 400.** Não é tamanho: uma
    ferramenta só já caía. Quatro construtos, cada um suficiente sozinho: união de
    tipo (`"type": ["string","null"]`), nó com `anyOf`/`oneOf`,
    `additionalProperties: {}` vazio, propriedade de objeto sem `type`. Metadado
    (`$schema`, `title`, `format`, `default`) ele engole -- nada disso é descartado
    em `ToolSchemaNormalizer`. Nas 22 ferramentas: 21 propriedades eram união de
    tipo e uma (`parameter.value`) não tinha tipo algum.
  - **Janela de contexto curta, e é o limitador real.** Custo de prompt por
    ferramenta, normalizada, tokens: diagnose 343, status 346, transport 413,
    crossfader 429, file 453, color_code 552, deck 553, catalog 617, technique 636,
    transition 693, style 739, group 703, autopilot 740, column 751,
    composition 836, batch 884, transform 911, monitor 984, layer 1075,
    effect 1095, parameter 1580, clip 2098 -- soma ~17,4k. Teto entre 2,3k
    (10 ferramentas, 200) e 3,1k (12 ferramentas, 500). Encurtar descrição não
    ajuda: cortada a zero continua 500 -- quem come a janela é o JSON Schema.
  - **Ollama (`qwen3:1.7b`, :11434): eu errei ao dizer "zero tool_calls".** Ele
    emite `tool_calls` no campo nativo sim, com `finish_reason: "tool_calls"` --
    é **não-determinístico** (tem `reasoning`), e numa amostra veio vazio. Aceita
    o schema **cru e** o normalizado, então normalizar sempre é seguro e dispensa
    detecção de fornecedor. É o backend do loop vivo de referência
    (`liveLoopThroughOllama`, ~2 min por turno num modelo de 2B).
  - Consequência de design que se mantém (§6): JSON guiado parseado por nós, uma
    ferramenta por turno, recusa é nossa.
- **Escada real do fm com o system prompt do engine e `stream:false`** (medido, não
  estimativa): passa com HTTP 200 até **10 ferramentas** = 3.986 tokens de prompt
  (`diagnose`, `status`, `transport`, `deck`, `column`, `catalog`, `composition`,
  `group`, `crossfader`, `color_code`). Em 11 cai **HTTP 500** "transcript exceeded
  the model's context size". Subconjunto congelado em
  `LocalChatBackend.appleToolSubset`. Consequência dura a dizer sem rodeio:
  "quantas camadas tem?" é **inrespondível pelo Apple**, porque `layer` não cabe —
  e `effect` também não. **(medido)**
- **Teto de tempo do `URLSession.shared`: 60 s.** Um turno fm real leva ~118 s, e
  era exatamente o `-1001` que derrubava `liveLoopThroughOllama`. Não é network
  problem, é ceiling de API. **(medido)**
- **Arena em macOS já é Metal por baixo, com Vulkan só na fachada (medido no disco,
  não em doc):** o binário linka `OpenGL.framework` **e**
  `@executable_path/../../../libvulkan.1.dylib`, que é o **loader do LunarG** — os
  strings têm `VK_LAYER_LUNARG_override`, `VK_LUNARG_direct_driver_loading` e as
  extensões de surface Metal (`VK_EXT_metal_surface`, `vkCreateMetalSurfaceEXT`,
  `vkExportMetalObjectsEXT`). O driver vem junto no bundle:
  `/Applications/Resolume Arena/Arena.app/Contents/lib/libMoltenVK.dylib` +
  `Contents/Resources/vulkan/icd.d/MoltenVK_icd.json` + `Licenses/moltenvk.md`. Ou
  seja, Vulkan → MoltenVK → Metal, tudo dentro do próprio pacote dele, sem
  dependência do sistema. Consequência: escolher Metal não nos põe em rota
  alternativa nenhuma, é o mesmo driver que o Arena já pisa nesta máquina. **(medido)**
  Também por isso **não** existe motivo técnico pra embutir Vulkan/MoltenVK nosso:
  nada que a gente escreva hoje desenha pixel, e carregar um stack de GPU só pra
  "ficar igual" seria a exceção que quebra o convenção-sobre-configuração.
- **Vídeo entre nós e o TouchDesigner: NDI é o caminho, e com a versão casada com a
  do Arena (regra dele, e ela tem razão de ser medida).** Números desta máquina:
  - Arena **embarca** o NDI próprio: `@executable_path/../../../libndi.dylib`, com
    string interna `NDI SDK APPLE 09:14:54 Dec 20 2024 **6.1.1**` (Mach-O
    `current version 5.0.0`, que não é a versão do SDK — é ABI do pacote). Ele não
    usa o NDI do sistema, usa o dele. **(medido)**
  - Runtime instalado aqui é **mais novo**: apps NDI (Access Manager, Router, Scan
    Converter, Video Monitor, Virtual Input) todos **6.3.2 / build 260413**, e
    `/Library/NDI SDK for Apple/Version.txt` = `NDI 2026-04-13 git-5396c5f1
    **v6.3.2.0**`. O SDK completo está em `/Library/NDI SDK for Apple`
    (`include/Processing.NDI.Lib.h`, `lib/macOS/libndi.dylib`). **(medido)**
  - Isso abre a pergunta que precisa do voto dele antes de qualquer código:
    **linkamos contra o `libndi` de dentro do Arena (6.1.1) ou contra o SDK
    instalado (6.3.2)?** Minha leitura: casar com o do Arena é o que obedece a regra
    "sempre na mesma versão do Arena", mas o caminho vive dentro do `.app` deles e
    pode mudar a qualquer release -- o que pesa contra. Ficou registrado como item
    novo no `docs/DUVIDAS.md`.
- **Procedência do SDK (fechou o buraco do download):** o operador baixou o
  instalador e jogou no repo: `Install_NDI_SDK_v6_Apple.pkg`, 225 MB. O download
  **exige cadastro** em `ndi.video`/`docs.ndi.video` -- ou seja, não é coisa que se
  rebaixe numa formatação. Por isso saí de dentro do repo (binário de 225 MB não vai
  pra commit) e ficou em `~/Developer/vendor/Install_NDI_SDK_v6_Apple.pkg`, com cópia
  de backup em `Meu Drive/BKP/` (Drive em streaming, a cópia grava bytes -- é isso que
  queremos aqui). Conferido de dentro do próprio `.pkg`: `Version.txt` =
  **v6.3.2.0**, igual ao que já está instalado nesta máquina. Bônus que importa pra
  distribuição futura: o payload traz `NDI SDK for Apple/redist/libNDI_for_Mac.pkg`,
  o runtime redistribuível -- é isso que um instalador nosso vai levar se o cliente não
  tiver NDI. Ferramentas de teste ficaram em `/Applications/NDI*` (Test Patterns,
  Launcher, Scan Converter, Router, Video Monitor, Virtual Input, Discovery, Access
  Manager), todas **6.3.2**. O voto do item 8 continua de pé: instalar casou 6.3.2,
  mas o Arena ainda embute 6.1.1. HD: o operador pediu pra não me preocupar *tanto*
  com HDR nesta fase.
- **Backup do pkg pelo mount falhou como backup — combinado novo.** Tentei copiar pro
  `Meu Drive/BKP/` via FileProvider e o arquivo ficou **truncado em 10 MiB com SHA
  diferente** do original (`1535e276…`); removi a cópia ruim, a fonte em
  `~/Developer/vendor/` segue íntegra. Lição dura: num mount em streaming, `cp` que
  retorna != bytes confirmados no servidor. O MCP `gdrive` desta sessão está sem auth
  ("Auth required"), então não consegui validar pelo lado do servidor. **Ficou
  combinado com o operador: eu produzo os pacotes, ele sobe.** Ou seja, backup de
  binário grande pelo Drive é trabalho dele, não meu. **(medido)**

### Eixo novo: o relógio de cada clipe vem escrito no payload (checkpoint 9)
- `transporttype` aparece **73x** em `/tmp/comp2.json`, `ParamChoice`, e o payload entrega
  `options` inteira: `["Timeline","BPM Sync","SMPTE 1","SMPTE 2","Denon DJ","Pioneer DJ"]` -- idêntica
  ao dropdown fotografado por ele, na mesma ordem. `value` das 73 = `"Timeline"`, `index = 0`
  (= fábrica, confirmado por Preferences → Defaults nas capturas dele). Contrato `RelogioDoClipe`
  validado por round-trip em teste, não por chute.
- `playmode` aparece **14x** (só nos clipes com `transport`), `options =
  ["Loop","Bounce","Random","Play Once & Clear","Play Once & Hold"]`, `value` das 14 = `"Loop"`.
  Ponto verde na foto dele estava em `Play Once & Clear` ("acabou, morreu"). Nenhum código de soma
  depende disso ainda -- registrado, com dúvida aberta em DUVIDAS §14.2.
- `duration_type` tem **três vocabulários diferentes por nível** (camada
  `Clip Transport|Beats|Seconds`; clipe `Layer Determined|Transport|Beats|Seconds`; composição inclui
  `Longest Clip`). Por isso virou enum `RegimeDePiloto`, não string.
- BPM mora em `composition.tempocontroller.tempo` (`ParamRange 20...500`, hoje 120) -- campo que
  **não existia** na nossa leitura anterior, e sem ele o regime `Beats` não vira tempo. Sem BPM
  devolvemos `.nenhuma`; nunca chutamos 120.
- Swagger deles (<http://192.168.0.104:8080/api/docs/example/>) agrupa **por objeto** (11 tags /
  258 paths), **não por janela** -- a "janela escondida" que ele procurou não existe na doc. Zero
  ocorrências de "timecode" nas 258 rotas. O exemplo oficial deles é SPA React cujo bundle
  (`/tmp/exmain.js`, 170 KB) usa **WebSocket + `subscribe` + `parameter/by-id`** sobre a mesma porta
  — é o canhão de referência pra assinatura em tempo real (OSC já dá playhead a ~50 Hz sem tocar em
  config nenhum).


### Formato de vídeo: DXV3 e ponto (decisão do operador)
- Verbatim dele: *"Cara, É DXV3 e ponto!"* e *"DXV é o formato proprietário deles."*
  Registro como regra, não como sugestão: **o formato de material do nosso ecossistema
  é DXV3.** Isso é o que o VenueTalks/DXV codec da Vizrt alimenta direto no Arena.
  (A frase sobre VenueTalks/Vizrt era enfeite meu, sem medição -- o que temos é o
  `Resolume DXV Codec 3.0.1 Installer.pkg`, 6 MB, montado dum DMG de ago/2024; o
  payload instala `./Library/QuickLook/ResolumeQuickLook.qlgenerator` e afins, i.e.
  é codec de sistema/QuickLook pra ferramentas fora do Arena, não um pré-requisito do
  Arena. Guardei junto do NDI em `~/Developer/vendor/`.)
  **(medido no bundle dele)** o Arena traz compressor/decompressor próprios:
  `N2ra14DXV3CompressorE`, `N2ra16DXV3DecompressorE`, `N2rj18ConversionSettings4DXV3E`
  no binário, e os quatro presets de gravação nativos em
  `default/Presets/Render and Record/DXV 3 {High,Normal} Quality {With,No} Alpha.xml`.
  Nada disso precisa de codec instalado no sistema — `/Library/QuickTime` está vazio de
  DXV e não vamos mexer ali.
- **Eu errei, e o erro era justamente o que ele proibiu: inventei.** Escrevi acima
  que "a cadeia TD->Arena DXV exige um passo de conversão que hoje não existe". Não
  existe *no TouchDesigner*, verdade -- mas a conversão **existe no Arena e ele já
  deixou configurada**. Verbatim dele: *"Na API do Arena tem como jogar os MP4 pra
  conversão, não precisamos ter isso."* Medido no arquivo dele,
  `~/Documents/Resolume Arena/Preferences/config.xml`: tanto `<RecordSettings>` quanto
  `<RenderSettings>` trazem `<Conversion Codec="DXV 3" Format="Normal Quality, With
  Alpha" AutoSize="Fit" AudioEnabled="1" SampleRate="44100" BitDepth="16">`. E o
  binário tem os compressores `N2ra14DXV3CompressorE`, `N2ra14DXV4CompressorE` e
  `N2ra22VideoToolboxCompressorE`. **(medido)** Regra registrada: **quem converte é o
  Arena. Nós nunca escrevemos conversor, nem encodamos codec no nosso código.** É o
  caso mais limpo de "a gente não implementa, a gente integra".
- Mapa de codecs medido nos dois binários, porque ele define pra onde o pixel pode
  ir: Arena comprime **DXV3, DXV4, VideoToolbox**; descomprime **HAP, DXV3, DXV4,
  TJPEG, VideoToolbox**. TD não tem codec DXV nenhum e o `libavcodec` que ele embarca
  foi compilado com `--enable-encoder=hap --enable-decoder=hap` e **zero** dxv na
  linha de configure (ele confirmou: *"o ffmpeg TINHA DXV, limaram"*; e *"O Lance deles
  é o HAP"*). Consequência útil: **HAP é o único codec de arquivo que TD escreve e o
  Arena lê sem ninguém converter nada** -- só que é mão dupla torta, o Arena só *lê*
  HAP, nunca escreve. Então a partição fica: ao vivo TD->Arena = **NDI**; arquivo que
  o Arena consome nativamente = **DXV3** (nato); HAP só se um dia precisar de arquivo
  entre TD e Arena sem passar pelo Arena. Nada disso vira código agora.
- Onde a API **não** cobre (medido, pra não prometer o que não existe): as 22
  ferramentas do servidor MCP oficial (`/Applications/Resolume Arena/mcp/
  resolume_arena_mcp_server`, `.mcpb` manifest `version 7.28.0`, "Requires Resolume
  Arena 7.26+") não têm nenhuma tool de conversão/import de mídia -- a única que
  encosta em arquivo é `file` com actions `browse|info|loaded`. Sondando a REST viva
  em `:8080`, `/api/v1/media`, `/api/v1/media/convert`, `/api/v1/convert`,
  `/api/v1/files`, `/api/v1/library`: todos **404**. Ou seja, a conversa que ele
  descreveu é real mas mora na interface (arrastar MP4 / Render), não num endpoint
  nosso. Ficou como item novo no `docs/DUVIDAS.md`.
- **A API já faz o diagnostico de codec sozinha -- e e isso que a gente mostra, nao o
  Media Manager.** Medido rodando o servidor MCP oficial em stdio com o handshake de
  instrucoes e depois `file { action: "info", path: ... }` num MP4 real dele
  (`~/Movies/FACE-IT.mp4`, 1080x1080, 25 fps, 13200 frames, 646 Kbps):
  ```
  Codec: H.264
  Performance: Slow codec (H.264). May drop frames at high resolution.
               Transcode to DXV with Resolume Alley for best performance.
  ```
  **(medido)** Isso e exatamente a coluna *Compression* da screenshot que ele mostrou
  (`Unknown` vs `DXV 3.0 Normal Quality, No Alpha`), so que legivel por maquina e sem
  abrir janela nenhuma. Ou seja: a nossa tela de saude do set le `file info` e nao
  precisa do Media Manager. Confirmado tambem que `file { action: "loaded" }` responde
  "No files loaded" na composicao vazia dele, e que o servidor **exige**
  `status { action: "instructions" }` antes de qualquer outra tool (sem isso devolve
  `isError`). Nosso `MCPClient` ja trata esse gate (lines com `instructionsAcknowledged`
  e o detector "must read server instructions") -- nada a fazer aqui. Texto oficial das
  instrucoes arquivado em `docs/fixtures/arena-mcp-instructions.txt` (6.922 chars).
- **`Resolume Alley` esta instalado aqui** (`/Applications/Resolume Alley`, versao
  7.14.0-rev20492). E o transcoder autonomo da casa, e a API manda a gente pra ele.
  Os presets sao o vocabulario de saida que importa pra nos:
  `default/Presets/{DXV High|Normal Quality With|No Alpha, ProRes 422 HQ|NQ, ProRes
  4444, Motion JPEG, H264 Low|Medium|High}.xml`. O XML de preset e o mesmo objeto
  `Conversion` do `config.xml` do Arena (mesmo `className="Conversion"`, mesmos
  atributos) -- mais um motivo pra nao reinventar formato. **(medido)**
- Duas coisas que ele precisa saber sobre o Alley antes de a gente contar com ele:
  1. **Nao achei CLI.** O binario nao expoe flags de linha de comando utilizaveis, e o
     `Info.plist` o declara como app de documento (papeis Viewer/Editor, UTType
     "dxv document"). Chutar um modo batch seria inventar de novo. Entao conversao
     automatizada pelo Alley = abrir GUI = nao e "zero configuracao" pro operator.
  2. **O `libndi` do Alley e 6.1.1**, string `NDI SDK APPLE 09:14:54 Dec 20 2024 6.1.1`
     -- identico ao do Arena. Ja o runtime instalado no sistema e 6.3.2. Isso e
     evidencia a favor da tua regra ("NDI sempre na mesma versao do Arena"): o ecossistema
     inteiro deles embarca 6.1.1 proprio. Alimenta o voto do item 8.
- Consequencia que fecha o raciocinio do formato: **nossa parte e diagnosticar e
  apontar; converter e do Arena (Record/Render, ja configurado no `config.xml` dele) ou
  do Alley.** Nada de encoder nosso, nada de licenca de codec no nosso binario.
- **`Render To File` por clipe -- o caminho que so quem conhece o Arena a 25 anos
  conhece.** Ensino dele, com screenshot: botao direito **em cima do clipe ja na
  composicao** -> o menu traz `Clear / Create Blank / Show in Finder / Show in File
  Browser / Strip Video / Strip Audio / Snapshot (Y%P) / Render To File / New Source /
  New Effect`. Isso converte aquele clipe ali, sem tocar na composicao inteira e sem
  abrir Media Manager -- e a saida elegante pro nosso problema de formato: o operator
  converte o que quer, quando quer, sem a gente automatizar nada. Detalhe que ele fez
  questao de dar: **a aba `Render` nao existe na View default.** Pra ver onde cai o
  resultado tem que habilitar `Show Render` no seletor de paineis (la ao lado de
  `Show Files`, `Show Record`, `Show Slices`, `Show Sources`). Se a gente nao souber
  disso, "nao funciona" seria falso alarme nosso. E la dentro o Preset e exatamente a
  lista que medimos nos arquivos: DXV 3 {High,Normal} Quality {With,No} Alpha, H264
  {Low,Medium,High}, Motion JPEG, ProRes 422 {HQ,NQ}, ProRes 4444. **(medido nos
  presets + screenshot dele)** Confirma por outra ponta a decisao de formato: a propria
  lista do Arena comeca em DXV 3.
  Onde cai o arquivo: `<RenderSettings><Conversion><OutputPath Type="2" Path=""/>` no
  `config.xml` dele -- `Type=2` com `Path` vazio, i.e. padrao da casa. O padrao fisico e
  `~/Documents/Resolume Arena/Renders/` (hoje vazio, igual ao `Recorded/`). Nao vou
  chutar o que os numeros de `Type` significam: campo deles, nao mexemos.
- Cobertura de API pra isso e **zero, e agora sei que e zero de verdade.** Varri o
  servidor MCP oficial atras de `render_to_file`/`renderToFile`/rota de render: nada. As
  22 tools nao tem render nenhum -- `clip` tem 23 actions e nenhuma de export
  (`open,get,list,trigger,eject,select,rename,copy,move,swap,merge,clear,clear_track,
  set_size,find,thumbnail*,dashboard_get,get_transport,set_transport`), `composition` só
  faz `save`/`save_as`/`new`/`undo`/`redo`, e o unico snapshot existente e do
  `monitor { action: "snapshot" }` -- imagem de monitor, nao arquivo de video. No
  binario do Arena tambem nao apareceu `/api/v1/...render...`. Entao `Render To File`
  e **GUI pura**, e cai na regra nova do onboarding (§2): a gente explica onde fica e
  porque e dele, nao simula clique nem inventa endpoint.
- O Media Manager que ele mostrou é outra face do mesmo ponto: reconectar arquivos
  perdidos, `Set Path` pra trocar arquivo, e **Collect Media** -- que copia tudo pra
  uma pasta `Media/` com subpasta por deck e regrava a composição apontando pra lá
  (documento oficial que ele linkou: `resolume.com/support/en/media-manager`; e ele:
  *"não sei se dá pra interagir mas aí que a gente faz o Collect"*). A screenshot dele
  fecha o raciocínio: coluna *Compression* distinguindo os `.mov` vermelhos
  (`Unknown`, sumidos de `Resolume Avenue 6/media/Shop/`) dos que já são
  `DXV 3.0 Normal Quality, No Alpha` -- é ali que a gente leria a saúde do set.
  **Não rola** fazer Collect pela API: é GUI, sempre salva a composição antes, e o
  Arena "nunca apaga" os arquivos dele -- mexer nisso sem permissão seria exatamente
  tocar no set de gente casca-grossa.
- **O porquê de DXV3 não ser capricho -- explicado por ele (autoridade de domínio):**
  verbatim: *"projeto pequeno MP4, foto JPEG e ProRes funciona, mas tu faz um projeto com
  200 colunas ferrou bicho, só o DXV salva, porque eles fazem o software focado nesse
  formato."* Isso converte a regra de "preferencia" em **regra de escala**: codec de
  decodificacao geral (H.264/HEVC/ProRes/MJPEG) e aceitavel em projeto pequeno e vira
  gargalo quando o numero de camadas/colunas sobe. Consequencia direta pro nosso
  desenho: **o veredito de codec nao pode ser binario nem absoluto.** Um H.264 sozinho
  num set de 3 camadas e irrelevante; o mesmo arquivo numa comp de 200 colunas e
  incendio. Entao a tela de saude precisa pesar o aviso pelo tamanho da composicao
  (camadas x colunas x clips carregados), nao pela string `Performance` sozinha -- e o
  texto que mostramos continua sendo o deles ("Slow codec... Transcode to DXV with
  Resolume Alley"), sem inventar numero de FPS nosso.
  Base medida a favor: o Arena embarca licenca e codigo do **`squish`**
  (`/Applications/Resolume Arena/Licenses/squish.md`), biblioteca de compressao por bloco
  DXT1/DXT5, e os presets `DXV 3 {High,Normal} Quality {With,No} Alpha` sao exatamente as
  variantes BC1/BC3 correspondentes a com/sem alpha. **(medido)**
  `chute:` a interpretacao -- DXV seria textura ja comprimida no formato da GPU, entao o
  custo por frame nao depende de decodificador de software, e N clipes ativos nao
  competem por decodificador; H.264/ProRes sim, cada clipe ativo exige decode proprio, e
  isso que explode em 200 colunas. Deixei como chute porque nao medi o pipeline interno
  deles: varri tokens `BC*_UNBLOCK` no binario e no `libMoltenVK.dylib` e nao achei, e
  ausencia de string nao prova nada (esses enums nao aparecem em `strings`). Se ele
  confirmar vira fato; se nao, continua chute -- e a regra vale igual nos dois casos.
- Anotado: ele disse pra não me preocupar *tanto* com HDR aqui. DXV3 é 4:2:2 8-bit com
  alpha — o assunto HDR fica pra quando houver motivo real, não antes.
- **Syphon: veredito justo, nem morto nem recomendado.** O site dele é de fato
  arqueologia -- último comentário público que o operador achou é de **2 de abril de
  2009**, época de v002/Vade e do openFrameworks que ele usava. MAS o protocolo não
  morreu no produto: `/Applications/Resolume Arena/Arena.app/Contents/Frameworks/Syphon.framework`
  está lá no Arena 7.28.0 de hoje. **(medido)** Então "ninguém usa" vale pra
  comunidade e pra novidade, não pra compatibilidade. Conclusão prática: **NDI
  primeiro** (é o que o barramento do venue fala); Syphon no máximo como ponte curta
  TD↔nossa em macOS, nunca como formato que a gente empurra pra terceiros. E nada
  disso entra em código agora -- ver o próximo item.
- **Nada de vídeo em código nesta fase.** O pedido atual dele é **um previ**; entrada
  HDI/3D pesado continua sendo trabalho do TouchDesigner. Ou seja: NDI/Metal entram
  como decisão registrada, não como dependência compilada. Carregar `libndi` ou
  stack de GPU antes de ter pixel pra mover seria exatamente a exceção que mata o
  *convention over configuration*. 
- **O tempo de um turno local não é constante — não confunda com regressão.** O
  mesmo `liveLoopThroughOllama` (mesmo código, mesma máquina, mesma tarde) levou
  **34,6 s** numa rodada e **188,7 s** na seguinte. O `qwen3:1.7b` tem `reasoning`
  e é não-determinístico; a variância é dele, não nossa. Consequência prática: ao
  avaliar mudança no loop, olhe o resultado do teste, nunca a duração. E o
  `ThinkingOrb` existe porque do ponto de vista do operador são só minutos de tela
  sem nada acontecendo — sem ele ele acha que travou, e com razão. **(medido)**

## 4b. O contrato estável: `~/Documents/Resolume Arena` (264 XML, 2,4 MB)
- **Estabilidade comprovada nos arquivos, não em doc:** presets em `Presets/` trazem
  `versionInfo majorVersion="7" minorVersion="3" microVersion="0"` e estão vivos num
  Arena **7.28** rodando agora. ~25 versões menores e o schema ainda carrega -- é o
  argumento do operador de que isso quase não muda. A gente constrói em cima disso,
  não em cima de API que muda a cada release. **(medido)**
- Formato legível: `<Preset className="...">` com `Param`/`ParamRange` (`T="DOUBLE"`,
  `value`, `ValueRange min/max`) e nós `PhaseSourceStatic`, `BehaviourDouble`. Ou seja:
  nomes de parâmetro, faixas reais de mínimo/máximo e a fonte de fase -- exatamente o
  que o `tools/list` do MCP não entrega detalhado. Convergência com o enum
  `parameter.phase_source` que já tínhamos visto.
- Uso permitido pelo nosso próprio jogo de regras: **ler** esse diretório. Ele é dado
  de usuário, não o app -- mas escrever ali seria configurar o Arena pela parte da
  frente e viola a imutabilidade. Então leitura só, sempre.
- `Shortcuts/`: MIDI tem 4 arquivos, Keyboard 1, **OSC 0** -- enquanto
  `activePresets.xml` declara `OSCShortcutPreset="OutputAllMessages"`. `chute:` esse
  é comportamento embutido (repropagar tudo), não mapeamento em arquivo. Perguntar ao
  operador quando formos precisar de mapeamento de console.
- `Compositions/Example.avc` é o set. Não abri: mesmo clã XML, mas é arquivo de show
  dele -- só lemos com ordem explícita.

### Correção de modelo mental dada pelo operador (importante)
- **O `.avc`/`.xml` NÃO é o projeto. É um retrato do estado atual.** O Arena é como
  se fosse *eternamente um projeto só*; o arquivo só diz em que estado ele estava.
  Não existe "abrir projeto" nele, do jeito que existe `.toe` no TouchDesigner.
- Evidência medida que sustenta isso: `Preferences/config.xml` traz
  `CurrentCompositionFile = .../Compositions/Spike.avc`, e **esse arquivo não existe
  em disco** -- só existe `Spike.xml`. O caminho é uma etiqueta de estado, não uma
  dependência real. `Compositions/` guarda `Example.avc` (191075 B) e `Spike.xml`
  (190949 B): 126 bytes de diferença, os dois com `numLayers="3" numColumns="9"` --
  são o mesmo set fotografado duas vezes. **(medido)**
- Consequência de arquitetura, e é grande:
  - **Fonte de verdade do estado é o MCP (+ OSC position), nunca o arquivo.** O
    arquivo é retrato atrasado, pode estar com outro nome, pode não existir.
  - A tela que soma o projeto **não** lê `.avc`: pergunta ao MCP em tempo real.
  - Onde esses XML valem mesmo é como **dicionário** de parâmetros/faixas/phase
    source (ver §4b em cima), não como fonte de estado.
  - Nosso verbo de UI é "conectar ao Arena", não "abrir composição". O que o
    Bonjour descobre é "tem um Arena aberto aqui", não "tem tal projeto".

### Advanced Output: subsistema inteiro (arquivo do operador chegou)
- Chegou: `~/Documents/Resolume Arena/Presets/Advanced Output/Spike.xml`, 12.767 B.
  Antes dele mandar, a única coisa em disco era `SimpleOutput.xml`
  (`advancedModeEnabled="1"`, `<Outputs/>` vazio, 105 B) e `slices.xml` (`<Items/>`
  vazio). Nenhum arquivo de Advanced Output. **(medido, já superado)**
  `SimpleOutput.xml` com `<SimpleSetup advancedModeEnabled="1"><Outputs/></SimpleSetup>`
  (105 bytes, zero saídas) e `slices.xml` com `<Items/>` vazio. Nenhum arquivo de
  Advanced Output em disco. **(medido)**
- `advancedModeEnabled="1"` já ligado, mas sem mapeamento salvo -- ou seja, a
  janela existe e está vazia até ele configurar.
- Consequência: isso é **estado de configuração**, não estado de set, e é escrito
  pelo operador na interface dele. A gente lê, nunca escreve (regra da
  imutabilidade). É o insumo natural da tela que soma o projeto -- dizer "camada 3
  está saindo no projetor do palco" é o que faz a tela servir pro VJ.
- **Errei aqui**: chutei os nomes `Display`, `Slice`, `Transform`, `Feedback` antes de
  ver o arquivo. Nenhum aparece, exceto `Slice` (e esse existe mesmo). Declaração
  pública do erro, conforme combinado.
- **Insight que explica o mistério dos arquivos "vazios"**: Advanced Output não mora em
  Preferences, mora como **preset nomeado** com root `<XmlState name="...">`. Por isso
  `SimpleOutput.xml` e `slices.xml` pareciam vazios -- são outra coisa. Encaixa no
  modelo mental dele ("estados salvos", não projetos).
- Os 22 ferramentas do MCP não têm nada de output (`deck`, `monitor` são o mais
  perto). Esse arquivo é **a única** janela conhecida pro roteador de saída.

#### Estrutura real (lida no `Spike.xml` dele -- substitui qualquer chute meu)
- Raiz: `<XmlState name="Spike">` -> `<ScreenSetup>` ->
  `<CurrentCompositionTextureSize width="1280" height="720">` -> `<screens>`.
- 1x `<Screen name="Screen 1" uniqueId="...">`, contendo:
  - `<guides>`: 2x `ScreenGuide` (`type="0"` e `type="1"`) com
    `ParamPixels name="Image"`.
  - `<layers>`: 1x `<Slice uniqueId="...">` -- **aqui mora o roteamento**:
    `<ParamChoice name="Input Source" default="0:1" value="0:1" storeChoices="0"/>`.
    Semântica de `0:1` é **desconhecida** (deck:layer? layer:deck?). Não inventar:
    verificar via MCP ou perguntar a ele.
  - `InputRect` / `OutputRect`: `orientation=0`, cantos 0,0 -> 1280,720.
    `OutputRect` fecha em `719.99993896484375` (float32 escorrido pra double).
  - `Warper`: `ParamChoice "Point Mode" PM_LINEAR` + `BezierWarper
    controlWidth="4" controlHeight="4"` = **grade de 16 vértices**, e
    `Homography` com `src == dst`.
  - `<OutputDevice><OutputDeviceVirtual name="Screen 1" deviceId="VirtualScreen 1"
    idHash="..." width="1280" height="720">`.
- `<SoftEdging>` fica no nível do **ScreenSetup** (não da slice): 6 `ParamRange`.
- Censo de elementos: 72 `ValueRange`, 32 `v`, 24 cada de
  `PhaseSourceStatic`/`ParamRange`/`BehaviourDouble`, 12 `Param`, 11 `Params`,
  2 `ScreenGuide`, 2 `ParamChoice`, 1 de cada `Slice`/`ScreenSetup`/`XmlState`/
  `Warper`/`SoftEdging`.

#### O que ele me explicou sobre isso (autoridade de domínio = ele)
- O valor do arquivo **não é o roteamento**, é a **calibração feita na mão**. Nos
  termos dele: "isso aí é só um Slice, é só uma fatia e uma entrada e uma saída".
  Obra de arte = geometria de projeção (malha Bezier de 16 pontos, cantos por slice,
  soft edge entre faces adjacentes) que alguém passou horas alinhando projetor.
- Consequência técnica dura -- e **minha primeira formulação dela estava errada**
  (escrevi "lossless byte-a-byte", forte demais). Medido no arquivo real, 46 valores
  decimais, dos quais **39 têm cauda longa** (>6 casas, ex.: `0.10000000000000000555`,
  `239.999984741210937...`, `719.99993896484375`):
  - Round-trip por **double** (`parse` -> `Double` -> `repr`) preserva o **valor** em
    39/39. O **texto** muda em 31/39 (`719.99993896484375` -> `719.9999389648438`),
    mas o número continua o mesmo. Ou seja: texto canônico curto e inócuo.
  - O perigo real é outro: **13 de 39 ocorrências não são float32 exato**, em 3
    valores distintos (`0.400...0222` x9, `0.100...0555` x3, `1.999999999999999778`
    x1). Se qualquer camada nossa ler como **Float32** e resserializar, viram
    `0.4000000059604645`, `0.10000000149011612`, `2.0`. O último é o assassino:
    `1.999999999999999778 -> 2.0` é exatamente meia-pixel de deslocamento de grade.
  - **Regra nº 1 corrigida**: se um dia escrevermos esse arquivo, todo número passa
    por `Double` do início ao fim e é gravado com o **texto original preservado**.
    Fazer parse e reserializar números que não tocamos = proibido. Editar o XML como
    texto é a única forma segura de mexer só no que a gente mudou.
  - Detalhe do dump: 26/39 são float32 exato, 13/39 são double genuíno -- o Arena
    mistura as duas origens no mesmo arquivo.
- Nosso `Spike.xml` é identidade pura (homografia src==dst, uma slice, tela cheia) --
  ou seja: papel em branco. O caso de risco real é o arquivo de um show montado.

## 5. Próximo passo escolhido (e por quê)
0. **Journal de escrita (o fio que ficou solto).** Ele pediu: *"nada do que a gente faz via
   automação fica registrado no undo/redo do Arena. Temos que tratar isso."* Confirmado por
   medição: `composition { action: "diff" }` não é histórico -- devolve "Baseline captured.
   Make changes, then call diff again", e `composition.undo|redo` está vetado pra sempre. Logo
   o Cmd-Z dele não alcança nada do que a gente faz; precisamos de diário nosso.
   Projeto combinado (mínimo, sem porta nova, sem escrever na pasta dele): ator que anota
   JSON-lines em `~/Library/Application Support/Resolux/journal/<sessao>.jsonl`; grava só
   execução **permitida** (recusa não polui); campos = timestamp, tool, action, args, isError,
   ~200 chars do resultado, id da sessão; pré-leitura do valor antigo só em escrita de
   `parameter`, que é o único tool com simetria leitura/escrita limpa (`get`/`get_animation` vs
   `set`/`set_animation`) -- sem leitura universal porque os próprios instruções do servidor
   avisam que snapshot custa token. Ponto único de inserção: `ChatEngine.execute(...)`, que já
   é onde passam tanto o `tool_calls` nativo quanto o resgate de texto. Injetar com default
   desligado pra não quebrar os 50 testes. Depois: UI "últimas mudanças" com o cabeçalho honesto
   *estas são nossas; o Cmd-Z do Arena não desfaz*.
   **STATUS (checkpoint 6): núcleo FEITO e testado.** `WriteJournal.swift` existe
   (append JSON-lines, um arquivo por sessão, cap de 200 chars, leitura do mais
   recente pro mais antigo, linha corrompida pulada); `ChatEngine` injeta com
   `journal: nil` por default — os antigos seguem intocados, os 7 novos cobrem
   registrar-com-anterior, recusa-não-registra, leitura-não-registra, espelhamento
   só-em-`parameter`, corte, ordem e corrupção. Armadilha que mordeu de verdade:
   `JSONEncoder` escapa barra (`tools\/call`), entao filtro cru por `tools/call`
   devolve vazio e teste de ausencia passa POR ACIDENTE — normalizar barra antes de
   filtrar. **Resta:** (a) UI "últimas mudanças"; (b) amarrar `sessionID` à posse do
   operador — DUVIDAS §10.4, espera voto dele porque muda o formato do registro.
0b. **A chave Timeline/Performance + a calculadora de tempo** (checkpoint 7).
   Palavra dele: *"Timeline: Calcula. Performance: Mede."* -- Ableton Live,
   Session vs Arrangement. Especificação inteira em DUVIDAS §13.
   **STATUS (checkpoint 7): núcleo FEITO e testado.** A chave existe --
   `OperationMode.swift`: `timeline` oferece cálculo+monitoração, `performance`
   só monitoração, recusa acionável em `ModeGate.refusal`. A calculadora existe --
   `TimelineCalculator.swift` lê a grade crua do REST, classifica o slot, resolve
   alto piloto (`Layer Determined` herda da camada), funde rolo encadeado num bloco
   só (Merge, palavra dele) e soma em **delta time** (`duracao / speed`, frames
   nunca entram). Taxonomia dos slots em `TimelineModel.swift` (vazio/imagem/áudio/
   vídeo/gerador x execução x barramento, com `.desconhecido` onde o Arena não
   conta). Cliente `ArenaREST.swift` com `Endpoint` injetável -- os testes rodam sem
   rede. **Não confundir com `ToolPolicy.Mode`**: permissão é um eixo, serviço é
   outro; performance pode ser `readWrite`. **Resta:** (a) plugar no `ChatEngine`
   com default `.timeline` e recusar cálculo em Performance; (b) telemetria como
   módulo próprio (medida isolada não é produto, limiar de aviso é voto dele);
   (c) Picker na UI **só se ele pedir**. Toda a especificação que gerou isso está
   em DUVIDAS §13 (delta time, ±32768 fora da conta, imagem 1 s, synth morto,
   epoch segundos, rename com `#`).

Ordem que faz sentido, um item por tacada:
1. **Deixar ele ver o humano↔bot funcionando** antes de qualquer commit (pedido
   explícito dele). Abrir o `ResoluxMac.app` do parágrafo acima, Arena já está
   aberto, e apertar "Conectar ao Arena". Uma pergunta legível basta. Aviso
   honesto que precisa ser dito junto: um turno local leva **minutos**, não
   segundos (`liveLoopThroughOllama` = 34 s; com fm é ~118 s), e a resposta vem
   pelo Ollama porque é o único backend provado com tools.
2. **Commit em 4 lotes** (§9) depois que ele aprovar no olho. Não antes.
3. ~~Endurecer `.readWrite`.~~ **FEITO nesta tacada** — ver §6 "veto permanente".
   Resto do item: decidir se `clip.type` (Timeline → BPM Sync) deve ter veto
   também quando a escrita vier por `parameter.set` genérico, hoje coberto só em
   nível de ação de ferramenta. Precisa dele: é regra de VJ, não minha.
4. **Tela que soma o projeto inteiro.** Requisito dele: abriu, cospe na cara o
   set — camadas/colunas/decks, modo de transporte por clipe, o que toca, estado
   do relógio, e **saída por display**. É leitura pura e exercita o pipeline
   inteiro sem tocar em nada. Atenção ao teto do Apple: `layer` e `effect` não
   cabem na janela do fm (§4), então essa tela precisa nascer falando com o
   Ollama ou sem provedor (chamada direta de leitura), senão vira mentira.
5. **Diagnóstico de barramento / varredura de porta pelo protocolo** (fim de
   projeto, é relatório, nunca configuração). Encarregado antigo.
## 6. Decisões de desenho dessa camada (responsabilidade assumida)
- **"Você está capenga" -- limitação aparece na cara, não em rodapé.** Regra dele:
  *"O que não der pra fazer, a gente explica."* Quando o backend escolhido é o Apple FM,
  `ResolumeChatView` mostra um cartão amber dizendo que só `N` de `M` ferramentas do Arena
  estão alcançáveis e que camada/efeito ficaram de fora; a pílula de status também passou a
  dizer "10 de 22 ferramentas" em vez dos 22 do servidor. O denominador vem do `tools/list`
  vivo (`toolTotal`), não de número que eu decorei. Esconder limitação é bug de produto aqui.
- **Bug que eu mesmo achei e consertei nesta tacada:** `ResolumeChatModel.begin(with:)` montava
  o `ChatEngine` sem repassar `settings.toolAllowlist`. Consequência: no backend Apple as 22
  ferramentas eram oferecidas e o `fm serve` derrubava HTTP 500 na janela curta -- ou seja, o
  voto "Apple de cara" estaria quebrado no dia em que fosse ligado. Não existia teste cobrindo
  esse elo entre `Settings` e `ChatEngine.Config`; hoje o voto tem teste
  (`BackendPreferenceTests`) mas **a regressão do allowlist ainda não tem teste próprio** --
  quem retomar deveria adicionar um (engine construído via model precisa chegar com subset).
- Provedor plugável com **local primeiro** (FM/Ollama, sem key); OpenAI só quando
  houver key salva, onde `tool_calls` nativo funciona.
- Uma ferramenta por turno + enum apertado: menos superfície, modelo pequeno acerta
  mais. 63 KB de schema afogam ~2B.
- Recusa implementada **por nós**: nada batendo na lista nomeada, nenhuma chamada.
  Política > boa vontade do modelo (ele não sabe recusar: "bom dia" virava
  `status/get`).
- Regra de domínio já encodeada no system prompt e travada por teste: fonte do
  relógio declarada antes de citar BPM/taxa/posição (`ChatEngine.systemPrompt`,
  em `Features/Resolume/Sources/Resolume/ChatEngine.swift` — não cito mais linha
  numérica porque ela já mudou três vezes nesta sessão e âncora falsa é pior que
  nenhuma), e SMPTE nunca em clipe com faixa de áudio — regra dele, ausente do
  schema do fabricante.
- **Veto permanente (feito nesta tacada).** O gate tinha virado bypass total no modo
  escrita (`if mode == .readWrite { return true }`) — "Permitir alterações" era ligar
  um truque num cavalo. Agora `ToolPolicy.decide` devolve `.allow / .readOnly /
  .never`, e `neverActions` barra em **qualquer** modo o que é irreversível ou que
  re-temporiza o show: `clip.set_transport` (converte Timeline → BPM Sync; o caso que
  ele descreveu como "aí fodeu tudo"), `composition.open|new|save*|undo|redo`,
  destruição de conteúdo (`layer.clear_clips`, `deck.eject`, `effect.remove`…) e
  `batch`, que seria a porta dos fundos porque o payload não é inspecionável ação por
  ação. Todo nome conferido contra `Fixtures/tools-schema.json` por teste dedicado
  (`nomes do veto permanente existem no enum real do servidor`) — é a guarda que falta
  quando eu digito API de memória. Um único item ali é marcado `chute:` no comentário:
  veto de `autopilot.set`, pelo medo de dois autômatos brigando pelo crossfader. Votar.
  A recusa agora também não mente mais: bloqueio no modo escrita dizia "modo somente
  leitura", o que faria qualquer um insistir achando que basta ligar a permissão.
- **Conexão sem campo algum.** `LocalChatBackend.discover()` sonda **só loopback**
  (:1976 e :11434, `GET /v1/models`, sessão própria de 2 s) — sem broadcast, sem
  Bonjour ainda, sem abrir porta nossa, sem pedir IP. A API key saiu da view: era
  violação frontal da regra zero-campo. Sobrou na tela um único controle: o seletor de
  política (leitura / permitir alterações), porque isso é decisão de show, não
  configuração.
- Preferência de backend = **Ollama primeiro**, Apple como fallback. Motivo técnico
  honesto: só o Ollama tem `tool_calls` nativo provado ponta a ponta; o fm escreve a
  chamada como texto e engolimos com `ToolCallTextRescue`. É escolha de produto e está
  na mesa pra ele (§4/`docs/DUVIDAS.md` item 3).

- **Canal remoto = WebSocket (decisão dele com meu voto técnico, 2026-09-27).**
  Presença e posse de sessão são semântica **bidirecional**: o lado remoto precisa
  dizer "estou aqui, quero escrever" e receber "não, quem tem a posse é X". SSE é
  downlink puro (todo upstream viraria POST separado, dois canais, duas verdades) e
  polling HTTP não carrega presença nenhuma -- vira adivinhação com atraso. WS dá os
  dois sentidos numa conexão só. Com três condições duras, sem as quais não vale:
  - **Posse autoritativa mora no Mac**, não no celular. O Mac é quem fala com o
    Arena; o lease tem de estar onde a escrita acontece. Segundo cliente recebe
    recusa explícita **nomeando** quem está na posse (senão ele insiste achando que
    é bug de rede).
  - **Lease com TTL + heartbeat obrigatório.** iOS mata o socket em background sem
    avisar; sem TTL o show fica refém de um app morto. E no reconnect **nunca**
    re-adquirir posse sozinha se outro operador já pegou -- reconectar é pedido, não
    direito.
  - **Transporte chega por túnel que ele mesmo levanta.** Regra permanente: do meu
    lado Tailscale tem zero automação (nem probe de `tailscale status`). Entrego o
    comando, ele roda. Nada de bindar em `*` nem inventar superfície TCP nossa.
  Local (topologia 1) não precisa de nada disso: já é `ProcessMCPTransport`, stdio,
  sem rede. O WS só serve a topologia 2 -- e **"remoto" não quer dizer WAN**: pode
  ser o mesmo iPad na mesma rede do Mac. Isso não afrouxa nada, só muda o motivo:
  - **Rede local não é rede confiável.** Wi-Fi de casa tem celular de visita, TV,
    outro laptop; e o próprio show acontece em rede de venue, que é o pior lugar
    possível pra assumir confiança. Então o WS exige pareamento/token **mesmo em
    LAN** -- posse única sem autenticação é só um nome bonito pra "quem chegar
    primeiro manda". A regra que isso aperta: hoje `LocalChatBackend.discover()`
    sonda **só loopback**; aceitar cliente LAN significa encostar numa interface
    não-loopback, e isso é decisão dele, não minha. Continuo sem bindar em `*`.
  - **Descoberta sem campo de IP**, respeitando a regra zero-config: Bonjour
    (já provado que resolve -- foi assim que achou o Arena sozinho via
    `_http._tcp.local`), não caixinha de endereço.
  - Em LAN o TTL fica **mais** importante, não menos: iPad em Wi-Fi perde o socket
    ao virar tela/block e ao trocar de AP, sem nenhum aviso chegando no Mac.

### Legenda das tags de incerteza no código (vocabulário novo, checkpoint 9)
Ele pediu pra não deixar `chute:` solto: *"Coloca uma tag de não documentado ou instável."* Virou
duas tags, com significados diferentes, e é assim que se lê um `grep`:
- **`nao documentado:`** -- o comportamento existe e eu tenho quase certeza, mas **nenhuma página da
  Resolume escreve sobre ele**. Risco aqui é doc deles ficar muda, não minha hipótese estar errada.
  Hoje: `autopilot.set` vetado permanentemente em `ToolPolicy.neverActions`.
- **`instavel:`** -- é **nossa escolha de desenho** com número que ainda não medimos na condição
  certa. Aqui o risco é meu, e a saída é medir, não consultar doc. Hoje: piloto × `speed` em
  `SlotState.effectiveMS`, piloto reassumindo relógio em clipe SMPTE, e o default de
  `ModeGate.defaults`.
Regra operacional: `grep -rn "instavel:\|nao documentado:" Features/Resolume/Sources` devolve a lista
do que ainda não tem prova. Toda entrada dessa lista tem medida barata que a fecha -- nenhuma exige
inversão de decisão dele.

## 7. Coisas que já afirmamos erradas e foram corrigidas
- "Reaper fica na rack" — li torto; objetivo era tirar o DAW. Depois ele tirou o
  DAW do desenho inteiro.
- "BPM 120 foi dano" — é só o padrão do Arena.
- Allowlist de ações e fixture de teste que eu tinha **inventado** — re-feitos do
  `tools/list` real (`Fixtures/tools-schema.json`, 22 ferramentas). O teste de
  divergência achou 45 erros e estava certo.
- "MTC não existe no TD do macOS" — meu `strings | grep -x` case-sensitive voltou
  zero pra tudo que existe. Método quebrado, não o TD.
- "FM ignora tools" — na verdade ele finge: devolve texto imitando tool call.
- **"21 ferramentas passaram no fm"** — número **falso que eu reportei**. Eu tinha
  omitido `stream:false`: o fm respondia SSE com HTTP 200 e eu li o 200 como sucesso.
  A medição correta está na escada do §4: **10** ferramentas passam, 11 dá 500. O
  transporte agora joga `ChatError.streamingUnsupported` em `text/event-stream` pra
  essa classe de erro próprio não voltar a se disfarçar de OK. **(autocrítica)**
- `lsof -p PID -i` sem `-a` é OR, não AND — já me fez afirmar "sem sockets" com
  evidência falsa. UDP não tem LISTEN: `lsof -nP -iUDP`.
- **"Imagem herda `duration_ms` do arquivo"** — meu erro de desenho, pego pelo teste
  antes de eu notar. PNG não tem tempo de tela; deixar o arquivo falar inflaria a
  linha com tempo que nenhum operador programou. Precedência corrigida: transporte >
  mídia (só áudio/vídeo) > padrão da casa (só imagem) > nenhuma. (DUVIDAS §13.5)
- **"FrameRate 0 = fps zero"** — `composition.framerate.value = 0.0` é **Auto**. Li
  o número sem o documento nomear a unidade, exatamente o erro que a regra §13.4
  proíbe. **(medido)**
- **"Array do REST é posição"** — `deck.layers` e `layer.columns` vêm vazios. Grade
  lida por array sairia às avessas; endereço é `layers/{L}/clips/{C}` 1-based.

- **"Clipe em SMPTE entra na soma"** -- bug real de desenho meu, exposto pela foto dele do dropdown:
  a calculadora somava qualquer clipe com número, inclusive um escravizado a timecode externo, como se
  o *play* fosse ato nosso. A regra que proibe isso já estava escrita há checkpoints ("em situação
  síncrona o play nunca é ato nosso"); eu só não tinha aplicado na soma. Corrigido em
  `SlotState.effectiveMS` com teste. **(autocrítica)**
- **"Quase afirmei `duration_type` ausente na camada"** -- meu `print` acessou `autopilot` pelo caminho
  errado e o campo sumiu da saída. Regra que fica: **leia o payload antes de afirmar ausência**;
  print quebrado é tão perigoso quanto doc mentirosa. **(autocrítica)**
- **Teste contrato mal escrito por mim**: afirmei `nomeNoArena.contains(nome)` cobrindo as 6 opções e
  o `.mesa` junta Denon+Pioneer num nome só — falhou na hora, certo ele. Virou `nomesNoArena:
  [String]` com round-trip. O teste me pegou antes do usuário, que é o papel dele.
- **`durationSource` sem número**: meu teste esperava `.nenhuma` num caso `Beats` sem BPM; o código
  devolve `.piloto` com `durationMS == nil`, e o código está mais certo -- manter a fonte preserva o
  diagnóstico ("faltou o BPM") em vez de apagar a causa. Asserção ajustada ao código, não o contrário.


- **"`clip.type`" no system prompt era campo fantasma -- e eu tinha escrito teste travando o
  fantasma.** O prompt ensinava o modelo a olhar `clip.type`; medido nos 72 clipes do payload vivo,
  **não existe chave `type` em clipe nenhum** -- o nome real é `transporttype`. Pior: o teste
  `#expect(prompt.contains("clip.type"))` congelava o erro, então ele passava verde. Corrigido nas
  duas pontas: prompt agora diz `clip.transporttype` com as 6 opções exatas, e o teste passou a
  exigir a **ausência** de `clip.type`. Lição: testar presença de string no prompt só prova que
  escrevi a string, nunca que ela corresponde à máquina. **(medido + autocrítica)**

## 8. Armadilhas de ambiente (não repagar)
- String interpolada escrita como `\#(i)` — derrubou o build de testes três vezes
  (mais dois trechos mutilados no mesmo arquivo). Se `--build-tests` morrer em
  `invalid escape sequence`, é isso, não mistério do toolchain.
- Sudo-free .pkg: `brew fetch --cask X` → `open "$(brew --cache --cask X)"`.
- `rm -f/-rf` é rejeitado pela sandbox mesmo com approval `never`; nunca pedir
  escalada nesse perfil.
- zsh: citar globs; `mkdir && cat <<EOF` aborta heredoc se o dir existe; `rg` não
  tem `-E`; greps precisam `--exclude-dir=.build`.
- Heredoc Python queimou várias vezes: `read_text()` com parênteses, sem atribuir
  em `Path.read_text`, sem lixo condicional. Escrever curto, editar no lugar.
- `apply_patch` exige `*** End Patch` e o texto esperado **exato** (um `—` a mais
  derruba o hunk). Prefira hunks pequenos depois de ler o trecho.
- Processo longo em `exec_command` devolve session id; drenar com `write_stdin`.
  `C-c` não mata confiável — matar por PID e conferir porta.
- Ports ocupadas neste Mac: `5000`/`7000-tcp`/`8080` (AirPlay Receiver + Arena);
  livres: `5001`, `8937`, `43117`.

## 9. Plano de commit (re-contado no checkpoint 7, quando ele mandar)
Ele quer **ver funcionando antes de commitar**. Os lotes 1–4 do checkpoint 5 **já
foram despejados** em `454f53e` ("Update working tree" — commit único, não em lotes;
registrado pra não relançar plano velho). O que falta commitar agora são dois lotes,
o do journal e o da calculadora:
- `feat(resolume): diário de escrita (rastro do que o Cmd-Z do Arena não alcança)` —
  `WriteJournal.swift`, `WriteJournalTests.swift`, `ChatEngine.swift`,
  `ToolPolicy.swift`. Atenção à armadilha de sempre: os dois `docs/` modificados
  vão junto ou num `docs:` separado — nunca deixar o doc descrevendo código órfão.

Histórico dos lotes originais (checkpoint 5), pra referência do que já entrou:
1. `fix(resolume): timeout do transporte acompanha turno local (300 s)` --
   `MCPTransport.swift`, `ProcessMCPTransport.swift`, `UnixSocketProbe.swift`,
   `ResolumeApp.swift` (prontidão pelo socket) + `TransportTimeoutTests.swift`,
   `SilentServerTests.swift`, `UnixSocketProbe.swift`/`UnixSocketProbeTests.swift`.
2. `feat(designsystem): portar peças MEVOLIT (palette, tone, aurora, glass, glow)` --
   os 5 arquivos novos em `Packages/ResoluxDesignSystem/Sources/ResoluxDesignSystem/`.
   Lote independente: nada em `Features/` compila sem ele, mas ele compila sozinho.
3. `feat(resolume): servidor MCP com gate de instruções e schema normalizado` --
   `MCPClient.swift`, `MCPJSONRPC.swift`(se mexido), `MCPValue.swift`,
   `ToolSchemaNormalizer.swift`, `Fixtures/tools-schema.json`,
   `InstructionsGateTests.swift`, `MCPClientTests.swift`.
4. `feat(resolume): chat sem campos, descoberta local e ordem de preferência votada` --
   `LocalChatBackend.swift`, `ToolCallTextRescue.swift`, `ChatEngine.swift`,
   `ChatModels.swift`, `ResolumeChatModel.swift`, `ResolumeChatView.swift`,
   `ResoluxMacApp.swift`, `Package.swift` + `BackendPreferenceTests.swift`,
   `ChatModelStateMachineTests.swift`, `ChatEngineTests.swift`,
   `ToolCallTextRescueTests.swift`, `LiveLoopTests.swift`, `RealServerSmokeTests.swift`.
5. `fix(resolume): veto permanente no gate de escrita` -- `ToolPolicy.swift` +
   `ToolPolicyTests.swift`, `ToolAllowlistTests.swift`.
- `feat(resolume): chave Timeline/Performance + calculadora de tempo` --
  `OperationMode.swift`, `TimelineModel.swift`, `TimelineCalculator.swift`,
  `ArenaREST.swift`, `MCPValue.swift` (+`doubleValue`/`intValue`/`parameterValue`)
  + `TimelineCalculatorTests.swift`. Lote independente: nada acima depende dele, e
  `MCPValue` já entrou no uso do journal sem quebrar os testes antigos.
**Armadilha de ordem (leia antes de commitar):** `Package.swift` está modificado junto
com fontes novas; se o lote 4 entrar antes do 2 e do 3, o commit fica sozinho sem
compilar. A sequência acima é dependente de propósito. Se ele quiser histórico
bisectável, confirmar essa ordem antes -- eu não reordero sem ele.
Nada de commit sem ordem dele. Nada de branch nova sem ele pedir.

## 10. Fora do repo (artefatosvoláteis, podem sumir)
Podem sumir a qualquer momento; nada essencial depende deles.
- `/tmp/tools.json` — dump completo do `tools/list` do Arena (22 ferramentas, 69 KB).
  A cópia que importa é `Features/Resolume/Tests/ResolumeTests/Fixtures/tools-schema.json`.
- `/tmp/fmshared.py` — `probe`/`normalize`/`specs` validados, importável; base das
  medições do fm. `/tmp/fmladder2.py`, `/tmp/fmfinal.py` — a escada do §4.
  `/tmp/sysprompt.txt` — system prompt real do engine (1.001 chars), usado na medição.
  `/tmp/ladder2.log` está **stale/vazio**: se precisar, re-rodar `fmladder2.py`.
- `/tmp/oscsniff.py` (escuta da 7001), `/tmp/bindprobe.py`, `/tmp/tdmcp-audit/repo`,
  `/tmp/fmprobe/`, `/tmp/sseprobe.py`, `/tmp/afm_choice2.py`.
- `/tmp/comp.json` — `GET /composition` vivo (composição "Spike"): melhor
  candidato a fixture de teste que existe. `/tmp/sw.yaml` — swagger do REST, 258
  rotas. `/tmp/perf6.swift` (GPU via IOAccelerator) e `/tmp/rus5.swift`
  (CPU/RAM via `proc_pid_rusage`), os dois probes compilados e calibrados.
