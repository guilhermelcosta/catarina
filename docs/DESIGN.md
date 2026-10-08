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
- **Rótulo de estado vazio abaixo de um `ComboBox`** ("Sem corpo.", "Sem autenticação."): a
  distância vertical vem **só** do `spacing` do `ColumnLayout` (`smallSpacing`) — use apenas
  `Layout.leftMargin` para alinhar. **Não** some `Layout.topMargin` (o "Sem corpo." somava e
  ficava com o dobro da distância do "Sem autenticação.").

### ⚠️ `StackLayout` ignora `Layout.margins`
Filhos de um `StackLayout` **não** respeitam `Layout.margins` (verificado). Para dar respiro:
- envolva o conteúdo num `Item` e use `anchors.fill: parent; anchors.margins: <valor>` na
  `ColumnLayout`/`RowLayout` interna; **ou**
- use `padding: <valor>` em `ScrollView`.

### ⚠️ `StackLayout` espreme filho que é `Layout` com `ScrollView`
O `StackLayout` dimensiona o filho atual com `newSize.expandedTo(min).boundedTo(max)`; num
filho que é `ColumnLayout`/`RowLayout` (layout aninhado) contendo um `ScrollView`, o `max`
calculado sai pequeno e o conteúdo aparece **espremido** (ex.: o corpo do payload virava uma
linha só ao trocar para a aba). Verificado no app (xcb).
- No filho `Layout` do `StackLayout`, defina `Layout.maximumHeight: Number.POSITIVE_INFINITY`
  (ou `Layout.maximumWidth`, no eixo correspondente).
- Filhos que são `Item`, `KvTable` ou `ScrollView` direto não sofrem disso.
- Com o máximo liberado, o `ColumnLayout` passa a ocupar a altura toda do `StackLayout`; se
  nenhum filho visível tiver `Layout.fillHeight: true`, o Qt **redistribui** o espaço sobrando
  entre os filhos comuns e o cabeçalho "estica" (o combo ia parar no meio da página). Termine o
  `ColumnLayout` com um `Item { Layout.fillHeight: true }`, deixando-o `visible` só quando
  nenhum outro filho preenche (ex.: corpo em "nenhum", variáveis efetivas vazias).

### ⚠️ `ListModel`: declare as roles no `append`, não via `setProperty`
Uma role criada por `setProperty` **depois** que o delegate já existe **não chega ao
delegate**: `model.<role>` fica `undefined` para sempre (o `get(i)` até enxerga o valor, mas
a UI não). Já quebrou o pino das abas — ao restaurar a sessão as abas eram inseridas sem
`pinned`/`preview`, e `setProperty(k, "pinned", true)` não aparecia na aba (o X continuava).
- Sempre inclua **todas** as roles em **todo** `append` (ex.: `pinned: false, preview: false`).
- Teste de regressão em `tests/tst_components.qml` (`test_listmodel_roles_declaradas`).

### ⚠️ `ToolTip.visible: hovered` rouba o clique
Mostrar tooltip no hover de um item que precisa ser **clicado** (pino/X de aba, botões de
ícone) faz o popup do tooltip engolir o clique — o `TapHandler`/`MouseArea` do item não
dispara. Verificado em `qmltestrunner` (offscreen e xcb).
- Preferir `ToolButton` (control) com `ToolTip.text` + `ToolTip.delay` (tooltip nativo, não
  quebra o clique); **ou**
- simplesmente não auto-mostrar tooltip nesses itens.

### ⚠️ `text` programático não emite `textEdited`
Setar `TextArea.text` por código (ex.: `VarCompleter.choose`) **não** dispara `textEdited` —
ele só sai de edição do usuário. Quem escuta `onTextEdited` (o `KvTable` grava o modelo,
o corpo/URL marcam dirty) fica desatualizado. Por isso o `VarCompleter.choose` emite
`target.textEdited()` na mão (QML permite emitir um sinal C++). Regressão em
`tests/tst_components.qml` (`test_varcompleter_choose_notifica_edicao`).

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

- **Diálogos (padrão)**: título em **negrito** com `header: DialogHeader { dialogTitle: <id>.title }`
  — o texto auxiliar (rótulo de campo) **não** é negrito. `Cancelar` à esquerda e ação primária
  (`highlighted`) à direita, na `RowLayout` com `Layout.bottomMargin: smallSpacing` (respiro até a
  borda). Prefira `standardButtons` quando der. A `height` fixa precisa caber o conteúdo — senão
  os botões extravasam o fundo.
- **Validação de diálogo é ao vivo** (conforme digita): `Label` vermelho abaixo do campo
  (`negativeTextColor`) + botão primário desabilitado enquanto inválido. O diálogo tem **altura
  fixa** já reservando o espaço da mensagem (senão, ou cresce ao digitar, ou os botões vazam).
  Não use erro só-no-clique.
