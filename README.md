<p align="center">
  <img src="assets/icons/catarina-badge.svg" width="96" alt="Catarina app icon" />
</p>

<h1 align="center">Catarina</h1>

<p align="center">
  <strong>Your API collections, as plain JSON files you own.</strong><br />
  No account. No cloud. No Electron. Free and open source.
</p>

<p align="center">
  <a href="https://github.com/guilhermelcosta/catarina/actions/workflows/ci.yml"><img src="https://github.com/guilhermelcosta/catarina/actions/workflows/ci.yml/badge.svg" alt="CI" /></a>
  <img src="https://img.shields.io/badge/Qt-6.5%2B-41CD52?logo=qt&logoColor=white" alt="Qt 6.5+" />
  <img src="https://img.shields.io/badge/KDE%20Kirigami-6-1D99F3?logo=kde&logoColor=white" alt="KDE Kirigami 6" />
  <img src="https://img.shields.io/badge/platform-Linux-informational" alt="Linux" />
  <img src="https://img.shields.io/badge/license-GPL--3.0--or--later-blue" alt="GPL-3.0-or-later" />
</p>

![Catarina](assets/screenshots/request-response.png)

## Why Catarina

Most API clients want an account and keep your work in their cloud. Catarina is
an ordinary folder of files.

- **Own your data.** One `.json` per request, in a directory you pick. No account, no sync, no export button, no lock-in.
- **Git is the collaboration layer.** Diff an API change, branch an experiment, review a pull request, share a folder.
- **Secrets stay out of Git.** Tokens live in the system keyring; the request file stores only a `secretId`.
- **Native, not Electron.** Qt 6 and Kirigami. Fast startup, low memory, one binary.
- **Free and open source.** GPL-3.0-or-later. No paid tier, no telemetry, no limits.

|               | Catarina                             | Cloud API clients            |
| ------------- | ------------------------------------ | ---------------------------- |
| Collections   | Plain JSON files in a folder you own | Workspace in their cloud     |
| Account       | None                                 | Usually required             |
| Collaboration | Git: diff, branch, review            | Export/import or in-app sync |
| Secrets       | System keyring                       | App or cloud storage         |
| Runtime       | Qt 6 / Kirigami                      | Electron in many cases       |
| Cost          | Free, GPL-3.0-or-later               | Free tier plus paid plans    |

## Features

- **Requests:** method, URL, params, headers, auth (Bearer, Basic, API key, inherited) and bodies (JSON, text, form, multipart).
- **Variables:** `{{name}}` resolved from global to collection to request, with autocomplete, hover values and undefined-variable warnings.
- **Dynamic values:** `{{$randomUuid}}`, `{{$randomTimestamp}}`, `{{$randomInt}}`, `{{$randomBoolean}}` and more, generated per send.
- **Collections:** nested folders, drag and drop, rename, duplicate and move.
- **Responses:** body, JSON tree, headers, cookies and a network timeline.
- **Workflow:** cURL import/export, history, command palette and remappable shortcuts.
- **Tabs:** preview, pin, reorder, reopen closed and restore the last session.

## Install

From source, one command:

```sh
./scripts/install.sh     # builds and installs to ~/.local
```

Then remove it, keeping your data:

```sh
./scripts/uninstall.sh
```

Install to another prefix:

```sh
PREFIX=/opt/catarina ./scripts/install.sh
PREFIX=/opt/catarina ./scripts/uninstall.sh
```

The uninstall script removes the binary, desktop file, icon and metainfo. It
does not touch your collections, settings, history or secrets.

Flatpak manifest: `packaging/io.github.guilhermelcosta.Catarina.yml`. Flathub
submission is pending.

To build and run from the tree instead:

```sh
cmake -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build -j
./build/bin/catarina
```

Dependencies, distro packages, Flatpak and tests: **[docs/BUILD.md](docs/BUILD.md)**.

## Development

```sh
ctest --test-dir build --output-on-failure
```

- Build and test details: [docs/BUILD.md](docs/BUILD.md)
- Architecture and data locations: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
- UI patterns: [docs/DESIGN.md](docs/DESIGN.md)
- Releases and branch model: [docs/RELEASING.md](docs/RELEASING.md)
- Agent and contributor rules: [AGENTS.md](AGENTS.md)

## Contributing

Read `AGENTS.md` before opening a pull request. Branch from `develop`, use
`feature/<slug>` or another `<type>/<slug>`, keep one behaviour per PR, run
`ctest`, and never commit secrets. UI changes follow `docs/DESIGN.md`.

## License

GPL-3.0-or-later. See [LICENSE](LICENSE).

## Credits

Built with [Qt](https://www.qt.io/) and [KDE Kirigami](https://invent.kde.org/frameworks/kirigami).
The example collection uses the public [DummyJSON](https://dummyjson.com/) API.
