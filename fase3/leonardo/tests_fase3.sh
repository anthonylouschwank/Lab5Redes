#!/usr/bin/env bash
# tests_fase3.sh — Matriz de pruebas de conectividad de la Fase 3 (Hospital).
#
# Se ejecuta EN la EC2 de origen (no necesita root):
#   bash tests_fase3.sh <origen>                 # origen: ti|medicos|visitantes|servidores|dmz|nat
#   bash tests_fase3.sh <origen> --solo VIS-02   # repetir una sola prueba
#   bash tests_fase3.sh --lista [origen]         # ver las pruebas sin ejecutarlas
# Credenciales LDAP (opcionales, nunca se imprimen):
#   export LDAP_USER=ti01; read -rs LDAP_PASS; export LDAP_PASS
#
# Salida: resultados-<origen>-<fecha>.csv (para la matriz de Roberto) con columnas
#   fecha,origen,destino,protocolo_puerto,esperado,obtenido,resultado   (resultado = PASS|FAIL)
# Las pruebas cuyo destino no tiene IP en fase3.env se muestran como OMITIDA y no van al CSV.
#
# Criterio: "permitido" que no conecta = FAIL; "bloqueado" que conecta = FAIL. Un
# "connection refused" en una prueba "bloqueado" también es FAIL: el paquete llegó al
# equipo, o sea que la red (SG/NACL) no lo bloqueó.
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"

ORIGENES_VALIDOS="ti medicos visitantes servidores dmz nat"
origen=""; solo=""; listar=no
while (($#)); do
    case "$1" in
        --lista) listar=si ;;
        --solo) shift; solo="${1:-}"; [[ -n "$solo" ]] || die "--solo necesita un ID (ver --lista)" ;;
        -h|--help) sed -n '2,18p' "$0"; exit 0 ;;
        -*) die "Opción desconocida: $1" ;;
        *) origen="$1" ;;
    esac
    shift
done
if [[ -n "$origen" && " $ORIGENES_VALIDOS " != *" $origen "* ]]; then
    die "Origen inválido: '$origen'. Usa uno de: $ORIGENES_VALIDOS"
fi
[[ -n "$origen" || "$listar" == "si" ]] || die "Falta el origen. Uso: bash tests_fase3.sh <${ORIGENES_VALIDOS// /|}>"

cargar_env

