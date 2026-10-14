#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# PtyBox - sync_termux_shared.sh [--copy]
#
# El modulo termux-shared esta EMBEBIDO en este repositorio (ver settings.gradle)
# para que la API compile siempre contra el mismo TermuxConstants que la app.
# El coste de esa decision es que hay dos copias que mantener sincronizadas.
#
#   ./scripts/sync_termux_shared.sh --check   compara con ../ptybox-app (CI)
#   ./scripts/sync_termux_shared.sh --copy    copia ../ptybox-app -> aqui
#
# Si el repositorio hermano no existe (CI de ptybox-api en solitario), el
# script verifica igualmente la invariante que importa: que el paquete embebido
# apunte a com.ptybox y no a com.termux.
# =============================================================================
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
SIBLING="$(cd "$REPO/.." 2>/dev/null && pwd)/ptybox-app/termux-shared"
LOCAL="$REPO/termux-shared"
CONSTANTS="$LOCAL/src/main/java/com/ptybox/shared/termux/TermuxConstants.java"

FAIL=0
ok()  { printf '  \033[32mOK\033[0m   %s\n' "$*"; }
bad() { printf '  \033[31mFAIL\033[0m %s\n' "$*"; FAIL=1; }

echo "== Sincronizacion de termux-shared =="

if [ ! -f "$CONSTANTS" ]; then
    bad "no existe $CONSTANTS"
    exit 1
fi

# 1. Invariante critica: el paquete del modulo embebido.
if grep -q 'TERMUX_PACKAGE_NAME = "com.ptybox"' "$CONSTANTS"; then
    ok "TermuxConstants.TERMUX_PACKAGE_NAME = com.ptybox"
else
    bad "TermuxConstants.TERMUX_PACKAGE_NAME no es com.ptybox: la API enviaria intents a la app equivocada"
fi
if grep -q 'TERMUX_APP_NAME = "PtyBox"' "$CONSTANTS"; then
    ok "TermuxConstants.TERMUX_APP_NAME = PtyBox"
else
    bad "TermuxConstants.TERMUX_APP_NAME no es PtyBox"
fi

# 2. Cero referencias funcionales al paquete original. Se ignoran los
#    comentarios (javadoc y //) porque ahi el nombre original es documentacion
#    del upstream, no comportamiento.
STRAY="$(
    find "$LOCAL/src/main/java" -name '*.java' 2>/dev/null | while read -r f; do
        awk -v file="$f" '
            {
                line = $0
                sub(/\/\/.*/, "", line)          # elimina comentario de linea
                if (line ~ /^[[:space:]]*\*/) next  # descarta lineas de javadoc
                if (line !~ /com\.termux/) next
                if (line ~ /com\.termux\.am\./) next          # libreria externa
                if (line ~ /com\.termux:termux-am-library/) next # coordenada maven
                printf "%s:%d: %s\n", file, FNR, line
            }' "$f"
    done
)"
if [ -z "$STRAY" ]; then
    ok "sin referencias a com.termux en el codigo del modulo"
else
    bad "quedan referencias a com.termux:"
    echo "$STRAY" | head -10 | sed 's/^/        /'
fi

case "${1:---check}" in
--copy)
    if [ ! -d "$SIBLING" ]; then
        bad "no encuentro el repositorio hermano: $SIBLING"
        exit 1
    fi
    echo "  copiando $SIBLING -> $LOCAL"
    rm -rf "$LOCAL"
    cp -r "$SIBLING" "$LOCAL"
    ok "copiado"
    ;;
--check)
    if [ -d "$SIBLING" ]; then
        DIFF_OUT="$(diff -rq "$SIBLING" "$LOCAL" 2>&1)"
        if [ -z "$DIFF_OUT" ]; then
            ok "termux-shared identico al de ptybox-app"
        else
            bad "termux-shared DIVERGE de ptybox-app:"
            printf '%s\n' "$DIFF_OUT" | head -20 | sed 's/^/        /'
            echo "        Ejecuta: ./scripts/sync_termux_shared.sh --copy"
        fi
    else
        echo "  aviso: $SIBLING no existe (build en solitario). Solo se validan las invariantes."
    fi
    ;;
*)
    echo "uso: $0 [--check|--copy]" >&2
    exit 2
    ;;
esac

echo
[ "$FAIL" -eq 0 ] || { echo "Sincronizacion incorrecta."; exit 1; }
echo "Sincronizacion correcta."