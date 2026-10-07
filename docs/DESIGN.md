# Guia de design e componentes — Katarina

Regras visuais e de implementação do app. **Antes de criar/alterar qualquer elemento de UI,
valide aqui qual é o padrão.** Se o padrão não existir, defina-o, implemente de forma
reutilizável e **adicione-o a este documento**.

Regra de ouro: se um elemento se repete (ou pode se repetir) em mais de um lugar, ele é um
**componente compartilhado** — nunca reimplemente localmente.

---

## 1. Espaçamento (respiro)

- **Padding de um painel/aba**: `Kirigami.Units.largeSpacing` em todas as bordas.
- **Entre controles** e margens internas de linhas/cabeçalhos de tabela: `Kirigami.Units.smallSpacing`.
- **Colunas de tabela**: espaçamento `smallSpacing` (no `KvTable`, `colSpacing`).

### ⚠️ `StackLayout` ignora `Layout.margins`
Filhos de um `StackLayout` **não** respeitam `Layout.margins` (verificado). Para dar respiro:
- envolva o conteúdo num `Item` e use `anchors.fill: parent; anchors.margins: <valor>` na
  `ColumnLayout`/`RowLayout` interna; **ou**
- use `padding: <valor>` em `ScrollView`.

---

## 2. Opacidades (valores padrão)

| Elemento | Opacidade |
|---|---|
| Mensagem de estado vazio ("Nada aqui ainda.", "Sem resposta.", etc.) | `0.6` |
| Cabeçalho de coluna de tabela (`font.bold: true`) | `0.65` |
| Texto secundário/ajuda ("globais aparecem em toda visão", descrições) | `0.6` |
| Linha de tabela desabilitada | `0.45` |
| Variável efetiva desabilitada (lista) | `0.4` |

---

## 3. Botões e ações

Padrão de **posicionamento**: ações no **topo à direita**; "Adicionar" no **rodapé** da lista.
Diferença de importância: primária = `highlighted`; secundária = `ToolButton` só com ícone + tooltip.

| Ação | Forma | Ícone | Onde |
|---|---|---|---|
| Salvar (primária) | `Button { highlighted: true }` com texto | `document-save` | topo à direita; habilitado só quando há alterações |
| Reverter/Descartar (secundária) | `ToolButton` só ícone + tooltip | `edit-undo` | antes do Salvar |
| Renomear | `ToolButton` só ícone | `edit-rename` | ao lado do título |
| Adicionar ("Adicionar"/"Novo …") | `Button`/`ToolButton` com texto | `list-add` | rodapé da lista/tabela |
| Remover linha | `ToolButton` | `list-remove` | última coluna |
| Excluir (destrutivo) | `Button`/`ToolButton` | `edit-delete` | toolbar (árvore) / rodapé (lista de ambientes) |
| Duplicar | `MenuItem` | `edit-duplicate` | menus |
| Enviar request | `Button { highlighted }` | `document-send` | toolbar do request |

- **Diálogos**: sempre `Cancelar` à esquerda e a ação primária (`highlighted`) à direita.
- **Editor contextual pequeno**: prefira um **popover ancorado e não-modal** (aplica ao vivo), em vez
  de um diálogo modal; a célula que o abre pode ser um **chip** (ícone + texto,
  `alternateBackgroundColor`, borda `disabledTextColor`, `radius: 4`). Ex.: escopo da variável.
- **Seção editável** (título + "alterações não salvas" + Reverter + Salvar): use **`SaveBar.qml`**.
  Não recrie esse cabeçalho à mão.

---

## 4. Ícones

Use nomes do Breeze e **confirme que existem no tema** (ícones inexistentes ficam quebrados;
ex.: `vcs-repo` não existe). Convenção fixa:

| Conceito | Ícone |
|---|---|
| Coleção (nível raiz) | `folder-documents` |
| Pasta/subpasta | `folder` |
| Nova pasta | `folder-new` |
| Ambiente(s) | `vcs-branch` |
| Novo request | `document-new` |
| Salvar / Reverter / Renomear | `document-save` / `edit-undo` / `edit-rename` |
| Excluir / Remover linha | `edit-delete` / `list-remove` |

