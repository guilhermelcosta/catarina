#!/bin/sh
# Smoke test: ensures Main.qml loads without QML errors.
# Passes if the app stays alive until the timeout (rc 124) with no errors in the log.
bin="$1"
if [ -z "$bin" ] || [ ! -x "$bin" ]; then
    echo "usage: qml_smoke.sh <binary-path>"
    exit 2
fi

log="$(mktemp)"
tmp="$(mktemp -d)"
trap 'rm -f "$log"; rm -rf "$tmp"' EXIT

# hermetic: temp home/config/data so the smoke test never touches the user's
# real settings/collections (and never creates the default ~/Documents/catarina)
HOME="$tmp" XDG_CONFIG_HOME="$tmp/config" XDG_DATA_HOME="$tmp/data" \
    CATARINA_SECRETS_BACKEND=file timeout 6 "$bin" >"$log" 2>&1
rc=$?

if [ "$rc" -ne 124 ]; then
    echo "catarina exited on its own (rc=$rc) — likely failure loading QML:"
    cat "$log"
    exit 1
fi

if grep -qiE "QQmlApplicationEngine failed|is not a type|is not defined|ReferenceError|TypeError|Cannot assign|Unable to assign|No such" "$log"; then
    echo "QML errors in the log:"
    cat "$log"
    exit 1
fi

exit 0
