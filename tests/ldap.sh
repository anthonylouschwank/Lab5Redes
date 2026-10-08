#!/usr/bin/env bash
# Matriz de pruebas LDAP (LDAP-01 a LDAP-04) más grupos y usuario inexistente.
# Uso (en la VM): bash tests/ldap.sh
set -uo pipefail
source "$(dirname "$0")/lib.sh"
source "${TESTS_DIR}/../secrets/credenciales.env"

URI="ldap://ldap.${DOMAIN}"
# La contraseña válida se pasa en un archivo temporal para que no quede en la evidencia
PW_ANTHONY="$(mktemp /tmp/pw_anthony.XXXX)"; trap 'rm -f "$PW_ANTHONY"' EXIT
printf '%s' "$PASS_anthony" > "$PW_ANTHONY"

prueba LDAP-01 "Consulta de usuarios en ou=People" \
    "ldapsearch -x -LLL -H ${URI} -b ${PEOPLE_DN} '(objectClass=inetOrgPerson)' uid cn" \
    "grep -c '^uid: ' | grep -qx 6"

prueba LDAP-02 "Bind con usuario y contraseña correctos" \
    "ldapwhoami -x -H ${URI} -D uid=anthony,${PEOPLE_DN} -y ${PW_ANTHONY}" \
    "grep -qx 'dn:uid=anthony,${PEOPLE_DN}'"

prueba LDAP-03 "Bind con contraseña incorrecta" \
    "ldapwhoami -x -H ${URI} -D uid=anthony,${PEOPLE_DN} -w ContrasenaIncorrecta" \
    "grep -q 'Invalid credentials (49)'"

prueba LDAP-03b "Bind con usuario inexistente" \
    "ldapwhoami -x -H ${URI} -D uid=noexiste,${PEOPLE_DN} -w cualquiera" \
    "grep -q 'Invalid credentials (49)'"

prueba LDAP-04 "Atributos uid, cn, sn y mail de un usuario" \
    "ldapsearch -x -LLL -H ${URI} -b ${PEOPLE_DN} '(uid=isabella)' uid cn sn mail" \
    "grep -q '^uid: isabella' \$SALIDA && grep -q '^cn: Isabella Obando' \$SALIDA && grep -q '^sn: Obando' \$SALIDA && grep -q '^mail: isabella@${D_RE}' \$SALIDA"

prueba LDAP-05 "Grupos por rol y sus miembros" \
    "ldapsearch -x -LLL -H ${URI} -b ${GROUPS_DN} '(objectClass=posixGroup)' cn memberUid" \
    "grep -c '^memberUid: ' | grep -qx 6"

prueba LDAP-06 "Registro de binds en el log de slapd" \
    "sudo journalctl -u slapd --since '-10 min' --no-pager | grep -E 'BIND dn=\"uid=(anthony|noexiste)|RESULT tag=97 err=(0|49)' | tail -n 12" \
    "grep -q 'err=49' \$SALIDA && grep -q 'err=0' \$SALIDA"