# ---------------------------------------------------------------- matriz
# ID|ORIGEN|DESTINO|TIPO|PUERTO|ESPERADO|NOTA
#   TIPO: tcp, http, ldap, icmp, ntp (fuente ^* = destino), ntp-cualquiera (Leap Normal),
#         internet-tcp, internet-https
PRUEBAS=(
    "TI-01|ti|servidores|tcp|22|permitido|SSH TI -> Servidores"
    "TI-02|ti|servidores|http|${INTRANET_PORT}|permitido|Intranet desde TI"
    "TI-03|ti|servidores|ldap|${LDAP_PORT}|permitido|LDAP desde TI"
    "TI-04|ti|servidores|ntp|123|permitido|NTP interno (fuente ^*)"
    "TI-05|ti|servidores|icmp|-|permitido|Ping TI -> Servidores"
    "TI-06|ti|medicos|tcp|22|permitido|TI llega a Médicos"
    "TI-07|ti|visitantes|tcp|22|permitido|TI llega a Visitantes"
    "TI-08|ti|dmz|tcp|22|permitido|TI llega a la DMZ"
    "SRV-01|servidores|ti|tcp|22|bloqueado|Ninguna subred llega a TI"
    "SRV-02|servidores|servidores|http|${INTRANET_PORT}|permitido|Intranet desde Servidores"
    "SRV-03|servidores|servidores|ntp-cualquiera|123|permitido|El servidor NTP está sincronizado"
    "MED-01|medicos|ti|tcp|22|bloqueado|Ninguna subred llega a TI"
    "MED-02|medicos|ti|icmp|-|bloqueado|Ninguna subred llega a TI (ICMP)"
    "MED-03|medicos|servidores|http|${INTRANET_PORT}|permitido|Intranet desde Médicos"
    "MED-04|medicos|servidores|ldap|${LDAP_PORT}|bloqueado|LDAP solo desde Servidores y TI (contrato de Sebastián)"
    "MED-05|medicos|servidores|ntp|123|permitido|NTP interno (fuente ^*)"
    "VIS-01|visitantes|ti|tcp|22|bloqueado|Visitantes no llega a TI"
    "VIS-02|visitantes|servidores|http|${INTRANET_PORT}|bloqueado|Intranet NO desde Visitantes"
    "VIS-03|visitantes|servidores|tcp|22|bloqueado|Visitantes no llega a Servidores"
    "VIS-04|visitantes|servidores|ldap|${LDAP_PORT}|bloqueado|LDAP NO desde Visitantes"
    "VIS-05|visitantes|medicos|tcp|22|bloqueado|Visitantes no llega a Médicos"
    "VIS-06|visitantes|dmz|tcp|22|bloqueado|Visitantes no llega a la DMZ"
    "VIS-07|visitantes|ti|icmp|-|bloqueado|Visitantes no llega a TI (ICMP)"
    "VIS-08|visitantes|servidores|icmp|-|bloqueado|Visitantes no llega a Servidores (ICMP)"
    "VIS-09|visitantes|medicos|icmp|-|bloqueado|Visitantes no llega a Médicos (ICMP)"
    "VIS-10|visitantes|dmz|icmp|-|bloqueado|Visitantes no llega a la DMZ (ICMP)"
    "VIS-11|visitantes|internet|internet-tcp|${INTERNET_TEST_PORT}|permitido|Visitantes sí tiene Internet (por NAT)"
    "VIS-12|visitantes|internet|internet-https|443|permitido|Visitantes navega (HTTPS por NAT)"
    "VIS-13|visitantes|local|ntp-cualquiera|123|permitido|Hora sincronizada (Amazon Time Sync; no puede usar 10.0.0.46)"
    "DMZ-01|dmz|ti|tcp|22|bloqueado|Ninguna subred llega a TI"
    "DMZ-02|dmz|servidores|http|${INTRANET_PORT}|permitido|Intranet desde la DMZ"
    "DMZ-03|dmz|servidores|ntp|123|permitido|NTP interno (fuente ^*)"
    "NAT-01|nat|ti|tcp|22|bloqueado|Ninguna subred llega a TI"
    "NAT-02|nat|internet|internet-https|443|permitido|La NAT tiene Internet"
    "NAT-03|nat|servidores|ntp|123|permitido|NTP interno (fuente ^*)"
)

ip_de() {
    case "$1" in
        ti) echo "$IP_TI" ;;
        servidores) echo "$IP_SERVIDORES" ;;
        medicos) echo "$IP_MEDICOS" ;;
        visitantes) echo "$IP_VISITANTES" ;;
        dmz) echo "$IP_DMZ" ;;
        nat) echo "${IP_NAT:-$IP_DMZ}" ;;
        internet) echo "$INTERNET_TEST_IP" ;;
        local) echo "127.0.0.1" ;;
    esac
}
subred_de() {
    case "$1" in
        ti) echo "$SUBNET_TI" ;; servidores) echo "$SUBNET_SERVIDORES" ;;
        medicos) echo "$SUBNET_MEDICOS" ;; visitantes) echo "$SUBNET_VISITANTES" ;;
        dmz|nat) echo "$SUBNET_DMZ" ;;
    esac
}
etiqueta_proto() {   # tipo puerto
    case "$1" in
        tcp) echo "TCP/$2" ;; http) echo "${INTRANET_SCHEME^^}/$2" ;; ldap) echo "LDAP TCP/$2" ;;
        icmp) echo "ICMP" ;; ntp|ntp-cualquiera) echo "NTP UDP/123" ;;
        internet-tcp) echo "TCP/$2" ;; internet-https) echo "HTTPS/443" ;;
    esac
}

