# ResoluxToolkit

Website: [https://resolux-toolkit.vercel.app](https://resolux-toolkit.vercel.app)

ResoluxToolkit é um monorepo Swift para suportar um operador de VJ no trabalho com o **Resolume Arena**. O produto central é o app macOS `ResoluxMac`, que conversa com o Arena por MCP e REST, expõe monitoramento read-only e um assistente local com loop de ferramentas.

## Estrutura

| Caminho | Papel |
| --- | --- |
| `Packages/ResoluxCore` | Modelo de domínio puro, sem dependências de plataforma. |
| `Packages/ResoluxPlatform` | Abstração compartilhada entre plataformas. |
| `Packages/ResoluxPlatformMac` / `ResoluxPlatformiOS` | Implementações AppKit e UIKit. |
| `Packages/ResoluxDesignSystem` | Componentes visuais MEVOLIT. |
| `Features/Starter` | Utilitário multiplataforma com relatório de capacidades e backup. |
| `Features/Resolume` | Motor e UI do produto Resolume, macOS-only. |
| `Apps/macOS/ResoluxMac` | App final para macOS. |
| `Apps/iOS/ResoluxIOS` | App final para iOS; atualmente é scaffold. |

## Como executar

1. Requisitos: macOS 15+, Swift tools 6.0 e Xcode com o workspace `ResoluxToolkit.xcworkspace`.
2. Abra `ResoluxToolkit.xcworkspace` no Xcode e escolha o scheme **ResoluxMac**.
3. Com o Resolume Arena aberto, execute o app. O motor descobre a sessão local e começa em modo de leitura.

Comandos úteis:

```bash
xcodebuild -workspace ResoluxToolkit.xcworkspace -scheme ResoluxMac -configuration Debug build
swift test --package-path Features/Resolume
swift test --package-path Packages/ResoluxCore
```

O suíte de Resolume tem um teste que depende do Arena aberto com a REST API habilitada; o restante roda offline.

## Princípios de domínio

- O Resolume Arena é imutável: o toolkit não altera instalação, preferências ou configurações nativas.
- As ferramentas são `read-only` e `deny-by-default` por padrão; escritas só passam pela política e pelo journal de operações.
- O assistente usa modelos locais por padrão e nunca descarrega o controle do Arena para um agente automático sem veto humano.
- Integrações seguem as portas e convenções do Arena: REST em `8080`, OSC de entrada em `7000` e saída em `7001`.
- O app macOS roda sem sandbox para gerenciar o processo MCP do Arena como filho.

## Documentação

- `docs/HANDOFF.md`: estado da sessão e fonte de verdade de trabalho.
- `docs/ESTADO-E-ROADMAP.md`: implementação atual e ordem do roadmap.
- `docs/ITERACOES.md`: registro de cada tacada.
- `docs/DUVIDAS.md`: decisões e votos pendentes do operador.
