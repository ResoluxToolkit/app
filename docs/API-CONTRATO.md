# Resolux API v1 — contrato

Este arquivo é a fronteira única entre a engine Swift e o cliente web. A engine
é dona da versão; a UI não inventa endpoint nem formato novo.

## Base

- Daemon: `ResoluxServer`, escutando apenas em `127.0.0.1:1980`.
- Cliente web conversa com o daemon; não fala MCP, Ollama, Apple FM nem REST do
  Arena diretamente. Protocolos externos ficam no adaptador do daemon.
- HTTP: `http://127.0.0.1:1980/api/v1`.
- WebSocket: `ws://127.0.0.1:1980/api/v1/ws`.
- JSON `utf-8`; campo `Content-Type: application/json`.
- Erro HTTP sempre em envelope: `{"error":{"code":"...","message":"..."}}`.
- Sem rede externa e sem CORS. Origem aceita: `localhost`, `127.0.0.1` e mesmo
  host resolvido como `::1`.
- `ToolPolicy` permanece read-only e deny-by-default. Escrita só aparece na API
  quando o operador mudar esse voto.

## HTTP

| Método e caminho | Uso | Resposta |
|---|---|---|
| `GET /api/v1/health` | sonda do daemon | `{"protocol":"resolux-api/1","status":"online"}` |
| `GET /api/v1/session` | estado atual da engine | `{"protocol":"resolux-api/1","mode":"timeline","backend":"ollama","model":"qwen3:1.7b","toolPolicy":"readOnly","toolsAllowed":22,"journalEnabled":true}` |
| `PATCH /api/v1/session` | muda só estado permitido | mesmo corpo de `GET /api/v1/session` |
| `GET /api/v1/tools` | ferramentas visíveis ao modelo | `{"tools":[{"name":"composition.get","description":"..."}]}` |
| `GET /api/v1/arena/**` | proxy read-only do REST do Arena | JSON do Arena |
| `HEAD /api/v1/arena/**` | proxy read-only | headers do Arena |

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
- O proxy não reescreve JSON; repassa status, corpo JSON e content type.
- Se o Arena não estiver aberto, responde `502` com
  `{"error":{"code":"arena_unavailable","message":"Arena REST unavailable"}}`.

### `PATCH /api/v1/session`

Campos opcionais; campo desconhecido volta `400`:

```json
{"mode":"timeline","backend":"ollama","model":"qwen3:1.7b","toolAllowlist":["composition.get","layer.list"]}
```

Valores aceitos nesta versão:

- `mode`: `"timeline"` ou `"performance"`.
- `backend`: `"ollama"` ou `"applefm"`.
- `toolAllowlist`: lista de nomes declarados em `/api/v1/tools`; `null` volta a
  oferecer todas as ferramentas.
- `toolPolicy` não é configurável: fica read-only nesta versão.

## WebSocket

Toda mensagem é um objeto com `type`. Mensagens de cliente devem ter `id` para
correlação. Só um turno `chat.send` por conexão; outro turno antes de terminar
recebe `busy`.

### Cliente → engine

```json
{"type":"chat.send","id":"msg-1","payload":{"text":"Quantos clipes tem agora?"}}
{"type":"session.update","id":"cfg-1","payload":{"mode":"timeline"}}
{"type":"ping","id":"ping-1"}
```

### Engine → cliente

```json
{"type":"hello","payload":{"session":{"protocol":"resolux-api/1","mode":"timeline","backend":"ollama","model":"qwen3:1.7b","toolPolicy":"readOnly","toolsAllowed":22,"journalEnabled":true}}}
{"type":"chat.started","id":"msg-1"}
{"type":"chat.result","id":"msg-1","payload":{"message":{"role":"assistant","content":"Resposta final..."}}}
{"type":"chat.error","id":"msg-1","payload":{"code":"backend_unavailable","message":"..."}}
{"type":"session.updated","id":"cfg-1","payload":{"mode":"timeline"}}
{"type":"pong","id":"ping-1"}
```

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

## Regras da engine

- Histórico permanece dentro da engine; a UI não envia histórico.
- Toda escrita autorizada precisa passar por `WriteJournal`.
- `ModeGate` decide `timeline`/`performance`; a UI só envia a intenção.
- O cliente não manda prompt de sistema e não pede ferramenta diretamente.

## Fluxo de dev do cliente (Meteor)

- Em dev, a porta principal do Meteor (`meteor --port`) define onde o client
  sobe, e as outras portas do processo derivam dela: mudar a principal desloca
  todas juntas. Medido no `frontend` desta máquina: **(medido: conversa)**
  - `meteor` → app `3000`, HMR (Rspack) `8080`, Mongo `3001`.
  - `meteor -p 3003` → app `3003`, HMR `8083`, Mongo `3004`.
  - Padrão observado: Mongo = principal + 1; HMR anda junto com a principal
    (delta da principal aplicado sobre o base `8080`).
- Atenção: o default do HMR do Meteor (`8080`) é o mesmo default de fábrica do
  REST do Arena — os dois não dividem porta; nesta máquina o Arena estava em
  `8008` e só voltou ao `8080` depois de o front fixar `--port 3003`.
  **(medido: conversa)**
- Voto do operador: o trio default (app `3000`, HMR `8080`, Mongo `3001`) é
  portas de serviço interno, sem efeito no cliente — e é o que se altera. Em
  dev o front fixa `--port 3003`: app `3003`, HMR `8083`, Mongo `3004`.
  **(docs: conversa)**
- Nenhuma dessas portas é contrato: o daemon continua fixo em `127.0.0.1:1980`
  e o front em dev roda na porta que o operador escolher, sem tocar no Arena.

## Persistência e nuvem

- Banco não entra no workflow local: chat, toolcalls, MCP, Arena e estado ativo
  rodam sem Supabase, Mongo ou qualquer nuvem.
- O cliente pode subir autenticação e backups só em idle; a nuvem nunca faz
  parte do caminho crítico do turno e nunca pode bloquear resposta.
- O daemon continua a fonte de verdade do estado ativo. Sync remoto usa o que o
  cliente já recebeu/exportou; o motor não conhece Supabase, Mongo nem Meteor.
