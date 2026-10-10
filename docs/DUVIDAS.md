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

## 10. Posse da sessao: quem decide, quanto tempo vale, o que acontece na queda
Aberto pela regra nova dele (*"o operador que entrar primeiro trava a sessao"*).
Nao e detalhe de UI -- e gate de escrita, e as tres respostas mudam codigo. Eu tenho
preferencia em cada uma, mas nenhuma e minha pra decidir sozinho: e comportamento de
palco, e autoridade de dominio ai.

### 10.1 Quem e a autoridade de posse?
Minha proposta: **o Mac**. Motivo: e ele quem fala com o Arena, entao a decisao de
escrever tem que morar onde a escrita acontece; se o celular mandasse, dois clientes
concorrentes viriam duas verdades e uma delas estaria errada na frente do VJ.
O que eu preciso saber: **existe caso em que o iOS tem que poder escrever quando o Mac
esta com a posse?** Se sim, nao e posse exclusiva -- e pedido e liberaao, e ai muda o
desenho (fila, nao trava).

### 10.2 Quanto tempo um lease vale sem heartbeat?
Em LAN/SHOW eu votaria curto (algo na casa dos 3-5 segundos) porque iPad perde socket
sem avisar ninguem e "refem de app morto" e o pior modo de falha possivel num palco: o
Mac fica recusando comando pra mao que esta de fato no controle. Contra-argumento que
justifica pedir sua palavra: TTL curto demais significa que um momentinho de Wi-Fi ruim
no meio da transicao devolve a posse pro Mac justamente na hora em que ninguem devia
tocar em nada. So voce sabe qual dos dois modos de falha te irrita menos ao vivo.

### 10.3 Ao reconectar, o dono antigo recupera a posse sozinho?
Minha posicao: **nao**. Reconectar e pedido, nao direito heredado -- se outro operador
pegou enquanto o app morreu, retomar em silencio significa dois automatos no mesmo
crossfader achando que cada um manda. Mas isso cobra um preco seu: se voce sair do app
pra atender algo e voltar, vai ter que pedir de novo (ou confirmar na tela). Quer esse
atrito a menos, ou quer a garantia?

### 10.4 O diario de escrita deve carregar a identidade do operador?
Hoje o `sessionID` do journal sai de data+UUID gerado no `init` do `WriteJournal`. Isso
**nao casa com a regra de posse**: se a identidade da sessao e do operador/lease, o
rastro tem que dizer quem fez, senao seis meses depois voce olha o arquivo e ve escrita
sem dono. Minha intencao e amarrar o `sessionID` ao lease (quem tem a posse nomeia o
arquivo), mas **so faco isso depois do seu ok** porque mexe no formato do registro que
acabei de escrever testes em cima.

### 10.5 O segundo que chega: recusa muda o quê na tela?
A recusa precisa vir com nome ("posse esta com <X>, desde <hh:mm>"), senao vira "bug de
rede" e a pessoa insiste. Falta saber se quem esta sem posse pode **ler** o set (relatorio
mudo) ou se perde a conexao inteira. Leitura sozinha nao toca em nada, entao minha
preferencia e deixar ler -- mas e seu produto.

### Respondida pelo operador (2026-09-27, checkpoint 6): quem readquire na reconexao
Dele: *"Se ele for o que 'criou' o evento. O sistema e monousuario, quem 'montou' ele e o
super admin."* E a ressalva que vem logo atras, que e a parte que desenha o codigo:
*"Esse cara nao pode sair derrubando quem estiver, tem que ter uma janela em que seja
seguro isso acontecer."*

O que isso resolve sozinho:
- O sistema e **monousuario por construcao**. Nao existe "dois operadores disputando" como
  estado normal -- existe o dono do evento e gente esperando. Isso derruba a ideia de fila
  de espera que eu tinha colocado como possibility em 10.1.
- Readquirir na reconexao **e direito do criador do evento**, nao de quem estiver conectado.
  Identidade de criador vence identidade de conexao.

O que a ressalva muda (e onde eu nao decido sozinho):
- **Readquirir vira PEDIDO com efeito no proximo momento seguro, nao preempcao imediata.**
  O criador chega, o gate marca a posse como "reivindicada pelo dono", e a virada so
  acontece na janela. Enquanto isso quem esta no comando continua mandando -- senao a
  ressalva dele nao valeria nada.
