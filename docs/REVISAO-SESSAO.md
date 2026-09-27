# Revisão de sessão — Relógio / Timecode

> **Snapshot histórico (2026-09-27 manhã).** Não atualizo este arquivo: as linhas
> com `.swift:NN` e os "hoje é assim" daqui envelheceram durante a mesma sessão.
> Estado atual = `docs/HANDOFF.md`; dúvidas abertas = `docs/DUVIDAS.md`.

Índice do que se acumulou. Um fio por vez, na ordem que o operador escolher.
Nada aqui está commitado. Arena intocado. Marcação: **(medido)** = observado
nesta máquina; **(docs)** = tirado de documentação/catálogo; **(chute)** =
minha inferência, precisa veto ou confirmação.

## Regras do operador (valem acima de tudo)
- **Arena é imutável.** Nada do que vem de fábrica é alterado: nem Preferences,
  nem Wire, nem config de OSC/REST/MIDI. A gente se adapta ao que ele já oferece,
  porque "ninguém sabe mexer nesse tipo de coisa". Distinção que uso (veto em uma
  linha se estiver errada): *operar* o set ao vivo (tocar, cue) pode, quando ele
  armar; *configurar* o app nunca.
- **Rede sandboxed.** Nada de porta aberta em `*` disputando infra de venue.
  Endereço fixo + faixa negociada por local.
- **Portas padrão do Arena nunca mudam.** 8080 (REST), 7000 (OSC in), 7001 (OSC
  out) ficam como vieram de fábrica. Se algo precisar de outro número, esse algo
  se move -- nunca o Arena.
- **Ponte é o TouchDesigner.** Nenhum DAW entra no desenho (nada de Reaper/QLab
  como peça nossa). Quem executa tempo, render e OSC de luz é o TD.
- **Zero campo de configuração.** No limite, um IP -- e se Bonjour resolver, nem
  o IP: o Arena já se anuncia sozinho.
- **Autoridade de domínio é dele.** Chute meu vem prefixado `chute:` e ele veta
  em uma linha.
- **Ritmo:** uma unidade de trabalho por vez, depois pausar e ouvir.

## Fios abertos

### 1. tdmcp (TouchDesigner já tem MCP)
- Ponte é um WebServer DAT dentro do TD, escutando `127.0.0.1:9980` — loopback
  puro, casa com a regra de rede. **(medido no fonte)**
- 509 ferramentas registradas; `TDMCP_TOOL_PROFILE=safe|directory|full` estreita
  isso. Serve pro nosso problema de schema gigante afogar modelo pequeno.
- Já tem: `create_ltc_timecode_bridge`, `sync_timecode`,
  `connect_lighting_console_osc` (com `safety_mode: dry_run|approval_required`).
- Cobertura fraca: lock/drift entre correções é só texto de aviso, não código.
  Aí é nosso trabalho.
- Risco cru: default do `sync_timecode` é OSC `0.0.0.0:7000`, que colide com o
  Arena (ver fio 2). E `docker-compose.yml` sobe com host `0.0.0.0`.

### 2. OSC do Arena
- Escutado por 3s em `127.0.0.1:7001`: 278 e depois 299 pacotes/s. **(medido)**
- Só dois endereços, ~140 Hz cada: `/composition/layers/1/clips/1/transport/position`
  e `/composition/selectedclip/transport/position`.
- Antes de eu escutar, **ninguém** lia a 7001. O Arena fala com ele mesmo; a mesa
  de luz não recebe nada hoje.
- Taxa segue o cook do Arena, não é tick estável — mais um motivo pro lock ser
  nosso.
- Só publica camada 1/clip 1 e o clip selecionado. Escolher outra camada seria
  mexer nele, então consumimos o que sai.

### 3. Timeline × BPM Sync
- Regra do operador: clip em **Timeline** (padrão) não é afetado pelo BPM global;
  BPM só atua em **BPM Sync**.
- Já escrita no system prompt do bot: `Features/Resolume/Sources/Resolume/ChatEngine.swift:152`.
- Consequência pro timecode: se o clock derivar de clip Timeline, o BPM global é
  irrelevante e não podemos chamar aquilo de "BPM do show".
- **Desencontro decidido pelo operador:** o BPM global não é assunto do produto
  ("ninguém usa essa porra" → ninguém usa). Não vira caso de teste nem caso de UI.
- O risco que sobra, e esse é duro: escrita que mude `clip.type` para *BPM Sync*
  junto com BPM alterado desanda o set. Então `clip.set_transport` e qualquer
  escrita que toque tipo de transporte ficam fora da lista nomeada até o operador
  mandar incluir.

### 4. `libLTC.dylib` dentro do Arena
- **Perdeu prioridade com a regra da imutabilidade**: ela só importa se a gente
  escravizar o Arena num timecode externo, e isso exige configurar entradas SMPTE
  nele — que é justamente o que não fazemos. Se algum show precisar disso, é ato
  manual do VJ na interface dele, não coisa que nosso software pilote.
