#!/usr/bin/env bash
# Matriz de pruebas Web (WEB-01 a WEB-05) más autorización por grupo LDAP.
# Uso (en la VM): bash tests/web.sh
# WEB-05 detiene slapd unos segundos y lo vuelve a iniciar.
set -uo pipefail
source "$(dirname "$0")/lib.sh"
source "${TESTS_DIR}/../secrets/credenciales.env"

URL="http://www.${DOMAIN}"
ERRLOG="/var/log/apache2/hospital-error.log"

# Credenciales en archivos netrc temporales para que no queden en la evidencia
NETRC_DIR="$(mktemp -d /tmp/netrc.XXXX)"
trap 'rm -rf "$NETRC_DIR"; sudo systemctl start slapd' EXIT
netrc() { printf 'machine www.%s login %s password %s\n' "$DOMAIN" "$1" "$2" > "${NETRC_DIR}/$3"; }
netrc anthony  "$PASS_anthony"  anthony
netrc isabella "$PASS_isabella" isabella
netrc anthony  "ContrasenaIncorrecta" anthony-mala
netrc noexiste "cualquiera"     noexiste

CURL="curl -s -i --max-time 10"

prueba WEB-01 "Resolución de www.${DOMAIN}" \
    "dig +noall +answer www.${DOMAIN} A" \
    "grep -qE '^www\.${D_RE}\.\s+[0-9]+\s+IN\s+A\s+${IP_RE}$'"

prueba WEB-02 "Acceso a la página principal" \
    "${CURL} ${URL}/ | sed -n '1,12p;/<h1>/p;/Integrantes/p'" \
    "grep -q 'HTTP/1.1 200 OK' \$SALIDA && grep -q 'Hospital Privado Castillejos' \$SALIDA"

prueba WEB-03 "Intranet con usuario LDAP válido (anthony)" \
    "${CURL} --netrc-file ${NETRC_DIR}/anthony ${URL}/intranet/ | sed -n '1,10p;/<h2>Bienvenido/p;/<td>/p'" \
    "grep -q 'HTTP/1.1 200 OK' \$SALIDA && grep -q 'Bienvenido(a), Anthony Lou' \$SALIDA"

prueba WEB-03b "Intranet con otro usuario válido (isabella)" \
    "${CURL} --netrc-file ${NETRC_DIR}/isabella ${URL}/intranet/ | sed -n '1p;/<h2>Bienvenido/p'" \
    "grep -q 'HTTP/1.1 200 OK' \$SALIDA && grep -q 'Isabella Obando' \$SALIDA"

prueba WEB-03c "Panel de TI con miembro del grupo ti (anthony)" \
    "${CURL} --netrc-file ${NETRC_DIR}/anthony ${URL}/intranet/ti/ | sed -n '1p;/<h2>/p'" \
    "grep -q 'HTTP/1.1 200 OK'"

prueba WEB-03d "Panel de TI con usuario fuera del grupo ti (isabella)" \
    "${CURL} --netrc-file ${NETRC_DIR}/isabella ${URL}/intranet/ti/ | sed -n '1p'; sleep 1; sudo tail -n 2 ${ERRLOG}" \
    "grep -q 'HTTP/1.1 401 Unauthorized'"

prueba WEB-04 "Intranet con contraseña incorrecta" \
    "${CURL} --netrc-file ${NETRC_DIR}/anthony-mala ${URL}/intranet/ | sed -n '1p;/WWW-Authenticate/p'; sleep 1; sudo tail -n 1 ${ERRLOG}" \
    "grep -q 'HTTP/1.1 401 Unauthorized' \$SALIDA && grep -q 'Password Mismatch' \$SALIDA"

prueba WEB-04b "Intranet con usuario inexistente" \
    "${CURL} --netrc-file ${NETRC_DIR}/noexiste ${URL}/intranet/ | sed -n '1p'; sleep 1; sudo tail -n 1 ${ERRLOG}" \
    "grep -q 'HTTP/1.1 401 Unauthorized' \$SALIDA && grep -q 'noexiste' \$SALIDA"

prueba WEB-05 "Dependencia de LDAP: autenticación con slapd detenido" \
    "sudo systemctl stop slapd; systemctl is-active slapd; ${CURL} --netrc-file ${NETRC_DIR}/anthony ${URL}/intranet/ | sed -n '1p'; sleep 1; sudo tail -n 2 ${ERRLOG}; sudo systemctl start slapd; systemctl is-active slapd" \
    "grep -q 'HTTP/1.1 500' \$SALIDA && grep -qi \"can't contact ldap server\" \$SALIDA"

prueba WEB-06 "Log de acceso de Apache (códigos 200/401/500)" \
    "sudo tail -n 9 /var/log/apache2/hospital-access.log" \
    "grep -q '\" 200 ' \$SALIDA && grep -q '\" 401 ' \$SALIDA && grep -q '\" 500 ' \$SALIDA"