- **Falta a definicao de "janela segura", e essa e a pergunta que ficou.** O formato eu
  proponho, o predicado e dominio dele. Candidatos que ja temos leitura pra medir hoje
  (`transport {get}`, `crossfader {get}`, `composition {playing}`, `monitor {diff}`):
  nenhuma escrita nossa em andamento; transporte nao em transcicao; crossfader estavel.
  `chute:` transcicao de crossfader em curso e exatamente o momento proibido -- e quando
  a plateia esta vendo duas camadas ao mesmo tempo.
- Limite honesto do gate: a janela segura e em relacao ao que **nos** escrevemos. A mao
  dele no console do Arena a gente nao enxerga. Gate protege automacao de automacao, nao
  ele de si mesmo.
- Teto que ele precisa definir: se a janela segura nunca chega (segundo operador fica
  mexendo sem pausa), o dono do evento espera ate quando? Sem teto, um operador confuso
  pode sentar na posse a noite inteira num show de tres horas.
- **Persistencia da identidade do criador.** Se "quem montou o evento" nascer so em
  memoria, no reboot do Mac ninguem e super admin -- a gente ou tranca todo mundo ou
  deixa qualquer um reivindicar. Tem que ir pra disco junto com o evento.
- Consequencia pro diario (fecha 10.4 por dentro): com posse nomeada e bastao passando,
  o journal precisa ter **linha de troca de posse**, senao o rastro mostra escrita sem
  fronteira entre quem fez o que. E o `sessionID` passa a ser identidade de evento +
  operador, nao data+UUID.

### Predicado da janela segura: respondido (2026-09-27, checkpoint 6) -- e nao e tecnico
Dele: *"Em eventos, existem momentos criticos: p. ex. na hora do Hino Nacional. Nessa hora,
trocar de operador, nem fudendo."*

Isso mata minha proposta tecnica como criterio. Crossfader estavel e transporte parado sao
condicao **necessaria**, nao suficiente: durante o Hino o set pode estar perfeitamente quieto
e mesmo assim e o pior momento possivel pra qualquer virada, porque se der merda ali **todo
mundo esta olhando** e nao tem trilha pra cobrir o silencio. A janela segura nao se deduz do
estado do Arena -- ela e **declarada**.

Desenho que isso implica (nao vou codar sem seu ok):
- O evento carrega uma **agenda com blocos criticos**. Fora dos blocos: posse readquirivel no
  proximo momento tecnicamente calmo. Dentro de um bloco: **nada muda**, ponto. Bloco critico
  nao tem override, nao tem "confirmar anyway", nao tem admin pulando -- o "nem fudendo" dele
  e literal. Se o criador do evento pudesse furar o proprio bloqueio, o bloqueio nao existe.
- `chute:` dentro de bloco critico eu ampliaria o congelamento pra alem da troca de posse:
  nenhuma **escrita** nossa (so leitura). Motivo: se a preoccupacao e nao produzir nada
  visivel-e-irreversivel num momento de atencao total, troca de operador e so o exemplo mais
  dramatico. Votar: bloqueia so posse, ou bloqueia escrita inteira no bloco?
- **Hora escrita nao vale nada em evento ao vivo** -- e aqui eu discordo de agendar por
  relogio. Hino atrasa quatro minutos porque a autoridade chegou tarde, e nao tem como saber.
  Entao o bloco critico precisa de **armar/desarmar na mao**, com a agenda servindo de lembrete
  ("proximo: Hino, 18:00"), nao de gatilho automatico. Gatilho por relogio ia congelar o
  comando errado na hora errada. Precisa do seu voto: armar na mao sempre, ou agenda tambem
  arma sozinha quando bate o horario?
- Consequencia de UI: o estado "evento esta em momento critico" tem que estar visivel pros
  dois lados, senao o segundo operator le recusa e acha que e bug. E o journal ganha linha de
  **abertura e fechamento de bloco critico**, porque "quem fez o que" so faz sentido sabendo
  em que regime foi feito.
- Nota de alcance honesto: bloco critico governa o que **nos** fazemos. Nao impede ninguem de
  mexer no console do Arena nem de puxar o cabo. E um gate de automacao, nao cadeado.

## 11. De onde vem a criticalidade (aberta por ele no checkpoint 6)
Pergunta dele: *"Como que o sistema sabe da criticalidade? Vamos no futuro, se meter na parte
de roteiro/historyboard tb."*

