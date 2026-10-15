# Resolux API v1 — contrato

Este arquivo é a fronteira única entre a engine Swift e o cliente web. A engine
é dona da versão; a UI não inventa endpoint nem formato novo.

## Base

- Daemon: `ResoluxServer`, escutando em `127.0.0.1:1980` por default;
  `RESOLUX_BIND=0.0.0.0` abre todas as interfaces (LAN, Tailscale) — é o
  modo do `scripts/release.sh`.
- Cliente web conversa com o daemon; não fala MCP, Ollama, Apple FM nem REST do
  Arena diretamente. Protocolos externos ficam no adaptador do daemon.
- HTTP: `http://127.0.0.1:1980/api/v1`.
- WebSocket: `ws://127.0.0.1:1980/api/v1/ws`.
- Em release, o daemon também serve o bundle estático do frontend
  (`/`, `/assets/**`, `/icons/**` e `manifest.webmanifest`) quando
  `RESOLUX_FRONT_DIST` aponta para o `dist/` — sem a variável o daemon é só
  API. Em debug, o Vite fica na origem `:3003` e repassa `/api/v1` e
  `/monitor` para o daemon; a 1980 não serve front.
- JSON `utf-8`; campo `Content-Type: application/json`.
- Erro HTTP sempre em envelope: `{"error":{"code":"...","message":"..."}}`.
- Sem CORS. O binding default segue no loopback; em release o daemon atende
  direto na LAN/Tailscale pela mesma 1980. Origem aceita no handshake WS: loopback
  (`localhost`, `127.0.0.1`, `::1`), faixas privadas (10/8, 172.16/12,
  192.168/16 e o CGNAT 100.64/10 do Tailscale) e nomes de máquina sem ponto ou
  terminados em `.local` (mDNS, ex.: `mac`, `mac.local`). Host de site externo
  sempre tem ponto e continua de fora.
- `ToolPolicy` permanece read-only e deny-by-default. Escrita só aparece na API
  quando o operador mudar esse voto.

## HTTP

| Método e caminho | Uso | Resposta |
|---|---|---|
| `GET /api/v1/health` | sonda do daemon | `{"protocol":"resolux-api/1","status":"online"}` |
| `GET /api/v1/session` | estado atual da engine | `{"protocol":"resolux-api/1","mode":"timeline","backend":"ollama","model":"qwen3:1.7b","toolPolicy":"readOnly","toolsAllowed":22,"journalEnabled":true}` |
| `PATCH /api/v1/session` | muda só estado permitido | mesmo corpo de `GET /api/v1/session` |
| `GET /api/v1/tools` | ferramentas visíveis ao modelo | `{"tools":[{"name":"composition.get","description":"..."}]}` |
| `GET /api/v1/conversa` | turnos persistidos pelo daemon | `{"turnos":[{"id":1,"papel":"usuario","texto":"...","hora":"10:01"}]}` |
| `DELETE /api/v1/conversa` | limpa a conversa do disco | `{"turnos":[]}` |
| `GET /api/v1/arena/**` | proxy read-only do REST do Arena | JSON do Arena |
| `HEAD /api/v1/arena/**` | proxy read-only | headers do Arena |
| `GET /monitor` | SSE do monitor do sistema | evento `data: {contrato v1}` |
| `POST /monitor/processes/{pid}/terminate` | encerra processo listado pelo monitor | `{"ok":true}` ou `{"ok":false}` |

### Proxy do Arena

- Caminho interno `/api/v1/arena/foo` vira o endpoint REST do Arena
  configurado no daemon (`ARENA_REST_PORT`; `8080` é default de fábrica, não
  verdade fixa). Medido nesta sessão: `8008` respondeu; depois de o front sair
  do trio `3000/8080/3001`, o Arena voltou ao default `8080` de fábrica
  (`192.168.0.105:8080`), o que corrobora a colisão com o HMR do Meteor.
  **(medido: conversa)**
- O valor válido é parte do preflight/homologação; o daemon não descobre ou
  configura nada escrevendo no Arena.
