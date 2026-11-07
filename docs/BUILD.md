# Building Catarina

## Dependencies

- **Qt 6.5+**: Core, Gui, Qml, Quick, QuickControls2, Network
- **Extra CMake Modules 6**
- **KF6 Kirigami**
- **QtKeychain** (optional): enables the OS keyring. Without it, secrets go to a
  `0600` file.

### Fedora / KDE

```sh
sudo dnf install cmake gcc-c++ \
    extra-cmake-modules \
    qt6-qtbase-devel qt6-qtdeclarative-devel qt6-qtquickcontrols2-devel \
    kf6-kirigami-devel qtkeychain-qt6-devel
```

### Arch

```sh
sudo pacman -S cmake extra-cmake-modules \
    qt6-base qt6-declarative qt6-quickcontrols2 kirigami qtkeychain-qt6
```

### Debian / Ubuntu

```sh
sudo apt install cmake g++ extra-cmake-modules \
    qt6-base-dev qt6-declarative-dev qt6-quickcontrols2-dev \
    kirigami6-dev libqt6keychain1
```

Package names vary by release. If `find_package(Qt6Keychain)` fails, install the
QtKeychain development package for your distro.

## Quick install and uninstall (user-local)

```sh
./scripts/install.sh     # build and install to ~/.local
./scripts/uninstall.sh   # remove the app files
```

Installs to `~/.local` by default (`~/.local/bin/catarina`, desktop file, icon
and metainfo). Override the prefix with:

```sh
PREFIX=/some/prefix ./scripts/install.sh
PREFIX=/some/prefix ./scripts/uninstall.sh
```

The uninstall script removes only the files installed by the install script. It
does not touch collections, settings, history or secrets. Close the installed app
before uninstalling.

The script still builds; the build is incremental, so a second run is quick. The
`build-install/` directory is a build artifact and can be deleted manually.

## Build and run

```sh
cmake -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build -j
./build/bin/catarina
```

## Install

```sh
sudo cmake --install build
```

## Flatpak

The manifest builds the tagged release, not the current working tree. For local
changes use the CMake build above.

```sh
flatpak run --command=flathub-build org.flatpak.Builder --install \
    packaging/io.github.guilhermelcosta.Catarina.yml
```

## Tests

```sh
ctest --test-dir build --output-on-failure
```

| Target | Covers |
|---|---|
| `check_storage` | request logic, variable resolution, secrets, persistence, seed |
| `check_http` | real HTTP against a local server: response, error, cancellation, multipart |
| `tst_components` | QML components and JS logic |
| `tst_app` | screens and AppController behaviour |
| `check_highlighter` | JSON syntax highlighting |
| `qml_smoke` | the app loads with no QML errors |

Tests are hermetic: they use a temporary directory and do not touch your data or
the real keyring.