Resposta curta: **o sistema nao sabe, e nao pode fingir que sabe.** Nao existe um bit no Arena
que diga "isto e critico". O Hino e critico porque **ele** decidiu que e -- entao a
criticalidade e uma propriedade do **evento**, nao do set. Isso tem consequencia de desenho:
nao adianta procurar em `tools/list`, nem derivar de BPM, nem inferir de crossfader. Vai ter
que existir um artefato nosso, autor por quem montou o evento.

### O objeto que resolve isso (e o mesmo do historyboard)
Rundown / roteiro: uma lista ordenada de blocos do evento, cada um com nome, hora prevista
(opcional) e a flag `critico`. Ex.: credenciamento -> abertura -> autoridade fala -> **Hino**
-> Transicao 1 -> bloco musical... A partir dai:
- **Criticalidade = flag do bloco atual.** Gate le o bloco corrente, nao o relogio.
- Avancar o bloco e gesto humano (ele diz "entrei no Hino"), igual ao armar/desarmar que eu
  tinha proposto -- so que agora com nome e contexto na tela, nao um botao solto de "bloquear".
- O journal passa a marcar a **troca de bloco**, e ai "quem fez o que" ganha sentido historico:
  escrita dentro do bloco Hino e outra categoria de escrita.
- O historyboard que ele quer no futuro nao e feature separada: e o mesmo arquivo crescendo
  (bloco -> cue -> alvo no set). Fazer o gate com esse formato desde ja evita retrabalho.

### Costura que eu faco agora (decisao minha, avisada, nao pedindo voto)
O gate nao deve conhecer roteiro -- ele conhece um **provedor de criticalidade** (`chute:`
nome `CriticalitySource`). Implementacao de hoje: `manual` (arma/desarma na mao). Implementacao
de amanha: roteiro, que escreve no mesmo sinal. Assim o gate fica congelado e testavel, e o
historyboard entra sem tocar no gate. Se eu amarrar o gate direto no relogio ou no Arena, no
dia que o roteiro chegar eu reescrevo a parte que mais exige confianca -- isso e o tipo de
economia que sai cara.

