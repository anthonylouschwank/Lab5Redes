#!/usr/bin/env bash
# lib.sh — Funciones comunes de los scripts de la Fase 3 (Leonardo).
# No se ejecuta sola: cada script la carga con
#   source "$(dirname "$0")/lib.sh"
#
# Ofrece: mensajes (paso/info/ok/aviso/falla/die), archivo de evidencias,
# carga de fase3.env, respaldos con timestamp, escritura idempotente de archivos,
# instalación de paquetes que detecta si la EC2 no tiene salida a Internet,
# confirmaciones por terminal y el resumen final con código de salida.

[[ -n "${_FASE3_LIB:-}" ]] && return 0
_FASE3_LIB=1

FASE3_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FASE3_TS="$(date +%Y%m%d%H%M%S)"
FASE3_FALLAS=0
FASE3_REGISTRO_RESPALDOS="/var/log/fase3-respaldos.log"
EVIDENCIA=""

if [[ -t 1 ]]; then
    C_OK=$'\e[32m'; C_ERR=$'\e[31m'; C_WARN=$'\e[33m'; C_PASO=$'\e[1;36m'; C_0=$'\e[0m'
else
    C_OK=""; C_ERR=""; C_WARN=""; C_PASO=""; C_0=""
fi

# ---------------------------------------------------------------- mensajes
evid() {
    if [[ -n "$EVIDENCIA" ]]; then printf '%s\n' "$*" >> "$EVIDENCIA"; fi
}
paso()  { printf '\n%s==> %s%s\n' "$C_PASO" "$*" "$C_0"; evid ""; evid "==> $*"; }
info()  { printf '    %s\n' "$*"; evid "    $*"; }
ok()    { printf '    %s[OK]%s %s\n' "$C_OK" "$C_0" "$*"; evid "    [OK] $*"; }
aviso() { printf '    %s[AVISO]%s %s\n' "$C_WARN" "$C_0" "$*" >&2; evid "    [AVISO] $*"; }
falla() {
    printf '    %s[FALLO]%s %s\n' "$C_ERR" "$C_0" "$*" >&2
    evid "    [FALLO] $*"
    FASE3_FALLAS=$((FASE3_FALLAS + 1))
}
die() {
    printf '\n%s[ERROR]%s %s\n' "$C_ERR" "$C_0" "$*" >&2
    evid "[ERROR] $*"
    printf '%sRESULTADO: FALLO%s\n' "$C_ERR" "$C_0" >&2
    evid "RESULTADO: FALLO"
    exit 1
}

# mostrar "título" comando args...   -> ejecuta, muestra la salida sangrada y la guarda en la evidencia.
# No aborta si el comando falla (es solo para mostrar estado).
mostrar() {
    local titulo=$1 salida
    shift
    salida="$("$@" 2>&1)" || true
    printf '    -- %s --\n' "$titulo"
    printf '%s\n' "$salida" | sed 's/^/      /'
    evid "    -- $titulo (\$ $*) --"
    evid "$(printf '%s\n' "$salida" | sed 's/^/      /')"
}

# ---------------------------------------------------------------- arranque
require_root() {
    [[ ${EUID} -eq 0 ]] || die "Hay que ejecutarlo como root: sudo bash $0 ..."
}

revisar_ubuntu() {
    local id="" version=""
    if [[ -r /etc/os-release ]]; then
        # shellcheck disable=SC1091
        id="$(. /etc/os-release && echo "${ID:-}")"
        # shellcheck disable=SC1091
        version="$(. /etc/os-release && echo "${VERSION_ID:-}")"
    fi
    if [[ "$id" != "ubuntu" || "$version" != "24.04" ]]; then
        aviso "Probado para Ubuntu 24.04; este equipo es '${id:-?} ${version:-?}'. Revisa los resultados con cuidado."
    fi
}

