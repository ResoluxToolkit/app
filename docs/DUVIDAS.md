# Dúvidas acumuladas (te responder quando voltar)

Regra nossa: chute vem marcado. Abaixo, o que eu preciso do seu voto de
autoridade de domínio. Não travei nada disso em código.

## 1. Advanced Output: `Input Source = "0:1"` é o quê?
No seu `Presets/Advanced Output/Spike.xml`, o `Slice` tem
`<ParamChoice name="Input Source" value="0:1">`. Sem você me dizer, não sei se
é `deck:layer` ou `layer:deck`. Não vou adivinhar porque isso aí é o arquivo da
obra de arte, e errar aqui é mexer na geometria que você calibrou na mão.

## 2. Autorar preset de Advanced Output conta como "configurar o Arena"?
Sua regra é Arena imutável. Nós não tocaríamos em Preferences nem em Wire. Mas
escrever um `.xml` de preset novo na pasta de presets é, tecnicamente, criar
arquivo na instalação dele. Preciso da linha exata: (a) podemos escrever preset
e pedir pra ele carregar, (b) só lemos e nunca escrevemos, ou (c) geramos um
`.avc`/preset num canto fora da pasta e a pessoa importa sozinha.
Enquanto não decidir: **só leitura**. Nada no repo escreve XML de saída.

## 3. Qual backend é o default? (isso muda o produto)
Medi com `stream:false` e o system prompt real do motor:

- **Ollama** (`qwen3:1.7b`, :11434): aceita as 22 ferramentas e devolve
  `tool_calls` de verdade. Loop completo funciona. Turno leva ~30–120 s.
- **Apple FM** (`fm serve`, :1976, modelo `system`): aceita só as **10
  ferramentas mais baratas** (3.986 tokens de prompt → HTTP 200). A 11ª já
  devolve HTTP 500, mesmo sendo barata. E entre as que ficam de fora está
  justamente `layer` — ou seja, **"quantas camadas tem?" fica sem resposta
  honesta pelo caminho Apple.** Também escreve a tool call como texto (a gente
  resgata, mas é gambiarra por natureza).

### Respondida pelo operador (2026-09-27) — fecho aqui
Voto dele: *"Pra mim, o que seria elegante é: Foundation Models de cara, se o malandro não
configurou/não souber. Mas pelo menos ele não fica com nossa principal ferramenta sem
funcionar."* Então **Apple primeiro, Ollama como rede de segurança** -- o oposto da minha
escolha anterior, invertido em código (`LocalChatBackend.preferredOrder` + o arquivo de testes
`BackendPreferenceTests`). Ele aceitou de olhos abertos o custo de cobertura (10 ferramentas,
`layer` fora), e a consequência virou regra de UI: quando estiver no Apple, o app diz
**"Você está capenga"** em vez de fingir que são 22.
Anotação do mesmo voto: **offline é restrição real** (tem venue sem internet) e embutir modelo
grande está fora ("a gente vai foder um software") -- a ordem escolhe entre o que já está de pé
na máquina; nunca baixa peso, nunca nuvem.

## 4. Correção de registro (erro meu, registrado pra não repetir)
Na rodada anterior eu afirmei "21 ferramentas passaram no fm". **Era falso**: eu
esqueci `stream:false`, o fm respondeu SSE com HTTP 200 e eu li como sucesso.
A escada honesta é a do item 3. Já existe teste prendendo o número
(`ToolAllowlistTests.swift`) e o transporte agora rejeita `text/event-stream`
com erro legível.

## 5. Portas de roteamento
Medido nesta máquina com TouchDesigner aberto: TD segura UDP `*:10000` (seu
"ele usa 10.000 em tudo" estava certo), Arena REST `:8080`, OSC `:7000`, além
de Art-Net UDP `:6454`. `5000` ocupada pelo AirPlay Receiver. Livres: `9000`,
`9001`, `1000`.
Nossa regra: nunca tocamos nas portas do Arena nem nas do TD em uso; nós
sentamos em cima (cliente) ou numa porta livre. Confirma `9000` como nossa
saída quando a gente tiver superfície própria, ou prefere que a gente continue
sem abrir porta nenhuma?