# ---------------------------------------------------------------- --lista
if [[ "$listar" == "si" ]]; then
    printf '%-7s %-11s %-24s %-14s %-10s %s\n' ID ORIGEN DESTINO PROTOCOLO ESPERADO DESCRIPCIÓN
    for p in "${PRUEBAS[@]}"; do
        IFS='|' read -r id o d tipo puerto esp nota <<<"$p"
        [[ -n "$origen" && "$o" != "$origen" ]] && continue
        ipd="$(ip_de "$d")"
        printf '%-7s %-11s %-24s %-14s %-10s %s\n' "$id" "$o" "$d (${ipd:-sin IP})" "$(etiqueta_proto "$tipo" "$puerto")" "$esp" "$nota"
    done
    exit 0
fi

# ---------------------------------------------------------------- sondas
# Cada sonda deja EST (estado corto) y OBT (texto para el CSV).
EST=""; OBT=""
T="$TIMEOUT_PRUEBA"

sonda_tcp() {
    local ip=$1 p=$2 err rc=0
    err="$(timeout "$T" bash -c "exec 3<>/dev/tcp/$ip/$p" 2>&1)" || rc=$?
    if ((rc == 0)); then EST=conecta; OBT="conectado"
    elif ((rc == 124)); then EST=timeout; OBT="timeout ${T}s (sin respuesta: probable SG/NACL/firewall)"
    elif grep -qi 'refused' <<<"$err"; then EST=rechazado; OBT="connection refused (el paquete llegó: no lo bloqueó la red; no hay servicio)"
    elif grep -qiE 'no route|unreachable' <<<"$err"; then EST=sin_ruta; OBT="sin ruta / red inalcanzable"
    else EST=error; OBT="error: ${err##*: }"
    fi
}

sonda_http() {
    local ip=$1 p=$2 code rc=0 url
    url="${INTRANET_SCHEME}://${ip}:${p}${INTRANET_PATH}"
    code="$(curl -k -sS -m "$T" -o /dev/null -w '%{http_code}' "$url" 2>/dev/null)" || rc=$?
    if [[ "$code" =~ ^(2|3) || "$code" == "401" ]]; then EST=conecta; OBT="HTTP $code"
    elif [[ "$code" =~ ^[45] ]]; then EST=conecta_error; OBT="HTTP $code (responde, pero con error)"
    elif ((rc == 28)); then EST=timeout; OBT="timeout ${T}s (sin respuesta: probable SG/NACL/firewall)"
    elif ((rc == 7)); then sonda_tcp "$ip" "$p"   # distinguir refused / sin ruta
    else EST=error; OBT="curl error $rc"
    fi
}

sonda_ldap() {
    local ip=$1 p=$2 rc=0 pw salida
    if ! command -v ldapsearch >/dev/null; then
        sonda_tcp "$ip" "$p"; OBT="(solo TCP: falta ldap-utils) $OBT"; return
    fi
    if [[ -n "${LDAP_USER:-}" && -n "${LDAP_PASS:-}" ]]; then
        pw="$(mktemp)"; chmod 600 "$pw"; printf '%s' "$LDAP_PASS" > "$pw"
        salida="$(timeout "$((T + 2))" ldapwhoami -x -o nettimeout="$T" -H "ldap://${ip}:${p}" \
            -D "uid=${LDAP_USER},${LDAP_PEOPLE}" -y "$pw" 2>&1)" || rc=$?
        rm -f "$pw"
        if ((rc == 0)); then EST=conecta; OBT="bind OK como uid=${LDAP_USER}"; return; fi
        if ((rc == 49)); then EST=conecta_error; OBT="LDAP responde pero credenciales inválidas (49)"; return; fi
    else
        salida="$(timeout "$((T + 2))" ldapsearch -x -LLL -o nettimeout="$T" -H "ldap://${ip}:${p}" \
            -b "$LDAP_BASE" -s base dn 2>&1)" || rc=$?
        if ((rc == 0)); then EST=conecta; OBT="búsqueda anónima OK en ${LDAP_BASE}"; return; fi
        if ((rc == 32)); then EST=conecta_error; OBT="LDAP responde pero no existe ${LDAP_BASE} (32)"; return; fi
    fi
    sonda_tcp "$ip" "$p"   # no contestó LDAP: clasificar el motivo a nivel TCP
    OBT="LDAP sin respuesta; $OBT"
    : "$salida"
}