Checagem rápida: `find /usr/share/icons -iname "<nome>.svg"`.

---

## 5. Componentes compartilhados (reutilize)

Todos em `qml/`:

- **`KvTable.qml`** — tabela editável chave/valor (params, cabeçalhos, campos, variáveis de
  request/coleção/ambiente). Opções: `secretColumn`, `allowFiles`, `scopeColumn`
  (+ `scopeText`/`scopeIcon`/`scopeRequested`), `rowFilter`, `resolved`/`collection`.
  **Toda tabela editável nova usa este componente** — estenda com uma opção nova em vez de
  criar outra tabela.
- **`SaveBar.qml`** — cabeçalho de seção com indicador de rascunho + Reverter + Salvar;
  opções `showDiscard`, `showRename`/`canRename` (lápis de renomear) e sinais `save`/`discard`/`rename`.
- **`EmptyState.qml`** — estado vazio (placeholder) padronizado: ícone opcional (área fixa de 72px),
  título, mensagem (`opacity 0.6`), atalho e ação opcional (`highlighted`). Fundo transparente
  (herda o painel). **Todo placeholder usa este componente** — centralize com
  `anchors.centerIn: parent; width: Math.min(parent.width - largeSpacing*2, 340)`.
- **`HeaderTable.qml`** — tabela somente-leitura (cabeçalhos HTTP da resposta).
- **`JsonTree.qml`** — árvore JSON da resposta (lazy: só parseia quando a aba "Árvore" está ativa).
- **`VarCompleter.qml`** — autocomplete/hover de `{{variavel}}`.
- **`NetworkView.qml`** — aba "Rede".
- **`Util.js`** — lógica pura/testável (cURL, base64, formatação, reordenação de abas).
  Coloque aqui qualquer função sem dependência de UI.

### Tabelas responsivas (regra)
- Colunas flexíveis: `Layout.fillWidth: true` + **`Layout.preferredWidth` e `Layout.minimumWidth`
  explícitos** (nunca dependa do tamanho implícito de `Label` vs `TextField` — foi o que desalinhou).
- Colunas pequenas fixas: `preferred = minimum = maximum` (Ativo 48, Tipo 90, Segredo 64, Remover 40 no `KvTable`).
- **Cabeçalho e linhas usam os mesmos `preferred`/`minimum`** → ficam alinhados.
- **Nunca** derive a largura de coluna da própria `width` da tabela (cria loop de polish do layout).

---

## 6. Regras de dados / UX

- **Variáveis** têm `enabled`; desabilitada não resolve em `{{...}}`, fica esmaecida e o
  autocomplete não a oferece. A resolução é única (`Backend::variableChain`) para todos os escopos.
- **Segredos**: o valor real é carregado do cofre para edição (mascarado no campo com segredo),
  mas **nunca** é escrito no arquivo versionado; desmarcar "segredo" grava em claro e limpa o cofre.
- **Confirmações de exclusão**: todas seguem `settings.confirmDelete` (ou confirma em tudo, ou em nada).
- **Resposta**: Ctrl+F busca no corpo completo; JSON sempre pretty; área de status reserva altura fixa.
- **Idioma da UI**: português (pt-BR).

---

## 7. Checklist ao criar um elemento novo

1. Já existe componente/padrão para isso? Reutilize (seção 5).
2. Espaçamento: `largeSpacing` (painel) / `smallSpacing` (interno) — seção 1.
3. Opacidade conforme a tabela — seção 2.
4. Botões: posição e forma conforme a seção 3 (`SaveBar` para seções editáveis).
5. Ícone existe no tema e segue a convenção — seção 4.
6. Se é tabela: use `KvTable`; se precisa de coluna/opção nova, **estenda o `KvTable`**.
7. Se surgiu um padrão novo → **documente aqui**.
