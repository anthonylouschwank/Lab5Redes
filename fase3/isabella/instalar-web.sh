#!/usr/bin/env bash
# Instala la intranet del Hospital Privado Castillejos (Fase 3): Apache + login LDAP por grupo.
# Idempotente: se puede repetir. Respalda el VirtualHost anterior y valida antes de recargar.
#
# Uso (en la EC2 Servidores, con el LDAP de Sebastián ya instalado):
#   sudo bash fase3/isabella/instalar-web.sh
#   sudo --preserve-env=LDAP_SERVICE_PASSWORD bash fase3/isabella/instalar-web.sh   (sin preguntar)
# La contraseña de uid=svc-intranet se pide con read -s (o por LDAP_SERVICE_PASSWORD) y se guarda
# SOLO en ${LDAP_BIND_SECRET} (root, 600). Si ese archivo ya existe y no se da una nueva, se conserva.
set -euo pipefail
shopt -u patsub_replacement 2>/dev/null || true

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
paso()  { echo; echo "==> $*"; }
ok()    { echo "    OK: $*"; }
aviso() { echo "    AVISO: $*"; }
falla() { echo; echo "ERROR: $*" >&2; echo "RESULTADO: FALLO" >&2; exit 1; }

[[ ${EUID} -eq 0 ]] || falla "ejecute con sudo."
if [[ -f "${DIR}/fase3.env" ]]; then
    source "${DIR}/fase3.env"
else
    aviso "no existe ${DIR}/fase3.env; se usan los valores de fase3.env.example."
    source "${DIR}/fase3.env.example"
fi

echo "Intranet: puerto ${INTRANET_PORT} · sitio ${INTRANET_SITE} · LDAP ${LDAP_URI} · base ${LDAP_BASE_DN}"
echo "Orígenes autorizados: ${INTRANET_ALLOW_CIDRS}"

