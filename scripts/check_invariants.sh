#!/usr/bin/env bash
# =============================================================================
# PtyBox:API - check_invariants.sh
#
# En la API las invariantes son distintas de las de la app y por eso tiene su
# propio script en vez de una copia del de ptybox-app:
#
#   - La API se instala como com.ptybox.api, que NO necesita medir 10
#     caracteres: no contiene $PREFIX ni binarios con el prefijo horneado.
#     La app principal es la que arrastra esa restriccion.
#   - Lo que la API tiene que compartir con la app es el paquete ANFITRION
#     (com.ptybox), que es de donde salen sharedUserId, los intents y los
#     permisos. Si aqui se declarara com.termux, la API le hablaria a la app
#     equivocada.
#   - El termux-shared va embebido; si divergiera del de ptybox-app, la API
#     podria compilar contra un TermuxConstants distinto.
#
# No depende de nada fuera del repo: funciona igual en Termux que en CI.
# =============================================================================
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
cd "$REPO"

FAIL=0
ok()   { printf '  \033[32mOK\033[0m   %s\n' "$*"; }
bad()  { printf '  \033[31mFAIL\033[0m %s\n' "$*"; FAIL=1; }

first() {
    [ -f "$1" ] || return 1
    sed -nE "s|.*$2.*|\1|p" "$1" 2>/dev/null | head -1
}

APP_GRADLE="app/build.gradle"
CONSTANTS="termux-shared/src/main/java/com/ptybox/shared/termux/TermuxConstants.java"
MANIFEST="app/src/main/AndroidManifest.xml"
STRINGS="app/src/main/res/values/strings.xml"

GRADLE_PKG="$(first "$APP_GRADLE" 'applicationId[[:space:]]+"([^"]+)"')"
GRADLE_VERSION="$(first "$APP_GRADLE" 'versionName[[:space:]]+"([^"]+)"')"
GRADLE_HOST="$(first "$APP_GRADLE" 'TERMUX_PACKAGE_NAME[[:space:]]*=[[:space:]]*"([^"]+)"')"
CONST_PKG="$(first "$CONSTANTS" 'TERMUX_PACKAGE_NAME[[:space:]]*=[[:space:]]*"([^"]+)"')"
XML_PKG="$(first "$STRINGS" '<!ENTITY TERMUX_PACKAGE_NAME "([^"]+)"')"

# El paquete anfitrion debe medir 10 caracteres porque es el que usa la app.
HOST="${PTYBOX_PKG:-com.ptybox}"
API_PKG="${PTYBOX_API_PKG:-${GRADLE_PKG:-com.ptybox.api}}"

echo "== Invariantes de PtyBox:API =="
echo
echo "-- Valores declarados --"
printf '  %-32s %s\n' "build.gradle applicationId"        "${GRADLE_PKG:-<NO ENCONTRADO>}"
printf '  %-32s %s\n' "build.gradle versionName"          "${GRADLE_VERSION:-<NO ENCONTRADO>}"
printf '  %-32s %s\n' "build.gradle TERMUX_PACKAGE_NAME"  "${GRADLE_HOST:-<NO ENCONTRADO>}"
printf '  %-32s %s\n' "TermuxConstants PACKAGE (anfitrion)" "${CONST_PKG:-<NO ENCONTRADO>}"
printf '  %-32s %s\n' "strings.xml PACKAGE (anfitrion)"    "${XML_PKG:-<NO ENCONTRADO>}"
echo

echo "-- Paquete de la API --"
if [ "$GRADLE_PKG" = "$API_PKG" ]; then
    ok "la API se instala como $GRADLE_PKG"
else
    bad "applicationId dice '$GRADLE_PKG' pero se esperaba '$API_PKG'"
fi
if [ "$GRADLE_PKG" = "com.termux.api" ]; then
    bad "la API sigue con el paquete de Termux original"
else
    ok "no colisiona con com.termux.api"
fi
if [ "$GRADLE_PKG" = "$HOST" ]; then
    bad "la API comparte paquete con la app: no pueden instalarse por separado"
else
    ok "paquete distinto del de la app ($HOST)"
fi

echo
echo "-- Paquete anfitrion: debe coincidir con el de PtyBox --"
for pair in "build.gradle:${GRADLE_HOST}" "TermuxConstants:${CONST_PKG}" "strings.xml:${XML_PKG}"; do
    where="${pair%%:*}"; value="${pair#*:}"
    if [ -z "$value" ]; then
        bad "$where no declara el paquete anfitrion"
    elif [ "$value" = "$HOST" ]; then
        ok "$where = $value"
    else
        bad "$where dice '$value' pero el anfitrion es '$HOST'"
    fi
done
if [ ${#HOST} -eq 10 ]; then
    ok "el anfitrion '$HOST' mide 10 caracteres (lo exige el parcheo del bootstrap)"
else
    bad "el anfitrion '$HOST' mide ${#HOST} caracteres: la app no se podria parchear"
fi

echo
echo "-- sharedUserId --"
if grep -q 'android:sharedUserId="\${TERMUX_PACKAGE_NAME}"' "$MANIFEST" 2>/dev/null; then
    ok "sharedUserId parametrizado con TERMUX_PACKAGE_NAME -> $HOST"
elif grep -q "android:sharedUserId=\"${HOST}\"" "$MANIFEST" 2>/dev/null; then
    ok "sharedUserId = $HOST"
else
    bad "el manifiesto no declara sharedUserId como $HOST"
fi

echo
echo "-- termux-shared embebido --"
if [ -f "$CONSTANTS" ]; then
    ok "termux-shared esta embebido en este repo"
    if grep -q 'implementation project(":termux-shared")' "$APP_GRADLE" 2>/dev/null; then
        ok "la app depende del modulo local, no de jitpack"
    else
        bad "la API ya no usa el termux-shared embebido: puede compilar contra otra copia"
    fi
    for m in terminal-view terminal-emulator; do
        if [ -d "$m" ]; then
            ok "$m presente (dependencia de termux-shared)"
        else
            bad "falta el modulo $m, del que depende termux-shared"
        fi
    done
    for p in ndkVersion markwonVersion compileSdkVersion; do
        if grep -q "^${p}=" gradle.properties 2>/dev/null; then
            ok "gradle.properties declara ${p}"
        else
            bad "gradle.properties no declara ${p}: los modulos embebidos no construiran"
        fi
    done
else
    bad "no hay termux-shared embebido"
fi

echo
echo "-- Version --"
if [ -n "$GRADLE_VERSION" ] && printf '%s' "${GRADLE_VERSION#v}" \
   | grep -qP '^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-((?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*)(?:\.(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*))*))?(?:\+([0-9a-zA-Z-]+(?:\.[0-9a-zA-Z-]+)*))?$'; then
    ok "versionName '$GRADLE_VERSION' valido (semver 2.0.0)"
else
    bad "versionName '${GRADLE_VERSION:-<vacio>}' no cumple semver 2.0.0"
fi

echo
if [ "$FAIL" -ne 0 ]; then
    echo "Invariantes rotas: NO se debe compilar."
    exit 1
fi
echo "Todas las invariantes se cumplen."