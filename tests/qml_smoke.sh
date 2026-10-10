#!/bin/sh
# Smoke test: garante que o Main.qml carrega sem erros de QML.
# Passa se o app continuar vivo até o timeout (rc 124) sem erros no log.
bin="$1"
if [ -z "$bin" ] || [ ! -x "$bin" ]; then
    echo "uso: qml_smoke.sh <caminho-do-binario>"
    exit 2
fi

log="$(mktemp)"
trap 'rm -f "$log"' EXIT

timeout 6 "$bin" >"$log" 2>&1
rc=$?

if [ "$rc" -ne 124 ]; then
    echo "catarina encerrou sozinho (rc=$rc) — provável falha ao carregar o QML:"
    cat "$log"
    exit 1
fi

if grep -qiE "QQmlApplicationEngine failed|is not a type|is not defined|ReferenceError|TypeError|Cannot assign|Unable to assign|No such" "$log"; then
    echo "erros de QML no log:"
    cat "$log"
    exit 1
fi

exit 0
