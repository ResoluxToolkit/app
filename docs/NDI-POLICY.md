# NDI® — política do ResoluxToolkit

Esta é a adaptação das regras do NDI® Apple SDK para o repo. Vale como guia de
desenho e revisão antes de qualquer implementação. Hoje ainda não existe
dependência nem código NDI no projeto.

## Escopo de produto

- **macOS é permitido** sob a licença gratuita do SDK. O app ResoluxMac pode
  ganhar integração NDI depois de implementada.
- **iOS não é permitido** sob a licença gratuita. Integração NDI fica fora do
  app iOS e dos targets iOS até existir contrato comercial com a NDI/Vizrt.
  Scaffold de UI sem o SDK continua válido.
- TouchDesigner segue como ponte de execução/processamento. NDI é o caminho de
  vídeo entre TouchDesigner e Arena, não biblioteca genérica de imagem nossa.

## Tratamento do SDK

- Nunca comitar nem redistribuir headers, exemplos, frameworks, estáticos,
  dynamic libraries, runtime packages ou payloads de instalador do NDI SDK.
- O SDK instalado só é usado para desenvolvimento local, depois do download
  oficial e da aceitação do contrato pelo desenvolvedor.
- O bridge não pode depender de biblioteca vinculada no build. Em runtime, tenta
  `dlopen` no local documentado do runtime oficial no macOS; só ativa a
  capability NDI se carregar. Se falhar, o app segue sem NDI e mostra instrução
  para instalar o runtime oficial.
- O repo contém apenas código/interface próprio. Não copia texto de header do
  SDK. Não vende o SDK e não gera instalador que extraia o redistribuível NDI,
  a menos que o operador revise os termos comerciais e mude esta política.
- A decisão de versão do runtime/biblioteca continua registrada em
  `docs/DUVIDAS.md` e não é resolvida aqui.

## Branding e avisos legais

- Os nomes continuam `ResoluxToolkit`, `ResoluxMac` e os nomes existentes das
  features. Não combinar `NDI` com o nome do produto.
- Texto de compatibilidade usa “ResoluxToolkit — with support for NDI®” ou
  frase equivalente neutra.
- A tela Sobre/legal inclui:
  “NDI® is a registered trademark of Vizrt NDI AB.”
- Os termos de distribuição incluem a isenção de garantia/limitação de
  responsabilidade da NDI para o uso da tecnologia e não sugerem endosso da
  NDI/Vizrt.

## Compatibilidade com open source

- O projeto precisa de licença permissiva. Candidatos aceitos: MIT,
  Apache-2.0 e BSD-3-Clause. Não usar GPL/LGPL em distribuição com NDI.
  A escolha exata continua pendente de voto do operador.
- Até a licença de topo existir/atualizar, não entra integração runtime NDI nem
  empacotamento distribuído.

## Checklist de revisão

1. Nenhum artefato NDI é rastreado pelo Git.
2. Nenhum target iOS linka ou carrega NDI.
3. O bridge no macOS é opcional e degrada sem NDI.
4. Toda menção a NDI usa trademark e texto neutro de compatibilidade.
5. Mudanças de licença/branding ficam em tacada separada aprovada.
