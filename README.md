# Catarina

![Qt](https://img.shields.io/badge/Qt-6.5%2B-41CD52?logo=qt&logoColor=white)
![KDE Kirigami](https://img.shields.io/badge/KDE%20Kirigami-6-1D99F3?logo=kde&logoColor=white)
![Platform](https://img.shields.io/badge/platform-Linux-informational)
![Tests](https://img.shields.io/badge/tests-ctest-success)

**Catarina é um cliente de API offline para Linux** — as coleções e requests são arquivos
`.json` versionáveis no seu disco, não registros num banco remoto. Feito com **Qt 6 / QML /
Kirigami**, com interface em português.

![Catarina](docs/screenshot.png)

## Por que mais um cliente de API?

- **Coleções em arquivos, versionáveis.** Cada request é um `.json` em
  `~/catarina-collections`. Você versiona com `git`, revisa em diff, compartilha por pasta — sem
  exportar/importar.
- **Segredos fora do repositório.** Senhas e tokens ficam no **cofre do sistema**
  (Secret Service/KWallet via QtKeychain); o arquivo versionado guarda só um `secretId`.
  Sem cofre disponível, cai para um arquivo `0600` fora da pasta das coleções.
- **Variáveis com escopo de verdade.** `{{nome}}` resolvido na cadeia **global → coleção →
  request**, com referências encadeadas, variáveis desabilitadas e escopo por coleção.
- **Leve e nativo.** Sem Electron. Um binário Qt/Kirigami.

## Funcionalidades

- **Requests**: método, URL com preview de querystring, params, headers (do request e da
  coleção), **auth** (Bearer / Basic / API Key / herdar da coleção) e corpo
  (none / JSON / texto / form-urlencoded / **multipart com arquivo**).
- **Coleções aninhadas** com drag-and-drop, renomear, duplicar e mover; **guias de indentação**
  (estilo VS Code) na árvore.
- **Variáveis** `{{variavel}}` com autocomplete, hover com o valor e aviso de variável não
  definida — na URL, headers, corpo, auth e tabelas.
- **Environments** globais, com escopo por coleção ou "todas".
- **Resposta**: corpo, **árvore JSON**, cabeçalhos, cookies e **aba de Rede** (timeline).
- **Abas** no estilo do VS Code: prévia transiente, fixar/desafixar, reordenar, reabrir fechada e
  **restaurar sessão**.
- **Importar/exportar cURL**, **histórico** de envios e **paleta de comandos** (`Ctrl+K`).
- **Atalhos** remapeáveis nas configurações.
- **Coleção de exemplo** (DummyJSON) criada no primeiro uso.

## Instalação

### Dependências

- **Qt 6.5+** — `Core`, `Gui`, `Qml`, `Quick`, `QuickControls2`, `Network`
- **Extra CMake Modules (ECM) 6**
- **KF6 Kirigami**
- **QtKeychain** (opcional) — habilita o cofre do SO; sem ele, segredos vão para arquivo `0600`

<details>
<summary>Nomes de pacote por distro</summary>

**Fedora / KDE**
```sh
sudo dnf install cmake gcc-c++ \
    extra-cmake-modules \
    qt6-qtbase-devel qt6-qtdeclarative-devel qt6-qtquickcontrols2-devel \
    kf6-kirigami-devel qt6-qtkeychain-devel
```

**Arch**
```sh
sudo pacman -S cmake extra-cmake-modules \
    qt6-base qt6-declarative qt6-quickcontrols2 kirigami qtkeychain-qt6
```

**Debian/Ubuntu**
```sh
sudo apt install cmake g++ extra-cmake-modules \
    qt6-base-dev qt6-declarative-dev qt6-quickcontrols2-dev \
    kirigami6-dev libqt6keychain1
```
</details>

### Compilar e rodar

```sh
cmake -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build -j
./build/bin/catarina
```

### Flatpak

O manifesto em `packaging/org.catarina.Catarina.yml` já inclui o QtKeychain:

```sh
flatpak-builder --user --install --force-clean build-flatpak packaging/org.catarina.Catarina.yml
```

### Instalar no sistema

```sh
cmake --install build
```

## Testes

```sh
ctest --test-dir build --output-on-failure
```

| Alvo | Cobre |
|---|---|
| `check_storage` | lógica pura de request, resolução de variáveis, segredos, persistência em disco, seed |
| `check_http` | integração HTTP real com servidor local (resposta, erro, cancelamento, multipart) |
| `tst_components` | componentes QML e lógica JS (QtQuickTest) |
| `tst_app` | comportamento de tela: abas, sessão, edição/dirty, exclusão, import, guias |
| `check_highlighter` | realce de sintaxe JSON |
| `qml_smoke` | o app carrega sem erros de QML |

Os testes são **herméticos** (diretório temporário, sem tocar nos seus dados nem no cofre real).

## Estrutura do projeto

```
src/
  core/       lógica pura: schema do request, substituição de variáveis, resolução
  storage/    I/O atrás de injeção: coleções, ambientes, histórico, segredos
  net/        montagem do request (RequestBuilder) e envio (HttpClient)
  backend.*   fachada Q_INVOKABLE exposta ao QML
  settings.*  preferências;  highlighter.*  realce de {{var}}/JSON;  main.cpp
qml/
  Main.qml        janela + wiring (shell)
  AppController   estado e orquestração (QtObject não-visual)
  screens/        telas (RequestEditor, ResponsePane, CollectionScreen, ...)
  dialogs/        modais e popups
  js/, Util.js, Strings.js   lógica pura e textos
tests/            check_*, tst_* (ctest)
docs/DESIGN.md    padrões visuais e de componentes
```

**Onde ficam os dados**

| O quê | Onde |
|---|---|
| Coleções/requests | `~/catarina-collections` (configurável) |
| Preferências | `~/.config/catarina/catarina.ini` |
| Segredos | cofre do SO ou `~/.local/share/catarina/secrets.json` (`0600`) |
| Histórico | `~/.local/share/catarina/history.json` |

## Contribuindo

1. Leia **[`AGENTS.md`](AGENTS.md)** (regras para agentes/contribuidores) e
   **[`docs/DESIGN.md`](docs/DESIGN.md)** antes de mexer na UI — os componentes e o espaçamento
   seguem um padrão único.
2. Reutilize os componentes existentes (`KvTable`, `SaveBar`, `EmptyState`, ...) em vez de criar
   locais; se um padrão novo surgir, **documente no DESIGN.md**.
3. Rode `ctest` antes de abrir o PR. Mantenha o histórico em commits pequenos e descritivos
   (`feat:`, `fix:`, `refactor:`, `test:`, `docs:`).

## Licença

Ainda **não definida** — falta adicionar um arquivo `LICENSE`. Até lá, trate como
"todos os direitos reservados". (Se quiser, abrimos um PR adicionando MIT/GPL.)

## Créditos

Feito com [Qt](https://www.qt.io/) e [KDE Kirigami](https://invent.kde.org/frameworks/kirigami).
A coleção de exemplo usa a API pública do [DummyJSON](https://dummyjson.com/).