- Só `GET` e `HEAD`. `POST`, `PUT`, `PATCH` e `DELETE` voltam `405`.
- O proxy não reescreve JSON; repassa status, corpo JSON ou binário (as
  thumbnails chegam como `image/*`) e content type.
- Se o Arena não estiver aberto, responde `502` com
  `{"error":{"code":"arena_unavailable","message":"Arena REST unavailable"}}`.

### `PATCH /api/v1/session`

Campos opcionais; campo desconhecido volta `400`:

```json
{"mode":"timeline","backend":"ollama","model":"qwen3:1.7b","toolAllowlist":["composition.get","layer.list"]}
```

Valores aceitos nesta versão:

- `mode`: `"timeline"` ou `"performance"`.
- `backend`: `"ollama"`, `"applefm"` ou `"spike"`.
  - `"spike"` usa o endpoint OpenAI-compatível da conta do Spike: token e
    `baseUrl` lidos de `~/.spike/account.json` no host da engine (nada vai no
    repo nem aparece na UI). Modelo padrão `"Spike"`; `model` do PATCH troca o
    id enviado ao endpoint.
- `toolAllowlist`: lista de nomes declarados em `/api/v1/tools`; `null` volta a
  oferecer todas as ferramentas.
- `toolPolicy` não é configurável: fica read-only nesta versão.

### `/api/v1/conversa`

- `GET` devolve o histórico em disco; `DELETE` limpa e devolve
  `{"turnos":[]}`. Outro método volta `405`.
- Turno `usuario` entra quando o `chat.started` sai; turno `agente` entra
  quando o `chat.result` sai. Turno interrompido/errado não grava resposta.
- Cada turno ganha `id` sequencial do disco — é a chave de reconciliação
  dos clientes no push (abaixo). Campo fora de `{id, papel, texto, hora}`
  não existe; `papel` é `usuario` ou `agente`.

## WebSocket

Toda mensagem é um objeto com `type`. Mensagens de cliente devem ter `id` para
correlação. Só um turno `chat.send` por conexão; outro turno antes de terminar
recebe `busy`.

### Cliente → engine

```json
{"type":"chat.send","id":"msg-1","payload":{"text":"Quantos clipes tem agora?"}}
{"type":"session.update","id":"cfg-1","payload":{"mode":"timeline"}}
{"type":"conversa.subscribe","id":"conv-1"}
{"type":"ping","id":"ping-1"}
```

### Engine → cliente

```json
{"type":"hello","payload":{"session":{"protocol":"resolux-api/1","mode":"timeline","backend":"ollama","model":"qwen3:1.7b","toolPolicy":"readOnly","toolsAllowed":22,"journalEnabled":true}}}
{"type":"chat.started","id":"msg-1"}
{"type":"chat.result","id":"msg-1","payload":{"message":{"role":"assistant","content":"Resposta final..."}}}
{"type":"chat.error","id":"msg-1","payload":{"code":"backend_unavailable","message":"..."}}
{"type":"session.updated","id":"cfg-1","payload":{"mode":"timeline"}}
{"type":"conversa.update","id":"conv-1","payload":{"turnos":[...]}}
{"type":"pong","id":"ping-1"}
```

### Conversa em tempo real

- `conversa.subscribe` responde na hora com um snapshot do disco e passa a
  receber `conversa.update` (lista completa de turnos) a cada turno novo ou
  limpeza — desktop e celular veem a mesma thread sem refresh.
- O cliente reconcilia pelo `turno.id`: turnos que já tem não entram de
  novo; mensagens locais sem correspondência no disco (erro de turno,
  interrupção) ficam na thread.
- No meio de um turno local o cliente ignora o push (a thread local manda);
  o `chat.result` do próprio turno atualiza o que falta.

Na v1 o turno é final, sem stream de tokens. Eventos de tool call ficam para uma
versão futura porque o `ChatEngine` atual devolve o turno resolvido; isso evita
criar evento que a engine não consegue honrar.

### Erros WebSocket

```json
{"type":"error","id":"msg-1","payload":{"code":"busy","message":"chat turn already running"}}
```

Códigos reservados:

