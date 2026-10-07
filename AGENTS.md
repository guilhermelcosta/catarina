# Instruções para agentes — Katarina

App de cliente de API em Qt 6 / QML / Kirigami. UI em português (pt-BR).

## Design e componentes

Antes de criar ou alterar qualquer elemento de UI, leia e siga **[`docs/DESIGN.md`](docs/DESIGN.md)**.
Ele define o padrão de espaçamento, opacidades, botões, ícones e os componentes compartilhados
(`KvTable`, `SaveBar`, `HeaderTable`, `JsonTree`, `VarCompleter`, `NetworkView`, `Util.js`).

Regras rápidas:
- Reutilize componentes compartilhados; não reimplemente localmente algo que se repete.
- Toda tabela editável usa `KvTable` (estenda com uma opção nova se precisar).
- Seções editáveis usam `SaveBar` (título + "alterações não salvas" + Reverter + Salvar).
- Padding de painel: `Kirigami.Units.largeSpacing`; entre controles: `Kirigami.Units.smallSpacing`.
- `StackLayout` ignora `Layout.margins` — use `anchors.margins` (via `Item`) ou `ScrollView.padding`.
- Confirme que todo ícone Breeze existe no tema antes de usar.
- Surgiu um padrão novo? Documente em `docs/DESIGN.md`.

## Testes

Rode `ctest` no diretório `build/` (build: `cmake --build build`). Há também `./build/bin/check_storage`
(lógica do backend, hermético) e `./build/bin/bench_storage` (benchmark dos caminhos quentes).
