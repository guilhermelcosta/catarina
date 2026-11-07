#!/usr/bin/env bash
# Remove the Catarina files installed by scripts/install.sh.
#
# User data is not touched: collections, settings, history and secrets stay
# where they are.
#
# Usage:
#   ./scripts/uninstall.sh
#   PREFIX=/opt/catarina ./scripts/uninstall.sh

set -euo pipefail

PREFIX="${PREFIX:-$HOME/.local}"

if [ -z "$PREFIX" ] || [ "$PREFIX" = "/" ]; then
    echo "Refusing to uninstall from an empty prefix or /" >&2
    exit 1
fi

if pgrep -f "$PREFIX/bin/catarina" >/dev/null 2>&1; then
    echo "Catarina is running from $PREFIX/bin/catarina. Close it first." >&2
    exit 1
fi

files=(
    "$PREFIX/bin/catarina"
    "$PREFIX/share/applications/io.github.guilhermelcosta.Catarina.desktop"
    "$PREFIX/share/icons/hicolor/scalable/apps/io.github.guilhermelcosta.Catarina.svg"
    "$PREFIX/share/metainfo/io.github.guilhermelcosta.Catarina.metainfo.xml"
)

for file in "${files[@]}"; do
    if [ -e "$file" ]; then
        rm -f "$file"
        echo "Removed $file"
    else
        echo "Not installed: $file"
    fi
done

if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$PREFIX/share/applications" >/dev/null 2>&1 || true
fi
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    gtk-update-icon-cache -f -t "$PREFIX/share/icons/hicolor" >/dev/null 2>&1 || true
fi
if [ "$PREFIX" = "$HOME/.local" ] && command -v kbuildsycoca6 >/dev/null 2>&1; then
    kbuildsycoca6 >/dev/null 2>&1 || true
fi

echo
echo "Catarina removed from $PREFIX"
echo "Collections, settings, history and secrets were not touched."