- `invalid_message` — JSON ou `type` inválido.
- `busy` — turno em progresso.
- `backend_unavailable` — nenhum backend local respondeu.
- `tool_denied` — política recusou uma tool.
- `arena_unavailable` — MCP/REST não respondeu.

### Monitor do Arena

O daemon é quem polla o REST do Arena em `GET` read-only (intervalo de 1 s).
O front assina o canal e nunca fala com o Arena diretamente. A assinatura é
correlacionada pelo `id` do cliente:

```json
{"type":"monitor.subscribe","id":"mon-1"}
```

O daemon responde com a composição bruta do Arena quando ela muda:

```json
{"type":"monitor.update","id":"mon-1","payload":{"composition":{}}}
```

Na falha (e só na transição ok → falha), o daemon avisa e continua tentando:

```json
{"type":"monitor.error","id":"mon-1","payload":{"code":"arena_unavailable","message":"Arena REST unavailable"}}
```

- Enquanto o cliente mantém o WS de monitor, o daemon mantém o poll. Quando o
  cliente fecha o socket, o daemon cancela o poll — nada de escrita, nada de
  preferência do Arena.
- As thumbnails continuam por proxy HTTP (`image/*`) nesta tacada.

### Monitor do sistema

- `GET /monitor` fica no próprio daemon e serve SSE com o contrato v1 do
  sistema (CPU, memória, GPU, rede, portas, NDI, MIDI, Art-Net, captura,
  áudio, displays e processos).
- A coleta é lazy: cada conexão faz `attach`; fechar a conexão faz `detach`
  e o loop de coleta para quando não sobra cliente.
- `POST /monitor/processes/{pid}/terminate` só aceita um `pid` presente no
  snapshot atual do monitor. Não é escrita no Arena.
- O cliente usa o caminho relativo na mesma origem; em dev, o Vite passa
  `/monitor` para o daemon `127.0.0.1:1980`.

## Regras da engine

- Histórico permanece dentro da engine; a UI não envia histórico.
- Toda escrita autorizada precisa passar por `WriteJournal`.
- `ModeGate` decide `timeline`/`performance`; a UI só envia a intenção.
- O cliente não manda prompt de sistema e não pede ferramenta diretamente.

## Fluxo de dev do cliente (Vite)

- O cliente é um bundle estático construído por Vite; não há server de app nem
  banco no processo. Em dev, `npm start`/`npm run dev` sobe o Vite fixo em
  `http://localhost:3003`; `npm run build` gera `dist/` e `npm run preview`
  serve o bundle pronto na mesma porta. **(docs: conversa)**
- Em dev, o Vite faz proxy de `/api/v1` (HTTP e WebSocket) para o daemon
  `http://127.0.0.1:1980`, mantendo o cliente no mesmo origem; em produção o
  `dist/` pode ser servido pelo próprio daemon e as chamadas são relativas.
- Não existe mais porta de HMR a dividir com o Arena: o `8080` do antigo
  Meteor/Rspack sumiu com a migração (histórico nas tacadas 44–47), e o REST
  do Arena nesta máquina fica em `8008` ou no default de fábrica `8080`.
  **(medido: conversa)**
- Nenhuma dessas portas é contrato: o daemon continua fixo em `127.0.0.1:1980`
  e o front em dev roda na porta que o operador escolher, sem tocar no Arena.

## Persistência e nuvem

- A persistência local do daemon mora em `~/.resolux`: `sessao.json` guarda a
  sessão restaurada no boot e `conversas/conversa.json` guarda os turnos
  `{"turnos":[...]}`. Sincronizar na nuvem depois é trocar essa pasta de
  bandeja, sem mudar o contrato.
- Banco não entra no workflow local: chat, toolcalls, MCP, Arena e estado ativo
  rodam sem Supabase, Mongo ou qualquer nuvem.
- O cliente pode subir autenticação e backups só em idle; a nuvem nunca faz
  parte do caminho crítico do turno e nunca pode bloquear resposta.
- O daemon continua a fonte de verdade do estado ativo. Sync remoto usa o que o
  cliente já recebeu/exportou; o motor não conhece Supabase nem Mongo.