- **Rótulo de formulário acima do campo**: não-negrito + `Layout.bottomMargin: smallSpacing`
  (folga `2×smallSpacing` até o campo) — só o `spacing` do `ColumnLayout` deixa o texto "colado".
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
  (+ `scopeText`/`scopeIcon`/`scopeColor`/`scopeRequested`), `rowFilter`, `resolved`/`collection`,
  `uniqueNames` (nome repetido no mesmo escopo: texto em **vermelho e negrito** + motivo num
  popup no hover do campo).
  O `scopeColor(index)` pinta o chip de escopo por escopo (verde = global, azul = restrita a
  coleções; **null** = neutro). **Toda tabela editável nova usa este componente** — estenda com
  uma opção nova em vez de criar outra tabela.
- **`SaveBar.qml`** — cabeçalho de seção com indicador de rascunho + Reverter + Salvar;
  opções `showDiscard`, `showRename`/`canRename` (lápis de renomear) e sinais `save`/`discard`/`rename`.
- **`EmptyState.qml`** — estado vazio (placeholder) padronizado: ícone opcional (área fixa de 72px),
  título, mensagem (`opacity 0.6`), atalho e ação opcional (`highlighted`). Fundo transparente
  (herda o painel). **Todo placeholder usa este componente** — centralize com
  `anchors.centerIn: parent; width: Math.min(parent.width - largeSpacing*2, 340)`.
- **`HeaderTable.qml`** — tabela somente-leitura (cabeçalhos HTTP da resposta); células selecionáveis + "Copiar tudo".
- **`ResolvedVarsTable.qml`** — tabela somente-leitura das variáveis efetivas (Origem/Nome/Valor).
  A coluna Origem tem **cor e ícone por escopo** (global/coleção/request) e a lista é ordenada por
  origem (global → coleção → request) e depois por nome.
- **`JsonTree.qml`** — árvore JSON da resposta (lazy: só parseia quando a aba "Árvore" está ativa).
- **`VarCompleter.qml`** — autocomplete/hover de `{{variavel}}` (usado por `VarField`). O popup de
  hover mostra `nome = valor` + um **chip do escopo** (mesma cor/ícone de origem: global/coleção/
  request), em vez de `(escopo)` entre parênteses.
- **`VarField.qml`** — campo de texto de uma linha com `{{variavel}}` **embutido** (highlight +
  autocomplete + hover). **Todo campo que aceita variáveis usa este componente** (URL, corpo,
  auth, colunas Nome/Valor do `KvTable`). É `TextArea` porque o highlight precisa do
  `QQuickTextDocument` — logo campos mascarados (`echoMode`, senha/segredo) não têm highlight.
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
- **Nome de variável é único por escopo** (ambiente, coleção ou request). O mesmo nome em escopos
  diferentes é ok (eles se sobrepõem); repetido no mesmo escopo é recusado
  (`Backend::duplicateVariableName`, nomes aparados). A UI bloqueia o **Salvar** e o campo
  duplicado mostra o motivo num **popup no hover** (mesmo estilo do hover de `{{variavel}}`).
- **Nome e valor podem referenciar outra variável** via `{{outra}}` (ex.: nome `{{env}}_url`
  vira o valor de `env`; valor `{{host}}/x` encadeia). Resolvido em `Backend::variableChain`
  (nome **e** valor num laço único, reconstruindo o mapa de nomes a cada passada até
  estabilizar — cobre referência encadeada, ex.: `{{variavel-1}}` → `valor 1` e `{{valor 1}}`
  → `valor 2`). O número máximo de passadas é a constante
  `kMaxVariableResolvePasses` (`src/backend.cpp`): ~1 passada por nível encadeado e, ao mesmo
  tempo, teto de segurança para referência cíclica (`{{a}}`↔`{{b}}`), que não converge.
- **Segredos**: o valor real é carregado do cofre para edição (mascarado no campo com segredo),
  mas **nunca** é escrito no arquivo versionado; desmarcar "segredo" grava em claro e limpa o cofre.
- **Confirmações de exclusão**: todas seguem `settings.confirmDelete` (ou confirma em tudo, ou em nada).
- **Resposta**: Ctrl+F busca no corpo completo; JSON sempre pretty; área de status reserva altura fixa.
- **Sessão**: só abas **fixadas** voltam ao reabrir o app (`Util.sessionPaths`); preview e demais
  não-fixadas são transientes. `restoreSessionTabs` recria as fixadas já com o pino.
- **Renomear coleção**: reaponta o escopo (`collections`) das variáveis de ambiente que a
  referenciam (`Backend::renameCollectionScope`), senão o escopo fica órfão.
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
