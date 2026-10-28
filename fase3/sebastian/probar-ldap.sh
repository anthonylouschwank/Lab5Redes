#!/usr/bin/env bash
# Pruebas E5.5-E5.7: consultas, bind válido y rechazo de credenciales inválidas.
set -euo pipefail

LDAP_URI="${LDAP_URI:-ldap://127.0.0.1}"
LDAP_BASE_DN="${LDAP_BASE_DN:-dc=hospital,dc=redes,dc=test}"
LDAP_TEST_UID="${LDAP_TEST_UID:-ti01}"
LDAP_TEST_DN="uid=${LDAP_TEST_UID},ou=People,${LDAP_BASE_DN}"

if [[ -z "${LDAP_TEST_PASSWORD:-}" ]]; then
    [[ -t 0 ]] || { echo "ERROR: defina LDAP_TEST_PASSWORD o use una terminal." >&2; exit 1; }
    read -r -s -p "Contraseña de ${LDAP_TEST_UID}: " LDAP_TEST_PASSWORD
    echo
fi

umask 077
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "${WORK_DIR}"; unset LDAP_TEST_PASSWORD' EXIT
printf '%s' "${LDAP_TEST_PASSWORD}" > "${WORK_DIR}/valid.pw"
printf '%s' "CredencialInvalida-Fase3" > "${WORK_DIR}/invalid.pw"

echo "[1/4] Consulta de usuarios ficticios"
users_output="$(ldapsearch -x -LLL -H "${LDAP_URI}" -D "${LDAP_TEST_DN}" \
    -y "${WORK_DIR}/valid.pw" -b "ou=People,${LDAP_BASE_DN}" \
    '(objectClass=inetOrgPerson)' uid cn mail)"
printf '%s\n' "${users_output}"
user_count="$(grep -c '^uid: ' <<<"${users_output}")"
[[ "${user_count}" -eq 6 ]] || { echo "FAIL: se esperaban 6 usuarios y se encontraron ${user_count}." >&2; exit 1; }

echo "[2/4] Consulta de grupos y membresías"
groups_output="$(ldapsearch -x -LLL -H "${LDAP_URI}" -D "${LDAP_TEST_DN}" \
    -y "${WORK_DIR}/valid.pw" -b "ou=Groups,${LDAP_BASE_DN}" \
    '(objectClass=posixGroup)' cn memberUid)"
printf '%s\n' "${groups_output}"
group_count="$(grep -c '^cn: ' <<<"${groups_output}")"
[[ "${group_count}" -eq 3 ]] || { echo "FAIL: se esperaban 3 grupos y se encontraron ${group_count}." >&2; exit 1; }

echo "[3/4] Bind válido"
valid_output="$(ldapwhoami -x -H "${LDAP_URI}" -D "${LDAP_TEST_DN}" -y "${WORK_DIR}/valid.pw")"
printf '%s\n' "${valid_output}"
grep -Fqi "dn:${LDAP_TEST_DN}" <<<"${valid_output}" || {
    echo "FAIL: ldapwhoami no devolvió el DN esperado." >&2
    exit 1
}

echo "[4/4] Bind inválido (el rechazo es el resultado esperado)"
set +e
invalid_output="$(ldapwhoami -x -H "${LDAP_URI}" -D "${LDAP_TEST_DN}" \
    -y "${WORK_DIR}/invalid.pw" 2>&1)"
invalid_rc=$?
set -e
printf '%s\n' "${invalid_output}"
[[ "${invalid_rc}" -ne 0 ]] || { echo "FAIL: la contraseña inválida fue aceptada." >&2; exit 1; }
grep -Fq 'Invalid credentials (49)' <<<"${invalid_output}" || {
    echo "FAIL: el rechazo no devolvió Invalid credentials (49)." >&2
    exit 1
}

echo "PASS: consultas, bind válido y bind inválido se comportaron como se esperaba."