sonda_icmp() {
    if ping -c 2 -W 2 "$1" >/dev/null 2>&1; then EST=conecta; OBT="responde al ping"
    else EST=timeout; OBT="sin respuesta al ping (2 intentos)"; fi
}

sonda_ntp() {   # la fuente <ip> debe estar seleccionada (^*) en chrony
    local ip=$1 linea marca reach
    if ! command -v chronyc >/dev/null; then EST=error; OBT="chrony no instalado (correr chrony-cliente.sh)"; return; fi
    linea="$({ chronyc -n sources 2>/dev/null || true; } | awk -v ip="$ip" '$2 == ip {print; exit}')"
    if [[ -z "$linea" ]]; then EST=error; OBT="${ip} no es fuente NTP de este equipo (correr chrony-cliente.sh)"; return; fi
    marca="${linea:0:2}"
    # Reach = registro octal de las últimas 8 consultas (0 = ninguna respuesta). No necesita root.
    reach="$(awk '{print $4}' <<<"$linea")"
    case "$marca" in
        '^*') EST=conecta; OBT="fuente ^* seleccionada (reach ${reach})" ;;
        '^+') EST=conecta_error; OBT="fuente ^+ aceptable pero no seleccionada (reach ${reach})" ;;
        *) if [[ "$reach" == "0" ]]; then EST=timeout; OBT="fuente ${marca} sin respuesta UDP 123 (reach 0: probable SG/NACL)"
           else EST=conecta_error; OBT="fuente ${marca} responde pero no seleccionada (reach ${reach})"; fi ;;
    esac
}

sonda_ntp_cualquiera() {
    local leap ref
    if ! command -v chronyc >/dev/null; then EST=error; OBT="chrony no instalado"; return; fi
    leap="$({ chronyc tracking 2>/dev/null || true; } | awk -F': ' '/^Leap status/ {print $2}')"
    ref="$({ chronyc -n tracking 2>/dev/null || true; } | awk -F': ' '/^Reference ID/ {print $2}')"
    if [[ "$leap" == "Normal" ]]; then EST=conecta; OBT="sincronizado; Reference ID ${ref}"
    else EST=timeout; OBT="no sincronizado (Leap status: ${leap:-?})"; fi
}

sonda_internet_https() {
    local code rc=0
    code="$(curl -sS -m "$((T + 3))" -o /dev/null -w '%{http_code}' "$INTERNET_TEST_URL" 2>/dev/null)" || rc=$?
    if [[ "$code" =~ ^[23] ]]; then EST=conecta; OBT="HTTP $code desde ${INTERNET_TEST_URL}"
    elif ((rc == 6)); then EST=sin_ruta; OBT="no resuelve el nombre (DNS) de ${INTERNET_TEST_URL}"
    elif ((rc == 28)); then EST=timeout; OBT="timeout (sin salida a Internet: ¿NAT/ruta 0.0.0.0/0?)"
    else EST=error; OBT="curl error $rc / HTTP ${code:-000}"; fi
}

