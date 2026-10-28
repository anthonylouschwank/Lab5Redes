#!/usr/bin/env bash
# Genera usuarios.ldif con hashes SSHA en la VM. El resultado está ignorado por Git.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CSV_FILE="${LDAP_USERS_CSV:-${SCRIPT_DIR}/usuarios-ficticios.csv}"
OUTPUT_FILE="${1:-${SCRIPT_DIR}/usuarios.ldif}"
LDAP_DOMAIN="${LDAP_DOMAIN:-hospital.redes.test}"
LDAP_BASE_DN="${LDAP_BASE_DN:-dc=hospital,dc=redes,dc=test}"

command -v slappasswd >/dev/null || {
    echo "ERROR: falta slappasswd. Ejecute primero instalar-ldap.sh." >&2
    exit 1
}
[[ -r "${CSV_FILE}" ]] || { echo "ERROR: no se puede leer ${CSV_FILE}." >&2; exit 1; }

read_secret() {
    local variable="$1" prompt="$2"
    if [[ -z "${!variable:-}" ]]; then
        [[ -t 0 ]] || { echo "ERROR: defina ${variable} o use una terminal." >&2; exit 1; }
        read -r -s -p "${prompt}: " "${variable}"
        echo
    fi
    [[ -n "${!variable}" ]] || { echo "ERROR: ${variable} no puede estar vacía." >&2; exit 1; }
}

read_secret LDAP_DEMO_PASSWORD "Contraseña de los usuarios ficticios"
read_secret LDAP_SERVICE_PASSWORD "Contraseña de uid=svc-intranet"

umask 077
TEMP_FILE="$(mktemp)"
trap 'rm -f "${TEMP_FILE}"; unset LDAP_DEMO_PASSWORD LDAP_SERVICE_PASSWORD' EXIT

{
    echo "# GENERADO EN LA VM: no versionar. Usuarios ficticios de Fase 3."
    tail -n +2 "${CSV_FILE}" |
    while IFS=, read -r uid given sn group gid uid_number title; do
        [[ -n "${uid}" ]] || continue
        hash="$(slappasswd -h '{SSHA}' -s "${LDAP_DEMO_PASSWORD}")"
        cat <<EOF

dn: uid=${uid},ou=People,${LDAP_BASE_DN}
objectClass: top
objectClass: inetOrgPerson
objectClass: posixAccount
uid: ${uid}
cn: ${given} ${sn}
givenName: ${given}
sn: ${sn}
displayName: ${given} ${sn}
title: ${title}
ou: ${group}
mail: ${uid}@${LDAP_DOMAIN}
uidNumber: ${uid_number}
gidNumber: ${gid}
homeDirectory: /home/${uid}
loginShell: /usr/sbin/nologin
userPassword: ${hash}
EOF
    done

    service_hash="$(slappasswd -h '{SSHA}' -s "${LDAP_SERVICE_PASSWORD}")"
    cat <<EOF

dn: uid=svc-intranet,ou=People,${LDAP_BASE_DN}
objectClass: top
objectClass: account
objectClass: simpleSecurityObject
uid: svc-intranet
description: Cuenta de lectura para autenticación de la intranet Apache
userPassword: ${service_hash}
EOF
} > "${TEMP_FILE}"

install -m 600 "${TEMP_FILE}" "${OUTPUT_FILE}"
echo "OK: se generó ${OUTPUT_FILE} con permisos 600."
echo "No lo agregue a Git; debe generarse nuevamente en la instancia de destino."