- O Arena embute libLTC e a carrega de fato. Símbolos de encoder E decoder
  presentes (`ltc_encoder_create`, `ltc_decoder_read`, ...). **(medido)**
- Docs internos descrevem **duas entradas SMPTE** nativas, com framerate
  configurável e compensação de delay em frames. **(docs)**
- Ainda não entendido: como isso se expõe (MCP? só GUI?) e o que significa pro
  nosso gerador. Fio a destrinchar.

### 5. MTC (o que os iluminadores usam)
- `midioutCHOP` do TD tem parâmetros "Send MIDI Timecode" e "Timecode
  Object/CHOP/DAT". MTC de saída é nativo do TD — não precisamos escrever port
  CoreMIDI. **(docs do catálogo de ops)**
- Como errei: varri o binário do TD com `strings | grep -x` case-sensitive e
  voltou zero pra tudo que existe. O teste limpo são três linhas num projeto.

### 6. Modo Escrita
- Hoje `.readWrite` retorna `true` antes de qualquer tabela — bypass total.
  `Features/Resolume/Sources/Resolume/ToolPolicy.swift:58`.
- Default é read-only e deny-by-default: fora da tabela = escrita = bloqueia.
  `Features/Resolume/Sources/Resolume/ToolPolicy.swift:63`
- Proposta pendente: escrita sempre nomeada, mesmo com o modo armado.

## Fila consolidada (mensagens que chegaram juntas)
- **Tela que soma o projeto inteiro.** Requisito de UI: ao abrir, o app cospe na
  cara do operador o set inteiro -- camadas/colunas/decks, modo de transporte de
  cada clipe, o que está tocando, estado do nosso relógio. Ele olha e sabe como as
  coisas estão. Leitura pura; casa com o diagnóstico de barramento abaixo.
- **Backend "Apple-like":** `fm serve` como proxy -- sem key, sem instalar nada, e
  a gente ganha o modelo `system`. Estudo liberado pelo operador. Dado medido: ele
  aceita `tools`, mas devolve a chamada como **texto** imitando o formato, não como
  `tool_calls` de protocolo (testado nos dois modos, stream e fechado). Logo: JSON
  guiado parseado do nosso lado, uma ferramenta por turno, e a recusa ser *nossa*,
  não do modelo.
- **Bonjour achou o Arena sem pedir nada.** Scan de `_http._tcp.local.` devolveu
  `Resolume Arena 7.28.0 - Webserver & Rest API`; multicast ativo no `en0`.
  Descoberta existe sem digitar IP. `_oscquery._tcp` e `_NDI._tcp`: zero anúncios.
  **(medido)**
- **Art-Net, a pergunta que ele não lembrava:** o Arena segura `UDP *:6454` -- porta
  padrão do Art-Net -- e embute `libArtnet.dylib` com símbolos reais
  (`artnet_get_config`, `artnet_add_rdm_device`). É saída de luz *dele*, não nossa;
  entra no diagnóstico, não no nosso roteamento. **(medido)**
- **Portas do TD:** ele trabalha com loopback interno e número padrão em tudo, então
  o roteamento TD ↔ Arena respeita os padrões de cada um e move só o que for nosso.
  Investigar sem furar a regra das portas do Arena.

## Encarregados para o fim do projeto
- **Diagnóstico de barramento (varredura de porta pelo protocolo).** Nosso app
  escuta o protocolo que deveria estar fluindo e varre as portas em volta, pra
  quando *alguém fizer merda* -- outro app ocupando a faixa, VJ mexendo na porta,
  console apontando pro lugar errado -- o diagnóstico dizer isso em uma frase, em
  vez do operador descobrir no meio do set. Não é feature de produto, é relatório:
  ele lê o barramento, nunca configura nada em nome de ninguém (regra da
  imutabilidade). Só depois que o caminho principal estiver sólido.

## Decisão que trava código
Quem gera o frame do timecode. Reaper saiu do desenho (ponte é o TD), então sobram
duas: o position que o Arena já despeja em loopback -- minha escolha hoje, porque
não toca nele e já flui -- ou free-run nosso, que faria de nós o relógio do show e
eu não quero isso sem o operador armar.

A regra "abre o Arena, abre o nosso app e a gente dá o nosso jeito" estreita essa
decisão: sem config nossa nem dele. Hoje ainda não cumpro isso -- o app pede API
key, base URL e nome de modelo (`Features/Resolume/Sources/ResolumeUI/ResolumeChatView.swift:58`),
e `connect` recusa sem key (`Features/Resolume/Sources/ResolumeUI/ResolumeChatModel.swift:81`).
Detectar o Arena já é automático (`ResolumeLocator.discover`).

## Corrigidos nesta fase
- "Reaper fica na rack" — li torto, o objetivo é tirar o DAW de lá.
- "BPM 120 foi dano" — é só o padrão do Arena. Retirado.
- Action allowlist e fixture de teste que eu tinha inventado — re-feitos a partir
  do `tools/list` real.
- Meu `chute:` de que MTC não existia no TD do macOS — método de varredura era
  quebrado, não o TD.