### O que o Arena ainda pode ajudar (corroboracao, nunca autoridade)
Nao decide nada, mas da checada de sanidade: `composition {playing}` e posicao de transporte
dizem se o que ele esta tocando parece condizer com o bloco declarado ("bloco = Hino, transporte
parado ha 40 s -- confirma?"). Vale como alerta, nao como gatilho: falso-positivo aqui custa o
show.

### Perguntas que ficam pra ele (nessa ordem de importancia)
1. **Roteiro vive onde?** Arquivo nosso (JSON/property-list em `Application Support`, editavel
   fora do app), pasta compartilhada, ou telinha dentro do app macOS? Zero-config nao significa
   zero-autor: alguém precisa digitar os blocos, e a regra dele proibe campo de IP/config, nao
   roteiro proprio.
2. Hoje, **antes** do roteiro existir: aceita o gate com arma/desarma manual e a criticalidade
   vindo de um botao, ou prefere que eu so implemente o gate quando o roteiro nascer junto?
   (Minha preferencia: manual agora, porque assim o gate existe e e testavel; o roteiro so troca
   a fonte do sinal.)
3. Bloco critico e **flag binaria** ou tem gradacao (ex.: "critico: nada muda" vs "atencao: só
   leitura, posse ate pode mudar")? So pergunto porque gradacao muda o formato do arquivo e nao
   da pra adicionar depois sem migrar.

## 12. Sync e ultima hora: duas ressalvas dele que mudam formato (checkpoint 6)
Ele leu minha frase sobre "amarrado no relogio" e respondeu com duas coisas. As duas viram
requisito, nao observacao.

### 12.1 "Isso me lembrou da parte de sync" -- porque "relogio" e ambiguo aqui
Neste repo "relogio" ja significa **duas coisas diferentes**, e e ai que o sync morde:
- **Horario do dia** (18:00, Hino): e o relogio do qual o gate nao pode depender -- atrasa,
  como ele mesmo ja concordou.
- **Relogio do Arena** (transporte/BPM/posicao): cada clipe tem o proprio `clip.type`
  (Timeline, BPM Sync, SMPTE 1/2, Denon DJ, Pioneer DJ e variantes) -- por isso o system
  prompt ja exige declarar fonte do relogio antes de citar BPM. E um relogio de **andamento**,
  nao de horario. Ele e a coisa mais facil de errar ao vivo, nao uma autoridade de agenda.
Somando: na lista de ferramentas do Arena existem `create_ltc_timecode_bridge`, `sync_timecode`
e `connect_lighting_console_osc`. Isso e o ponto que ele puxou: se a venue toca com **LTC /
timecode**, existe um relogio externo que e de fato confiavel -- e ele vem do equipamento, nao
do relogio de parede nem do BPM do clipe. Nesse caso avancar bloco pode ser ancorado em LTC,
e passa a fazer sentido ter hora no roteiro *como referencia visual*, nunca como gatilho.
Mas LTC e sync e equipamento: e chao de decisao dele, meu nao. O gate continua lendo o bloco
corrente declarado; LTC entra como corroboracao/clock externo, nunca como quem decide.
**Pergunta:** alguma venue que voce faz alimenta LTC/timecode (ou lightboard com cue por
timecode)? Se sim, o artefato do roteiro precisa de campo opcional de marcacao de tempo -- e
e mais facil por isso hoje do que migrar depois. Se nao, o roteiro nasce so com ordem + nome
+ flag, sem tempo nenhum.

### 12.2 "DIA? -- chega um minuto antes, a ultima alteracao"
Rido merecido: eu escrevi "no dia que o roteiro chegar" como se roteiro fosse documento
aprovado com antecedencia. Ele nao e. Na pratica **o roteiro muda no ultimo minuto, com o show
em curso** -- blocos inseridos, ordem trocada, um bloco promovido a critico porque a
autoridade resolveu falar. Consequencia dura, e essa sim muda codigo:
- **O arquivo e lido quente.** Gate nao tira snapshot no inicio e nao pode cacheiar a
  criticalidade pra vida toda: precisa reler/observar o rundown e reagir ao arquivo mudado,
  sem restart e sem recompilar. Se precisar reiniciar o app pra valer a alteracao, o recurso
  e lixo no dia do show.
- **Bloco corrente referenciado por ID estavel, nunca por posicao.** Se eu guardar "bloco 3"
  e alguem insere um bloco no topo as 17:59, o indice aponta outra coisa -- quer dizer que um
  erro de digitacao pode **tirar o evento do bloco critico em silencio**. Com ID, inserir e
  reordenar nao move a posse de contexto; mudar o bloco atual continua sendo gesto explicito.
- **Editar o rundown nunca desarma nem re-escolhe nada por conta propria.** Adicionar bloco,
  renomear, trocar hora prevista: tudo isso tem que ser inofensivo enquanto o bloco atual esta
  critico. Mudanca de estado so por mao humana.
- Journal registra o **ID do bloco** em cada linha, junto com a troca de posse/bloco -- senao
  o rastro fica apontando pra posicao de um arquivo que ja mudou tres vezes.
- Nota honesta: "editado a um minuto" implica tambem editar **sem estar no app** (ele no
  console, outra pessoa no notebook). Por isso reforco a pergunta 1 do §11: arquivo nosso
  editavel por fora vale mais que telinha fechada -- e aqui vira requisito operacional, nao
  preferencia de gosto.

### O que eu faco com isso (sem esperar voto)
Ordem de construcao nao muda: gate primeiro, lendo `CriticalitySource` manual. Mas com tres travas
que ja saem certas agora: ID de bloco desde o primeiro formato, leitura quente (nada de
snapshot eterno), e critica como flag que **nunca** se infere de estado. Assim a alteracao de
ultimo minuto, quando vier, bate numa porta que ja esta aberta.


## 13. A aula de cronometragem: chave Timeline/Performance (checkpoint 7)
Ele abriu a conversa com o desenho inteiro e eu repito aqui nas palavras dele, porque é
especificação, não comentário: **"Timeline: Calcula. Performance: Mede."** E a referência:
*"O Ableton Live é exatamente assim. Ele só tem isso, mais nada."* Session vs Arrangement — um
modo prepara, o outro executa, e o que executa não faz trabalho de escritório no meio do show.
Implementado em `OperationMode.swift` (`ModeGate`: timeline = cálculo+monitoração, performance
= só monitoração). **`chute:`** monitorar em timeline estar ligado — desligo se ele pedir.

Dois eixos separados e que não se misturam: `ToolPolicy.Mode` (leitura/escrita = o que posso
tocar no set) x `OperationMode` (que serviço ofereço). Performance pode estar `readWrite`
tranquilo: ele passa a ser monitorado, não deixa de operar.

### 13.1 O problema que a ferramenta resolve (e por que o Arena não resolve)
Arena **não é linear**: acesso aleatório, mas todo mundo monta como se fosse — clipe depois de
clipe. Vinheta que toca dez vezes aparece dez vezes na grade. Num editor, no fim da montagem você
olha a posição e sabe quanto tempo durou; no Arena **não**. Ele sempre quis isso: pôr dez vídeos
um do lado do outro e saber quanto tempo deu. **(pedido dele, literal)**

A pegadinha que ele mesmo levantou ("ué, mas que imagem é essa?"): detectamos **intenção**, e
intenção é **alto piloto**, nunca tamanho de grade. Se ele encadeou, quer que toque em sequência e
quer saber o tempo; se não encadeou, vai usar aquilo aleatório e a conta não significa nada.
Regra dura que sai daqui: **3 camadas × 9 colunas = 27 slots vazios é o berço do projeto** — todo
projeto novo nasce assim, então grade cheia/vazia **não sinaliza nada**. Nunca inferir nada de
dimensão de grade.

### 13.2 Delta time: frames nunca entram na conta
Nome dele pro conceito é o de jogo: **delta time** — tempo absoluto, independente de performance
da máquina. *"O projeto nasce com FPS auto."* **(medido:** `composition.framerate` = ParamRange
`value: 0.0` = Auto.**)** Cada arquivo traz o fps próprio e o tempo é a **duração do clip**,
independente do fps de cada um. Frame só importa pra imagem não engasgar — *"o frame só importa
pra imagem não ficar dopando"*. Muito operador chega e trava 60, porque a maioria dos painéis de
LED trabalha nessa frequência — isso é escolha dele, não entrada de cálculo. Consequência: **em
modo Timeline o BPM nem existe.** Premiere & cia exigiriam fps único no projeto inteiro; aqui não
acontece, e não vamos "consertar".
Código: `effectiveMS = durationMS / speed`, sem multiplicar nada por frame.

### 13.3 Sliders não são grandeza física (regra ±32768)
Palavra dele: *"Dica de ouro: Posição! Esse é o range dos sliders, então todo espaço tem 32768 de
tamanho, independente se esse tamanho é um metro ou um km."* E logo em seguida ele mesmo desfaz a
dica: é **limite nominal, não escala** — *"o cara pega um painel de 10 m e usa só 5000 U, o resto
vai parar na outra esquina"*. Tem parâmetro **normalizado 0…1** que apresenta unidade mas é fração.
Veredito registrado: **nenhum slider vira número na conta.** O espaço do venue é arbitrário; quem
precisa de metro é **projeção mapeada**, e isso é **fora de escopo declarado** — *"simplesmente
uma coisa que não oferecemos"*. Se um dia aparecer venue medido, é decisão nova dele, não
extensão nossa. (Nada hoje depende disso; a calculadora só lê `duration`/`speed`/`name`.)

### 13.4 Só entra número que o documento nomeia com unidade
Regra de higiene que ele aprovou: não inventamos grandeza. Entram na conta apenas campos que o
próprio payload nomeia como tempo — `transport.controls.duration` (**segundos**, ParamRange, min
0.001 / max 604800 = 7 dias) e `fileinfo.duration_ms` (**milissegundos**). Todo slider fica de
fora (§13.3). Isso também é o critério do log: número sem unidade no log é número mentiroso.
**(medido** na composição viva "Spike", Arena 7.28.0-rev24303.**)**

### 13.5 Imagem não tem duração: o padrão da casa é 1 s (já foi 5 s)
Toda imagem arrastada dura um tempo fixo parado, e ninguém muda isso. Ele primeiro disse 5 s e
corrigiu na hora: *"acabei de te dar uma informação falsa, não é mais 5 segundos, hoje em dia é 1
segundo só."* Valendo: **1 s** (`TimelineCalculator.imagemPadraoMS = 1_000`, fonte
`.presumida`). Por isso imagem tem três estados de execução mesmo sendo "parada" — ela consome um
slot de tempo.
Correção que sai de teste, e é importante: **imagem nunca herda `duration_ms` do arquivo**. O
`duration_ms` de um PNG não é tempo de tela, é número sem significado cronométrico; deixar o
arquivo falar inflaria a linha com tempo que nenhum operador programou. Precedência final:
**transporte (decisão do operador) > mídia (só áudio/vídeo) > padrão da casa (só imagem) >
nenhuma**. E `.nenhuma` **não vira zero** — zero faria a linha parecer mais curta que o show, o
pior erro possível pra uma ferramenta cujo único trabalho é dizer tempo. Tais slots vão pro
listado `semTempo` com endereço.

### 13.6 Alto piloto = Merge
*"Os blocos que tiverem em Auto Pilot a gente considera como se fizesse um Merge desses clipes:
ele quer que aquilo ali toque de uma vez."* Tradução em código: um rolo consecutivo encadeado numa
camada vira **um bloco só**, com total = soma do rolo, origem `.autoPilot`; o bloco para onde o
piloto desliga volta a ser `.avulso`. Detector é `autopilot.target`: por clipe o valor
`"Layer Determined"` **delega pra camada** — ignorar isso leria "Off" onde o operador ligou o
encadeamento. Na composição viva as 3 camadas estão `"Off"`, então hoje a calculadora **não se
oferece**: ele está escolhendo na mão. Intenção ligada = oferecer conta; desligada = silêncio com
motivo.

### 13.7 Synth é ferramenta morta
*"Synth não tem duração — Synth é performance, aí a gente nem se mete. Essa ferramenta é morta."*
Registrado como veto de escopo, não como gap. **(medido:** os 12 clipes da composição viva são
generators, `video.fileinfo` = `{}`/`null`; o total da linha hoje é 0.**)** Generator entra como
`.gerador`, `temMidia == false`, fora da soma, listado em `semTempo`.

### 13.8 Data: epoch segundos, ponto
Preferência pessoal declarada e vale pra tudo que a gente escreve: **epoch em segundos desde
1970-01-01**. *"em JS: Date().valueOf() kkk. ISO, GMT foda-se. Isso calcula depois."* Zero
fuso, zero locale, zero string — converte na apresentação, nunca no armazenamento. É o formato do
log nosso.
**Dúvida que precisa de voto (custo baixo agora, caro depois):** `WriteJournal.timestamp` nasceu em
**ISO-8601** (`ISO8601DateFormatter`) — violando a regra, anterior a ela ser dita. Converte pra
epoch já (`WriteJournal.swift`, e a linha ISO fixa em `WriteJournalTests.swift:178`) e troca o
formato em disco agora que o journal é jovem e sem arquivo histórico dele, ou aplica epoch só no
código novo e fica um registro com duas datas? **Minha recomendação: converter agora**, porque
depois de haver journal de um evento real o custo vira migração. Aguardo palavra — não mudo
formato de disco por conta própria.

### 13.9 Rename em lote pelo app (feature que ele puxou)
*"Uma coisa muito legal seria fazer o rename de tudo aí pelo app. É horrível no Arena."* E a regra
do `#`: **`#` é a posição do clipe** — renomear 20 colunas em ordem numérica é escrever `Clip #`
nas vinte. Confirmado por medida: o REST devolve `"Column #"` **cru**, quem numera é o Arena.
Consequência de implementação, escrita pra não errarmos sozinhos: **nós nunca expandimos e nunca
removemos o `#`** — escrevemos o literal e deixamos o Arena expandir. Se a gente "ajudar"
numerando, o produto duplica numeração e perde a ordem viva. Fila: renomear camada/coluna/deck em
lote com preview e `#`.

### 13.10 Performance: medir por fora, porque o HUD dele não é exportável
Ele mencionou o HUD do Arena (CPU 32% / RAM 45% / GPU 62% / FPS 63.6) e a dúvida "não sei se tem".
**Não tem** — varrido e provado: CPU/RAM/GPU **não existem** no REST (varri as 258 rotas do
`swagger.yaml`), **nem** nas 22 tools do MCP, **nem** em strings do binário. Então o modo
Performance medimos **nós**, e está validado:
- **GPU**: `IOServiceMatching("IOAccelerator")` → `IORegistryEntryCreateCFProperties` →
  dicionário `PerformanceStatistics` com `Device Utilization %`, `Renderer Utilization %`,
  `Tiler Utilization %`, `In use system memory`. Leitura sem privilégio. Calibrado: **72% nosso vs
  62% no HUD dele** (janela de amostragem diferente, mesma ordem de grandeza).
- **CPU/RAM**: `proc_pid_rusage(pid, 2, aliased)` sobre `rusage_info_v2` (`ri_user_time` off 16,
  `ri_system_time` 24, `ri_resident_size` 64, `ri_phys_footprint` 72). **Os campos são ticks de
  mach absolute time** — precisa multiplicar por `mach_timebase_info` numer/denom; sem isso o CPU
  sai ~41× pequeno (erro que cometi e que a medição desmentiu). Validado: **85,8% instantâneo vs
  `ps` 84,2%**, e vida útil 3419 s batendo exato. Cuidado com o comparativo: **`ps %cpu` é média
  de vida inteira**, não instantâneo — divergir não é bug nosso. Máquina: 8 CPUs / 8 GiB.
Probe utilizável: `/tmp/perf6.swift` (GPU), `/tmp/rus5.swift` (CPU/RAM). Volátil.

### 13.11 A API deles é mal documentada — então o método é medir
Veredito dele nesta tacada: *"Essa API deles é mal documentada."* Concordo, e ela virou método, não
lamento. As quatro vezes que a doc/instrução do servidor mentiu ou omitiu, todas com prova:
1. Instrução manda: *"Use the `batch` tool for all independent calls"* — e **vetamos `batch` para
   sempre** (§13.12). Servidor empurrando o caminho que não podemos andar.
2. `deck.layers` e `layer.columns` vêm **array vazio**: array do REST **não é posição**. Teria
   produzido grade lida às avessas. Endereço é `layers/{L}/clips/{C}` 1-based (1..9 ok, 10+ 404) ou
   `comp.layers[].clips[]`.
3. `composition.framerate.value = 0.0` não é "fps zero": é **Auto**. Doc nenhuma diz.
4. Duração real por clipe **só existe no REST**; as 22 tools MCP não devolvem duração. A rota de
   leitura que ele mandou achar é justamente essa.
Regra operacional que fica: **nada de afirmar comportamento do Arena sem payload na mão** —
`GET /composition` vivo é fixture barato, e a doc serve pra hipótese, nunca pra conclusão.

### 13.12 Tensão registrada sem silenciar: `batch`
As instruções do servidor ordenam agrupar toda chamada independente em `batch`. Nosso
`ToolPolicy` recusa `batch` em modo nenhum (`batch` não tem enum de action: não sabemos o que há
dentro, então não podemos responder pelo que vai tocar no set). O modelo vai insistir — cada
insistência custa uma recusa no turno. Deixamos aqui porque é conflito real entre a promessa do
produto (nunca mexer no set dele sem alvo conhecido) e a instrução do fornecedor. Se um dia
quisermos `batch`, o preço é abrir o payload antes de enviar, item por item, e isso é trabalho com
voto dele, não atalho.

### O que eu faço com isso (sem esperar voto)
Chave existe e tem gate com recusa acionável; falta **plugar no `ChatEngine`** com default
`.timeline` (parâmetro com default, pra não tocar nos 69 testes existentes) e recusar cálculo em
Performance. UI (Picker na `ResolumeChatView`) **não** vem antes de ele pedir. Telemetria vira um
módulo próprio depois — medida isolada não é produto, e quem decide o limiar de aviso é ele.
Fila nova desta tacada: rename em lote (§13.9), tela que soma o projeto inteiro já existia como
fila antiga e agora tem motor (`TimelineCalculator`), e a única pergunta travando formato é o epoch
do journal (§13.8).

---

## 14. De quem é o relógio: o dropdown de cada clipe virou eixo (checkpoint 9)

Ele fotografou dois dropdowns e traduziu os dois, com a economia de palavras dele. As duas frases
viraram código testado nesta tacada, não comentário.

### 14.1 `transporttype` = de quem é o relógio (`Timeline` / `BPM Sync` / SMPTE / mesa)

Foto dele: `Timeline | BPM Sync | SMPTE 1 | SMPTE 2 | Denon DJ | Pioneer DJ`. Tradução dele, na
ordem da foto: *"Timeline = Cronometria. BPM = Performance. SMPTE = Evento Sincronizado.
Denon/Pioneer = Controlado pela música."*

Medido no payload vivo (`/tmp/comp2.json`, Arena 7.28.0-rev24303): o campo `transporttype` aparece
**73 vezes**, `valuetype: ParamChoice`, `options` entregando a lista inteira **dentro do payload**
na mesma ordem da foto, `value` das 73 = `"Timeline"`, `index = 0`. Ou seja: a máquina entrega o
vocabulário, então dá pra validar contrato sem chute — e foi o que fizemos
(`RelogioDoClipe.nomesNoArena` ↔ `classificar(_:)`, round-trip travado em teste).

Consequência dura, e era um **bug real** antes desta tacada: a calculadora somava qualquer clipe que
tivesse número, inclusive um em `SMPTE 1`. Isso promete um total como se o *play* fosse ato nosso —
exatamente o que a regra dele proíbe (*"em situação síncrona o play nunca é ato nosso"*; OSC faz o
trigger, LTC faz o transport). Agora `effectiveMS` devolve `nil` quando o relógio não é nosso e o
slot aparece em `semTempo` com endereço. Nada é apagado: `durationMS` bruto continua legível, só a
**promessa de soma** é recusada.

Duas escolhas honestas que ele pode inverter, cada uma com teste que trava a escolha:
1. **Ausência de campo vira `Timeline`, não `desconhecido`.** Medido que `index = 0`/"Timeline" é o
   valor de fábrica (e as 3 capturas dele de Preferences mostram `Default Video/Audio Clip
   Transport = Timeline`). Nome que não conhecemos vira `.desconhecido` e **fica fora da conta**.
2. **Piloto ligado reassume o relógio mesmo em clipe SMPTE.** Com `duration_type` em
   `Seconds`/`Beats`, quem segura a tela é o relógio wall-clock do próprio Arena, então voltamos a
   cronometrar. Marcado `chute:` no código — não temos payload vivo com piloto + SMPTE ligados pra
   medir. Se num set sincronizado o piloto também segue o LTC, a inversão é uma linha em
   `effectiveMS`.

### 14.2 `playmode` = o que acontece quando o passo acaba (`Loop` … `Play Once & Clear`)

Segunda foto: `Loop | Bounce | Random | Play Once & Clear | Play Once & Hold`, com o ponto verde em
**`Play Once & Clear`**, e o comentário dele: *"Isso é o mais usado — acabou, morreu."* Terceira
foto: as mesmas duas chaves em **Preferences → Defaults** (`Default Video/Audio Clip Transport =
Timeline`, `Default Video/Audio Clip Play Mode` = as duas caixinhas), confirmando o par
fábrica-para-todo-clipe-novo.

Medido no mesmo payload: `playmode` aparece **14 vezes** (só nos clipes que têm `transport`),
`options = ["Loop","Bounce","Random","Play Once & Clear","Play Once & Hold"]`, `value` das 14 =
`"Loop"`, `index = 0`.

Leitura que registro sem fingir certeza: **"acabou, morreu" é a semântica literal do `Play Once &
Clear`** — toca uma vez e libera o slot, ou seja, o passo termina em tela livre/preta. Não mudei
código nenhum aqui: `SlotState.playMode` já carregava a string crua e nenhuma decisão de soma
depende dela (tempo vem de transporte/piloto, não de playmode). O que isso abre é produto, e está
na fila abaixo.

**Dúvida honesta (§14 aberto, anotado não perguntado):** se o último passo de um bloco é `Play Once
& Clear`, a régua acertou o tempo **e** previu tela vazia no fim. Hoje a régua responde "quanto
durou"; responder "no fim disso aqui, apaga" é outra frase. Precisa dele: em evento, apagão
programado e apagão-esquecido são coisas que o operador quer ver separadas? Não implemento sem voto
porque é opinião sobre palco, não sobre API.

### O que eu faço com isso (sem esperar voto)
Trava de sincronia **feita e testada** (7 testes novos, suíte 78 → **85/85**). playmode fica só
documentado. Falta plugar `OperationMode`/`ModeGate` no `ChatEngine` (default `.timeline`,
parâmetro com default) — e aí a chave dele ganha dentes: em `Timeline` a régua **calcula**, em
`Performance` ela **recusa calcular** e mede. Fila crescendo: régua visual (sensação espaço/tempo,
§13), rename em lote com `#` (§13.9), e agora "apagão previsto vs esquecido".

## 15. Qual licença de topo o ResoluxToolkit adota?
Com a política NDI escrita em `docs/NDI-POLICY.md`, o repo precisa de licença permissiva antes
de qualquer distribuição: MIT, Apache-2.0 ou BSD-3-Clause. Não escolhi por você porque isso muda
patente/attribution/contribuição. Enquanto não houver voto, não crio `LICENSE` e não implemento
runtime NDI.
