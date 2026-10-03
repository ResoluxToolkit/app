# ResoluxToolkit — fluxo de trabalho

O trabalho segue o ciclo **um recurso por tacada**:

1. O operador pede uma alteração.
2. Você altera apenas o necessário para aquele recurso; nada de refatoração lateral.
3. Você verifica o menor escopo possível (teste focado, `swift test` do pacote ou build do app afetado).
4. Você registra a tacada em `docs/ITERACOES.md` com: pedido, arquivos, verificação, onde ver no app e status `aguardando revisão`.
5. Você para a execução e espera o operador aprovar, pedir ajuste ou escolher o próximo recurso.

Se o pedido exigir mais de uma função/superfície, divida em tacadas e execute só a primeira. O registro em `docs/ITERACOES.md` é append-only: atualize status sem apagar histórico.