# ---------------------------------------------------------------- ejecución
FECHA="$(date +%F)"
CSV="${FASE3_EVID_DIR:-$PWD}/resultados-${origen}-${FECHA}.csv"
[[ -f "$CSV" ]] || echo "fecha,origen,destino,protocolo_puerto,esperado,obtenido,resultado" > "$CSV"
csv_campo() { local s=${1//,/;}; printf '%s' "${s//$'\n'/ }"; }

printf '%sPruebas de la Fase 3 desde %s%s  (%s, variables: %s)\n' "$C_PASO" "$origen" "$C_0" "$(hostname)" "$FASE3_ENV_USADO"
sub="$(subred_de "$origen")"
read -r -a mis_ips <<<"$(hostname -I 2>/dev/null || true)"
if [[ -n "$sub" ]] && command -v python3 >/dev/null; then
    if ! python3 - "$sub" "${mis_ips[@]}" <<'PY'
import ipaddress, sys
red = ipaddress.ip_network(sys.argv[1], strict=False)
sys.exit(0 if any(ipaddress.ip_address(i) in red for i in sys.argv[2:] if ':' not in i) else 1)
PY
    then
        aviso "Ninguna IP de este equipo (${mis_ips[*]}) está en la subred de '$origen' ($sub): ¿origen correcto?"
    fi
fi
printf '\n%-7s %-24s %-14s %-10s %-6s %s\n' ID DESTINO PROTOCOLO ESPERADO RESULT OBTENIDO

n_pass=0; n_fail=0; n_omit=0; ejecutadas=0
for p in "${PRUEBAS[@]}"; do
    IFS='|' read -r id o d tipo puerto esp nota <<<"$p"
    [[ "$o" == "$origen" ]] || continue
    [[ -z "$solo" || "$id" == "$solo" ]] || continue
    ejecutadas=$((ejecutadas + 1))
    ipd="$(ip_de "$d")"
    destino="$d (${ipd:-sin IP})"
    proto="$(etiqueta_proto "$tipo" "$puerto")"
    if [[ -z "$ipd" ]]; then
        n_omit=$((n_omit + 1))
        printf '%-7s %-24s %-14s %-10s %s%-6s%s %s\n' "$id" "$destino" "$proto" "$esp" "$C_WARN" OMITIDA "$C_0" "IP de '$d' no definida en fase3.env (IP_${d^^})"
        continue
    fi
    case "$tipo" in
        tcp|internet-tcp) sonda_tcp "$ipd" "$puerto" ;;
        http) sonda_http "$ipd" "$puerto" ;;
        ldap) sonda_ldap "$ipd" "$puerto" ;;
        icmp) sonda_icmp "$ipd" ;;
        ntp) sonda_ntp "$ipd" ;;
        ntp-cualquiera) sonda_ntp_cualquiera ;;
        internet-https) sonda_internet_https ;;
    esac
    if [[ "$esp" == "permitido" ]]; then
        [[ "$EST" == "conecta" ]] && res=PASS || res=FAIL
    else
        [[ "$EST" == "timeout" || "$EST" == "sin_ruta" ]] && res=PASS || res=FAIL
    fi
    if [[ "$res" == "PASS" ]]; then n_pass=$((n_pass + 1)); color="$C_OK"; else n_fail=$((n_fail + 1)); color="$C_ERR"; fi
    printf '%-7s %-24s %-14s %-10s %s%-6s%s %s\n' "$id" "$destino" "$proto" "$esp" "$color" "$res" "$C_0" "$OBT"
    printf '%s,%s,%s,%s,%s,%s,%s\n' "$(date '+%F %T')" "$origen" "$(csv_campo "$destino")" "$(csv_campo "$proto")" \
        "$esp" "$(csv_campo "$OBT")" "$res" >> "$CSV"
done

((ejecutadas > 0)) || die "No hay pruebas para origen=${origen}${solo:+ con ID=${solo}} (ver: bash tests_fase3.sh --lista ${origen})"
printf '\nResumen %s: %s%d PASS%s, %s%d FAIL%s, %d OMITIDA(S)\n' "$origen" "$C_OK" "$n_pass" "$C_0" "$C_ERR" "$n_fail" "$C_0" "$n_omit"
printf 'CSV: %s\n' "$CSV"
if ((n_omit > 0)); then printf 'Las OMITIDAS no van al CSV: define sus IPs en fase3.env y repite con --solo <ID>.\n'; fi
((n_fail == 0))