## 6. Conectar no abra do app, ou botão?
Tirei todos os campos (API key / base URL / modelo sumiram da tela). Hoje sobrou
um botão "Conectar ao Arena". Dá pra abrir e conectar sozinho, zero clique. Mantive
o botão porque a falha precisa aparecer na cara da pessoa com motivo ("abra o
Arena", "nenhum provedor local"). Você decide.

## 7. Coisas que ainda não fiz (sem dúvida, só fila)
- ~~Endurecer `.readWrite`.~~ **Feito nesta tacada:** `ToolPolicy.neverActions` barra
  em qualquer modo `clip.set_transport`, `composition.open/new/save*`, destruição de
  conteúdo e `batch`. Nomes todos conferidos no schema real por teste.
- **Falta o seu voto num chute que deixei embutido:** embuti veto permanente também em
  `autopilot.set`, porque me parece perigoso dois autômatos (o Arena e o bot) brigando
  pelo mesmo crossfader. Isso é regra de VJ, minha opinião não vale aqui: manutenção o
  veto ou libero no modo escrita?
- Escrita que chega por `parameter.set` genérico ainda passa no modo escrita. Se ela
  conseguir virar `clip.type` de Timeline pra BPM Sync por esse caminho, meu veto está
  incompleto e preciso saber — não testei esse caminho porque testar é mexer no set.
- Tela que resume o projeto (camadas/decks/colunas, transporte por clipe, o que
  está tocando, relógio, saída por display). 100% leitura.
  Detalhe que muda o desenho: pelo Apple isso é **inrespondível** (`layer`/`effect`
  não cabem na janela de contexto, §4 da HANDOFF). Nasce falando com Ollama ou direto.
- **Onboarding de recursos vira peça da tela, não rodapé.** Aplicando a regra nova
  (HANDOFF §2) no que já medimos, a tela de saúde tem três andares e nenhum deles é
  código nosso de codec: (1) **saúde do material** via `file { action: "info" }`, que já
  devolve `Codec:` + `Performance:` e a frase deles mandando pro Alley. Ajuste que veio
  da explicação dele sobre escala: esse aviso **não é vermelho automático** -- um H.264
  numa comp de 3 camadas não é problema, é incêndio numa de 200 colunas. Então a cor da
  linha pesa pelo tamanho da composição, nunca pela string sozinha; (2) **o que o
  Arena faz sozinho** -- botão direito no clipe -> `Render To File`, com o aviso de que a
  aba `Render` não está na View default (pede `Show Render`); (3) **o que a gente
  deliberadamente não faz** -- Collect Media e conversão em lote, porque são GUI e o
  Media Manager salva a composição antes de agir. Isso é conteúdo escrito, não bug.
- Varredura de porta por protocolo = relatório de diagnóstico, fim de projeto.
- **Defeito medido nesta tacada (ainda não corrigido): o bot local não converge.** Nos dois
  loops vivos de `swift test` com Ollama (`qwen3:1.7b`, pergunta "quantas camadas tem a
  composição agora?") a resposta final foi `Limite de 8 rodadas de ferramentas atingido.` e, na
  outra corrida, uma lição de ~15 linhas sobre "read-only mode" sem nunca entregar o número. Ou
  seja: o modelo pequeno fica chamando ferramenta sem fechar o turno. O teste passa porque só
  exige que a ferramenta MCP tenha sido chamada -- ele **não** prende a qualidade da resposta.
  Consequência prática pro seu voto: com Apple FM de cara, esse sintoma tende a aparecer mais
  (escreve tool call como texto + janela curta). Precisa de decisão de produto antes de eu
  mexer: aumentar rodadas, forçar resposta final após N rodadas, ou exigir resposta textual
  quando a recusa vier. Não ajusto isso no escuro porque é comportamento do chat que você usa.

## 8. Vídeo: linkar contra qual `libndi`? (só quando houver pixel pra mover)
Tu disseste "NDI, sempre na mesma versão do Arena" e Syphon ninguém usa. Concordo
com os dois, e medi as duas pontas: o Arena carrega o NDI dele mesmo
(`/Applications/Resolume Arena/libndi.dylib`, string interna **SDK 6.1.1**), enquanto
o que está instalado nesta máquina é **6.3.2** (apps NDI build 260413 e
`/Library/NDI SDK for Apple/Version.txt` = `v6.3.2.0`). Ou seja: "mesma versão do
Arena" hoje significa 6.1.1, e o caminho disso vive dentro do `.app` dele -- se ele
atualizar, nosso vínculo muda sozinho. Duas perguntas, na ordem:
1. Confirmo Syphon morto pra gente? Registro justo: o site é arqueologia (último
   comentário público que achaste é de abril/2009, era v002/openFrameworks), mas o
   `Syphon.framework` continua dentro do Arena 7.28.0 de hoje. Minha proposta: NDI
   como caminho oficial; Syphon no máximo como ponte TD↔gente em macOS, nunca como
   formato que empurramos pra terceiros.
2. Quando chegar a hora (ainda não é): casar com o `libndi` do Arena (6.1.1, obedece
   tua regra mas mora dentro do pacote deles) ou com o SDK instalado (6.3.2, caminho
   estável)? Não quero decidir isso sozinho porque é regra de pipeline de venue.
Nada disso entra em código agora: o pedido atual é **um previ**, e entrada HDI/3D
fica no TouchDesigner. Só quero a regra escrita antes de existir o primeiro pixel.

## 9. Conversão pra DXV: a gente chama o Arena como? (não é código de codec)
Tu disseste "na API do Arena tem como jogar os MP4 pra conversão, não precisamos ter
isso" -- e tu tinhas razão, eu tinha escrito o contrário e já corrigi no HANDOFF. A
conversão tá configurada no teu `config.xml` (`Codec="DXV 3"`, Normal Quality With
Alpha, tanto em RecordSettings quanto RenderSettings). Só que **não achei porta pra
isso**: nenhuma das 22 ferramentas MCP fala de conversão/import, e `/api/v1/media`,
`/api/v1/convert`, `/api/v1/files`, `/api/v1/library` deram todos 404 no teu Arena
7.28.0. Três caminhos, e a escolha é tua porque é fluxo de trabalho de operador:
1. **Zero código (meu chute preferido hoje):** a gente não converte nada, só aponta o
   MP4 pro Arena carregar (`file loaded` + abrir clip) e o Arena converte sozinho do
   jeito que tu já configuraste. Simples, não toca em preference nenhuma.
2. **Chamar a UI** (Media Manager / Render por AppleScript ouAccessibility): poderoso,
   mas o Media Manager **sempre salva a composição antes** de agir -- e isso escreve no
   arquivo de estado do set. Num set emprestado, isso é inaceitável sem pedir.
3. **Ferramenta externa de encode DXV:** não rola, vai dar merda -- codec proprietário
   num binário nosso é problema de licença e de formatação, e é exatamente o que tu
   disse pra gente não implementar.
Pergunta concreta então: quando um MP4 chegar na nossa mão, eu só peço pro Arena
carregar e ele resolve, ou tu quer que a gente mostre o arquivo como "não otimizado" e
deixe o operator decidir? (É leitura da coluna *Compression* do Media Manager, que
apareceu na tua screenshot -- `Unknown` vs `DXV 3.0 Normal Quality`.)
### Desdobrando depois de medir (mesmo item, nao e nova duvida)
Achei o `Resolume Alley` instalado aqui, que e pra onde a propria API manda quando o
codec e ruim. Ele **nao tem CLI** aparente (app de documento, sem flags de batch), entao
a opcao 3 continua fora. O que mudou: `file { action: "info" }` ja devolve
"Slow codec (H.264) ... Transcode to DXV with Resolume Alley" -- ou seja, a gente le o
diagnostico pronto, nao precisa decifrar nada nem abrir Media Manager. Restam as duas
perguntas de cima, agora com custo conhecido: so-carregar (zero risco, zero codigo) ou
mostrar-sinal-e-deixar-o-operator-decidir (minha aposta -- e o modo Arena-imutavel).

### Respondida pelo proprio operador (fecho aqui, sem voto pendente)
Ele resolveu isso pelo caminho que so quem tem 25 anos de Arena conhece: **botao
direito no clipe -> `Render To File`**, que usa o Preset ja configurado (a lista comeca
em DXV 3) e nao toca na composicao inteira. Entao a resposta da duvida e a terceira
opcao que eu nao tinha visto: **a gente nem oferece conversao -- o operator converte na
mao dele quando quiser, e a nossa funcao e explicar isso** (regra nova do onboarding no
HANDOFF §2, com as palavras dele: *"O que nao der pra fazer, a gente explica"*).
Unico cuidado que a gente assume por ele: avisar que **a aba `Render` nao aparece na
View default** -- precisa `Show Render`. Sem esse aviso, ele ia achar que quebramos
alguma coisa. Detalhe em HANDOFF §4, bloco `Render To File`.
