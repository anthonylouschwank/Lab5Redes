#!/usr/bin/env bash
# Carga solo las entradas que aún no existen. No cambia contraseñas al reejecutarse.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LDIF_FILE="${1:-${SCRIPT_DIR}/usuarios.ldif}"
LDAP_URI="${LDAP_URI:-ldap://127.0.0.1}"
LDAP_BASE_DN="${LDAP_BASE_DN:-dc=hospital,dc=redes,dc=test}"
LDAP_ADMIN_DN="${LDAP_ADMIN_DN:-cn=admin,${LDAP_BASE_DN}}"

[[ -r "${LDIF_FILE}" ]] || {
    echo "ERROR: no existe ${LDIF_FILE}; ejecute generar-usuarios.sh primero." >&2
    exit 1
}

if [[ -z "${LDAP_ADMIN_PASSWORD:-}" ]]; then
    [[ -t 0 ]] || { echo "ERROR: defina LDAP_ADMIN_PASSWORD o use una terminal." >&2; exit 1; }
    read -r -s -p "Contraseña de ${LDAP_ADMIN_DN}: " LDAP_ADMIN_PASSWORD
    echo
fi

umask 077
PW_FILE="$(mktemp)"
trap 'rm -f "${PW_FILE}"; unset LDAP_ADMIN_PASSWORD' EXIT
printf '%s' "${LDAP_ADMIN_PASSWORD}" > "${PW_FILE}"

if ! ldapwhoami -x -H "${LDAP_URI}" -D "${LDAP_ADMIN_DN}" -y "${PW_FILE}" >/dev/null; then
    echo "ERROR: autenticación administrativa fallida." >&2
    exit 1
fi

added=0
skipped=0
while IFS= read -r -d '' entry || [[ -n "${entry}" ]]; do
    [[ "${entry}" == dn:* ]] || continue
    first_line="${entry%%$'\n'*}"
    dn="${first_line#dn: }"
    if ldapsearch -x -LLL -H "${LDAP_URI}" -D "${LDAP_ADMIN_DN}" -y "${PW_FILE}" \
        -b "${dn}" -s base '(objectClass=*)' dn >/dev/null 2>&1; then
        echo "    = Ya existe: ${dn}"
        ((skipped += 1))
        continue
    fi
    printf '%s\n\n' "${entry}" |
        ldapadd -x -H "${LDAP_URI}" -D "${LDAP_ADMIN_DN}" -y "${PW_FILE}" >/dev/null
    echo "    + Creado: ${dn}"
    ((added += 1))
done < <(awk 'BEGIN { RS=""; ORS="\0" } /^dn: / { print }' "${LDIF_FILE}")

echo "OK: ${added} entradas creadas; ${skipped} ya existían."
ldapsearch -x -LLL -H "${LDAP_URI}" -D "${LDAP_ADMIN_DN}" -y "${PW_FILE}" \
    -b "ou=People,${LDAP_BASE_DN}" '(objectClass=inetOrgPerson)' uid cn mail

