#!/usr/bin/env bash
# Build Catarina and install it into a user-local prefix.
#
# Usage:
#   ./scripts/install.sh
#   PREFIX=/opt/catarina ./scripts/install.sh
#   BUILD_DIR=/tmp/catarina-build ./scripts/install.sh

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PREFIX="${PREFIX:-$HOME/.local}"
BUILD_DIR="${BUILD_DIR:-$ROOT/build-install}"

cmake -S "$ROOT" -B "$BUILD_DIR" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$PREFIX"
cmake --build "$BUILD_DIR" --parallel "$(nproc)" --target catarina
cmake --install "$BUILD_DIR"

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
echo "Installed to $PREFIX"
echo "Run: $PREFIX/bin/catarina"
case ":$PATH:" in
    *":$PREFIX/bin:"*) ;;
    *) echo "Add $PREFIX/bin to PATH to run it by name." ;;
esac