# ---------------------------------------------------------------- 1. Paquetes
paso "1. Paquetes (apache2, ldap-utils)"
faltan=()
for p in apache2 ldap-utils; do dpkg -s "$p" >/dev/null 2>&1 || faltan+=("$p"); done
if (( ${#faltan[@]} )); then
    echo "    Instalando: ${faltan[*]}"
    timeout 120 apt-get update -q >/dev/null \
        || falla "apt-get update no respondió. ¿La EC2 tiene salida a Internet? (NAT, ruta 0.0.0.0/0, SG-Servidores salida 80/443)"
    DEBIAN_FRONTEND=noninteractive apt-get install -y -q "${faltan[@]}" >/dev/null
    ok "instalados"
else
    ok "ya estaban instalados"
fi

# ---------------------------------------------------------------- 2. Módulos
paso "2. Módulos de Apache: ldap, authnz_ldap, include"
a2enmod -q ldap authnz_ldap include
ok "habilitados"

# ---------------------------------------------------------------- 3. Contraseña de svc-intranet
paso "3. Cuenta de servicio ${LDAP_BIND_DN}"
install -d -m 700 -o root -g root "$(dirname "${LDAP_BIND_SECRET}")"
if [[ -n "${LDAP_SERVICE_PASSWORD:-}" ]]; then
    origen="variable LDAP_SERVICE_PASSWORD"
elif [[ -s "${LDAP_BIND_SECRET}" ]]; then
    origen="archivo existente (se conserva)"
elif [[ -t 0 ]]; then
    read -r -s -p "    Contraseña de svc-intranet (la generó Sebastián/Majo en esta instancia): " LDAP_SERVICE_PASSWORD
    echo
    origen="teclado"
else
    falla "defina LDAP_SERVICE_PASSWORD o ejecute desde una terminal."
fi
if [[ -n "${LDAP_SERVICE_PASSWORD:-}" ]]; then
    tmp="$(umask 077; mktemp)"
    printf '%s' "${LDAP_SERVICE_PASSWORD}" > "${tmp}"
    install -m 600 -o root -g root "${tmp}" "${LDAP_BIND_SECRET}"
    rm -f "${tmp}"
    unset LDAP_SERVICE_PASSWORD
fi
echo "    Origen de la contraseña: ${origen}. Archivo: ${LDAP_BIND_SECRET} ($(stat -c '%U:%G %a' "${LDAP_BIND_SECRET}"))"
if who="$(ldapwhoami -x -o nettimeout=5 -H "${LDAP_URI}" -D "${LDAP_BIND_DN}" -y "${LDAP_BIND_SECRET}" 2>&1)"; then
    ok "bind de la cuenta de servicio aceptado (${who})"
else
    falla "el LDAP rechazó el bind de svc-intranet: ${who}
       Revise que slapd esté activo (${LDAP_URI}) y que la contraseña sea la de esta instancia.
       Para cambiarla: sudo --preserve-env=LDAP_SERVICE_PASSWORD bash $0"
fi

# ---------------------------------------------------------------- 4. Sitio
paso "4. Contenido del sitio en ${INTRANET_DOCROOT}"
install -d -m 755 -o root -g www-data "${INTRANET_DOCROOT}"
cp -r "${DIR}/sitio/." "${INTRANET_DOCROOT}/"
chown -R root:www-data "${INTRANET_DOCROOT}"
find "${INTRANET_DOCROOT}" -type d -exec chmod 755 {} +
find "${INTRANET_DOCROOT}" -type f -exec chmod 644 {} +
ok "$(find "${INTRANET_DOCROOT}" -type f | wc -l) archivos publicados"

# ---------------------------------------------------------------- 5. VirtualHost
paso "5. VirtualHost /etc/apache2/sites-available/${INTRANET_SITE}.conf"
grupos=""
for g in ${LDAP_GRUPOS_INTRANET}; do
    grupos+="                Require ldap-group cn=${g},ou=Groups,${LDAP_BASE_DN}"$'\n'
done
grupos="${grupos%$'\n'}"
conf="$(<"${DIR}/apache/hospital-intranet.conf.plantilla")"
conf="${conf//@SITE@/${INTRANET_SITE}}"
conf="${conf//@PORT@/${INTRANET_PORT}}"
conf="${conf//@SERVERNAME@/${INTRANET_SERVERNAME}}"
conf="${conf//@DOCROOT@/${INTRANET_DOCROOT}}"
conf="${conf//@ALLOW_IPS@/${INTRANET_ALLOW_CIDRS}}"
conf="${conf//@LDAP_URI@/${LDAP_URI}}"
conf="${conf//@BASE_DN@/${LDAP_BASE_DN}}"
conf="${conf//@BIND_DN@/${LDAP_BIND_DN}}"
conf="${conf//@BIND_SECRET@/${LDAP_BIND_SECRET}}"
conf="${conf//@GRUPO_TI@/${LDAP_GRUPO_TI}}"
conf="${conf//@REQUIRE_GRUPOS@/${grupos}}"
[[ "${conf}" != *"@"[A-Z_]*"@"* ]] || falla "quedó un marcador sin reemplazar en la plantilla."

destino="/etc/apache2/sites-available/${INTRANET_SITE}.conf"
respaldo=""
if [[ -f "${destino}" ]] && ! diff -q <(printf '%s\n' "${conf}") "${destino}" >/dev/null; then
    respaldo="${destino}.bak-$(date +%Y%m%d-%H%M%S)"
    cp -a "${destino}" "${respaldo}"
    echo "    Respaldo del anterior: ${respaldo}"
fi
printf '%s\n' "${conf}" > "${destino}"
chmod 644 "${destino}"
a2ensite -q "${INTRANET_SITE}" >/dev/null
if a2query -q -s 000-default 2>/dev/null; then
    a2dissite -q 000-default >/dev/null
    echo "    Sitio 000-default deshabilitado (la intranet atiende las peticiones por IP)."
fi
otros="$(a2query -s 2>/dev/null | awk '{print $1}' | grep -vx "${INTRANET_SITE}" || true)"
[[ -z "${otros}" ]] || aviso "hay otros sitios habilitados: ${otros//$'\n'/ }. Si atienden el mismo puerto, pueden tapar la intranet."
ok "sitio ${INTRANET_SITE} habilitado"

# ---------------------------------------------------------------- 6. Validar y aplicar
paso "6. Validación (apache2ctl configtest) antes de recargar"
if ! salida="$(apache2ctl configtest 2>&1)"; then
    echo "${salida}"
    if [[ -n "${respaldo}" ]]; then cp -a "${respaldo}" "${destino}"; echo "    Se restauró ${respaldo}."; fi
    falla "la configuración de Apache no es válida; no se recargó nada."
fi
ok "${salida##*$'\n'}"
systemctl enable -q apache2
if systemctl is-active -q apache2; then systemctl reload apache2; else systemctl start apache2; fi
ok "apache2 $(systemctl is-active apache2)"

# ---------------------------------------------------------------- 7. Verificación local
paso "7. Verificación en esta instancia"
sleep 1
ss -lntp | grep -q ":${INTRANET_PORT} " || falla "Apache no escucha en el puerto ${INTRANET_PORT}."
ok "escucha en TCP ${INTRANET_PORT}"
portal="$(curl -s -o /dev/null -w '%{http_code}' -m 5 "http://127.0.0.1:${INTRANET_PORT}/")"
intra="$(curl -s -o /dev/null -w '%{http_code}' -m 5 "http://127.0.0.1:${INTRANET_PORT}/intranet/")"
echo "    Portal sin login: HTTP ${portal} (esperado 200) · /intranet/ sin credenciales: HTTP ${intra} (esperado 401)"
[[ "${portal}" == 200 && "${intra}" == 401 ]] || falla "las respuestas no son las esperadas. Revise /var/log/apache2/${INTRANET_SITE}-error.log"

echo
echo "Siguiente: bash ${DIR}/probar-web.sh (con un usuario ficticio de Sebastián)."
echo "RESULTADO: OK"
