#!/usr/bin/env bash
# Pruebas de la intranet (E6.1–E6.3). Escribe una tabla PASS/FAIL; las contraseñas nunca se muestran.
#
# Uso:
#   bash probar-web.sh                                   # en la propia EC2 Servidores (http://127.0.0.1)
#   INTRANET_URL=http://10.0.0.46 bash probar-web.sh     # desde otra EC2 autorizada (TI, Médicos, DMZ)
#   bash probar-web.sh --desde 10.0.0.70                 # + simula un origen NO autorizado (esperado 403)
#
# Variables (credenciales SOLO por entorno o teclado):
#   WEB_USER (ti01)            usuario ficticio del grupo ti
#   WEB_PASS                   su contraseña (si falta, se pide con read -s)
#   WEB_USER_SIN_TI (medico01) usuario de otro grupo, para el panel de TI
#   WEB_PASS_SIN_TI            su contraseña (por defecto, la misma: Sebastián usa una sola para los ficticios)
#
# --desde IP: la petición sale con esa IP de origen (curl --interface). La IP debe existir en el equipo,
# p. ej. en la VM local: sudo ip addr add 10.0.0.70/32 dev lo  (y luego: sudo ip addr del 10.0.0.70/32 dev lo)
set -euo pipefail

URL="${INTRANET_URL:-http://127.0.0.1}"
URL="${URL%/}"
WEB_USER="${WEB_USER:-ti01}"
WEB_USER_SIN_TI="${WEB_USER_SIN_TI:-medico01}"
DESDE=""
[[ "${1:-}" == "--desde" ]] && DESDE="${2:?Falta la IP de origen}"

if [[ -z "${WEB_PASS:-}" ]]; then
    [[ -t 0 ]] || { echo "ERROR: defina WEB_PASS o ejecute desde una terminal." >&2; exit 1; }
    read -r -s -p "Contraseña de ${WEB_USER}: " WEB_PASS; echo
fi
WEB_PASS_SIN_TI="${WEB_PASS_SIN_TI:-${WEB_PASS}}"

HOST="${URL#*://}"; HOST="${HOST%%[:/]*}"
TMPD="$(umask 077; mktemp -d)"
trap 'rm -rf "${TMPD}"; unset WEB_PASS WEB_PASS_SIN_TI' EXIT
netrc() { printf 'machine %s login %s password %s\n' "${HOST}" "$1" "$2" > "${TMPD}/$3"; }
netrc "${WEB_USER}"        "${WEB_PASS}"            valido
netrc "${WEB_USER}"        "contrasena-incorrecta"  invalido
netrc "noexiste"           "cualquiera"             inexistente
netrc "${WEB_USER_SIN_TI}" "${WEB_PASS_SIN_TI}"     sinti

FALLAS=0
codigo() {  # codigo <ruta> [netrc] [ip-origen]
    local args=(-s -o "${TMPD}/cuerpo" -w '%{http_code}' -m 8)
    [[ -n "${2:-}" ]] && args+=(--netrc-file "${TMPD}/$2")
    [[ -n "${3:-}" ]] && args+=(--interface "$3")
    curl "${args[@]}" "${URL}$1" 2>/dev/null || true
}
prueba() {  # prueba <id> <descripcion> <esperado> <obtenido> [texto que debe aparecer]
    local res=PASS
    [[ "$4" == "$3" ]] || res=FAIL
    if [[ $res == PASS && -n "${5:-}" ]] && ! grep -q "$5" "${TMPD}/cuerpo"; then res=FAIL; fi
    [[ $res == PASS ]] || FALLAS=$((FALLAS + 1))
    printf '%-9s %-52s esperado %-4s obtenido %-4s %s\n' "$1" "$2" "$3" "$4" "$res"
}

echo "# Pruebas de la intranet — $(date '+%F %T %Z') — equipo $(hostname) — destino ${URL}"
echo
prueba W-01 "Portal sin login desde origen autorizado"         200 "$(codigo /)"                 "Hospital Privado Castillejos"
prueba W-02 "/intranet/ sin credenciales"                      401 "$(codigo /intranet/)"
prueba W-03 "/intranet/ con ${WEB_USER} y contraseña válida"   200 "$(codigo /intranet/ valido)" "Bienvenido(a)"
prueba W-04 "/intranet/ con ${WEB_USER} y contraseña inválida" 401 "$(codigo /intranet/ invalido)"
prueba W-05 "/intranet/ con usuario inexistente"               401 "$(codigo /intranet/ inexistente)"
prueba W-06 "/intranet/ti/ con ${WEB_USER} (grupo ti)"         200 "$(codigo /intranet/ti/ valido)" "Acceso concedido"
prueba W-07 "/intranet/ti/ con ${WEB_USER_SIN_TI} (sin grupo ti)" 401 "$(codigo /intranet/ti/ sinti)"
if [[ -n "${DESDE}" ]]; then
    prueba W-08 "Portal desde origen NO autorizado (${DESDE})" 403 "$(codigo / "" "${DESDE}")"
    prueba W-09 "/intranet/ con credencial válida desde ${DESDE}" 403 "$(codigo /intranet/ valido "${DESDE}")"
fi

echo
if (( FALLAS == 0 )); then echo "RESULTADO: PASS"; else echo "RESULTADO: FAIL (${FALLAS} prueba(s))"; exit 1; fi
