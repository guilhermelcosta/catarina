# Architecture and data

## Layout

```text
src/
  core/         pure logic: request schema, variable substitution, resolution
  storage/      I/O: collections, environments, history, secrets
  net/          request assembly (RequestBuilder) and sending (HttpClient)
  backend.*     Q_INVOKABLE facade exposed to QML
  settings.*    preferences
  highlighter.* {{var}}/JSON highlighting
  main.cpp
qml/
  Main.qml        window and wiring
  AppController   state and orchestration (non-visual QtObject)
  screens/        RequestEditor, ResponsePane, CollectionScreen, ...
  dialogs/        modals and popups
  js/, Util.js, Strings.js  pure logic and texts
tests/            check_*, tst_* (ctest)
assets/           app icon, source artwork and store screenshots
docs/             project documentation
```

The `core/` layer has no I/O or network dependency. `storage/` and `net/` are
injected behind small interfaces, which keeps the tests hermetic. `Backend` is
the only object exposed to QML.

## Data

| What                 | Where                                                                   |
| -------------------- | ----------------------------------------------------------------------- |
| Collections/requests | XDG Documents folder, `catarina/` (configurable)                        |
| Preferences          | `~/.config/catarina/catarina.ini`                                       |
| Secrets              | OS keyring, or `~/.local/share/catarina/catarina/secrets.json` (`0600`) |
| History              | `~/.local/share/catarina/catarina/history.json`                         |

Secrets are stored in the keyring through QtKeychain. The collection file only
stores a `secretId`. With no keyring available, the fallback file is created with
owner read/write permissions only.