# Carga las variables: FASE3_ENV (si se define), si no fase3.env junto a los scripts,
# si no fase3.env.example. Las variables ya exportadas en el entorno tienen prioridad
# (el archivo usa la forma  : "${VAR:=valor}").
cargar_env() {
    local f
    if [[ -n "${FASE3_ENV:-}" ]]; then
        f="$FASE3_ENV"
    elif [[ -f "$FASE3_DIR/fase3.env" ]]; then
        f="$FASE3_DIR/fase3.env"
    else
        f="$FASE3_DIR/fase3.env.example"
        aviso "No existe fase3.env: se usan los valores de fase3.env.example."
    fi
    [[ -f "$f" ]] || die "No encuentro el archivo de variables: $f"
    # shellcheck source=fase3.env.example
    source "$f"
    FASE3_ENV_USADO="$f"
}

# Abre (o continúa) el archivo de evidencias del día: evidencias-<host>-<fecha>.txt
iniciar_evidencia() {
    local script=$1
    shift
    EVIDENCIA="${FASE3_EVID_DIR:-$PWD}/evidencias-$(hostname)-$(date +%F).txt"
    {
        printf '\n%s\n' "################################################################"
        printf '# %s %s\n' "$script" "$*"
        printf '# Fecha: %s   Equipo: %s   Usuario: %s\n' "$(date '+%F %T %Z')" "$(hostname)" "${SUDO_USER:-$USER}"
        printf '# Variables: %s\n' "${FASE3_ENV_USADO:-?}"
        printf '%s\n' "################################################################"
    } >> "$EVIDENCIA"
}

# Resumen final: OK si no hubo fallas, FALLO (exit 1) si las hubo.
resumen_final() {
    local que=$1
    printf '\n'
    if [[ -n "$EVIDENCIA" && -n "${SUDO_USER:-}" ]]; then
        chown "$SUDO_USER": "$EVIDENCIA" 2>/dev/null || true
    fi
    if ((FASE3_FALLAS == 0)); then
        printf '%sRESULTADO: OK%s — %s\n' "$C_OK" "$C_0" "$que"
        evid "RESULTADO: OK — $que"
    else
        printf '%sRESULTADO: FALLO%s — %s (%d problema(s), ver [FALLO] arriba)\n' "$C_ERR" "$C_0" "$que" "$FASE3_FALLAS" >&2
        evid "RESULTADO: FALLO — $que ($FASE3_FALLAS problema(s))"
    fi
    if [[ -n "$EVIDENCIA" ]]; then printf 'Evidencia: %s\n' "$EVIDENCIA"; fi
    ((FASE3_FALLAS == 0))
}

# ---------------------------------------------------------------- archivos
# respaldar ARCHIVO  -> copia ARCHIVO.bak.<timestamp> y anota cómo restaurarlo.
respaldar() {
    local f=$1 copia
    [[ -e "$f" ]] || return 0
    copia="${f}.bak.${FASE3_TS}"
    cp -a "$f" "$copia"
    printf '%s %s -> %s   (restaurar: sudo cp -a %s %s)\n' "$(date '+%F %T')" "$f" "$copia" "$copia" "$f" \
        >> "$FASE3_REGISTRO_RESPALDOS"
    info "Respaldo: $copia   (restaurar: sudo cp -a $copia $f)"
}

# escribir_si_cambia DESTINO [MODO]   (contenido por stdin)
# Solo escribe si el contenido cambió (idempotente); si no cambió, no respalda ni toca nada.
escribir_si_cambia() {
    local dest=$1 modo=${2:-644} tmp
    tmp="$(mktemp)"
    cat > "$tmp"
    if [[ -f "$dest" ]] && cmp -s "$tmp" "$dest"; then
        rm -f "$tmp"
        info "Sin cambios: $dest"
        return 0
    fi
    if [[ -e "$dest" ]]; then respaldar "$dest"; fi
    install -D -m "$modo" "$tmp" "$dest"
    rm -f "$tmp"
    ok "Escrito: $dest"
}

# ---------------------------------------------------------------- paquetes
# asegurar_paquetes paq1 paq2 ...
# Si ya están instalados no toca la red. Si faltan, comprueba primero que apt alcance
# el repositorio (con timeout) y, si no, explica qué falta en vez de quedarse colgado.
asegurar_paquetes() {
    local faltan=() p salida
    for p in "$@"; do
        if ! dpkg-query -W -f='${Status}' "$p" 2>/dev/null | grep -q 'install ok installed'; then
            faltan+=("$p")
        fi
    done
    if ((${#faltan[@]} == 0)); then
        ok "Paquetes ya instalados: $*"
        return 0
    fi
    info "Faltan paquetes: ${faltan[*]}. Compruebo que apt alcance el repositorio (máx. 90 s)..."
    if ! salida="$(timeout 90 apt-get update -q \
            -o Acquire::Retries=0 -o Acquire::http::Timeout=10 -o Acquire::https::Timeout=10 \
            -o DPkg::Lock::Timeout=60 2>&1)" \
        || grep -qE '^(W|E): (Failed to fetch|Some index files failed|Could not)|Temporary failure resolving|Could not connect|Unable to connect|Network is unreachable|Connection timed out' <<<"$salida"; then
        printf '%s\n' "$salida" | grep -E '^(W|E):|Err:' | tail -n 4 | cut -c1-160 | sed 's/^/      /' >&2
        die "Esta máquina no alcanza el repositorio de Ubuntu (no tiene salida a Internet).
       Falta: NAT funcionando + ruta 0.0.0.0/0 hacia la NAT en la tabla de rutas de ESTA subred,
       y que su Security Group permita salida TCP 80/443. Paquetes pendientes: ${faltan[*]}"
    fi
    if ! DEBIAN_FRONTEND=noninteractive timeout 600 apt-get install -y -q \
            -o DPkg::Lock::Timeout=120 "${faltan[@]}"; then
        die "apt-get install falló para: ${faltan[*]}"
    fi
    ok "Instalados: ${faltan[*]}"
}

# ---------------------------------------------------------------- interacción
# confirmar "pregunta" [segundos]  -> 0 si la persona escribe SI. Lee de la terminal (/dev/tty).
confirmar() {
    local pregunta=$1 limite=${2:-120} resp=""
    if [[ ! -r /dev/tty ]] || ! { : < /dev/tty; } 2>/dev/null; then
        aviso "Sin terminal interactiva: se toma como NO -> $pregunta"
        return 1
    fi
    # Descarta lo que se haya tecleado antes de ver la pregunta (que no se responda sola).
    while read -r -t 0.2 -n 256 _ < /dev/tty 2>/dev/null; do :; done
    printf '\n    %s?%s %s [escribe SI y Enter; %ss] ' "$C_WARN" "$C_0" "$pregunta" "$limite" > /dev/tty
    if ! read -r -t "$limite" resp < /dev/tty; then
        printf '\n' > /dev/tty
        return 1
    fi
    [[ "${resp^^}" == "SI" || "${resp^^}" == "SÍ" ]]
}

# ---------------------------------------------------------------- red
# Interfaz con la ruta por defecto (no se asume ens5).
interfaz_salida() {
    local i
    i="$(ip -o -4 route show to default 2>/dev/null | awk '{for (k=1;k<NF;k++) if ($k=="dev") {print $(k+1); exit}}')"
    if [[ -z "$i" ]]; then
        i="$(ip -o -4 route get 1.1.1.1 2>/dev/null | awk '{for (k=1;k<NF;k++) if ($k=="dev") {print $(k+1); exit}}')"
    fi
    printf '%s' "$i"
}

# ---------------------------------------------------------------- chrony
# Muestra el estado de chrony (para inspeccionar antes de cambiar y verificar después).
chrony_estado() {
    mostrar "chronyc -n sources -v" chronyc -n sources -v
    mostrar "chronyc tracking" chronyc tracking
    mostrar "timedatectl (NTPSynchronized)" timedatectl show -p NTPSynchronized -p NTP
}

# chrony_esperar IP [segundos]  -> 0 cuando la fuente IP queda seleccionada (^*).
chrony_esperar() {
    local ip=$1 limite=${2:-90} t=0
    while ((t < limite)); do
        if chronyc -n sources 2>/dev/null | grep -qE "^\^\*[[:space:]]+${ip//./\\.}[[:space:]]"; then
            return 0
        fi
        sleep 5
        t=$((t + 5))
    done
    return 1
}

# Paquetes recibidos de una fuente NTP (0 = no responde). Necesita root (chronyc ntpdata);
# sin permiso devuelve vacío. Nunca hace fallar al script que la llama.
chrony_rx() {
    { chronyc -n ntpdata "$1" 2>/dev/null || true; } | awk -F': *' '/^Total RX/ {print $2; exit}'
}
