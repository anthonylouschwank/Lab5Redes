#!/usr/bin/env bash
# Instala y prepara OpenLDAP para Fase 3 sin reconstruir una base existente.
# Uso: sudo --preserve-env=LDAP_ADMIN_PASSWORD,LDAP_BASE_DN,LDAP_DOMAIN,LDAP_ORG_NAME,LDAP_URI \
#        bash fase3/sebastian/instalar-ldap.sh
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
    echo "ERROR: ejecute este script con sudo." >&2
    exit 1
fi

LDAP_DOMAIN="${LDAP_DOMAIN:-hospital.redes.test}"
LDAP_BASE_DN="${LDAP_BASE_DN:-dc=hospital,dc=redes,dc=test}"
LDAP_ORG_NAME="${LDAP_ORG_NAME:-Hospital Privado Castillejos}"
LDAP_URI="${LDAP_URI:-ldap://127.0.0.1}"
LDAP_ADMIN_DN="${LDAP_ADMIN_DN:-cn=admin,${LDAP_BASE_DN}}"
LDAP_FIRST_DC="${LDAP_BASE_DN#dc=}"
LDAP_FIRST_DC="${LDAP_FIRST_DC%%,*}"

if [[ -z "${LDAP_ADMIN_PASSWORD:-}" ]]; then
    if [[ ! -t 0 ]]; then
        echo "ERROR: defina LDAP_ADMIN_PASSWORD o ejecute desde una terminal para ingresarla." >&2
        exit 1
    fi
    read -r -s -p "Contraseña del administrador LDAP: " LDAP_ADMIN_PASSWORD
    echo
fi
if [[ -z "${LDAP_ADMIN_PASSWORD}" ]]; then
    echo "ERROR: la contraseña del administrador no puede estar vacía." >&2
    exit 1
fi

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "${WORK_DIR}"; unset LDAP_ADMIN_PASSWORD' EXIT
umask 077
ADMIN_PW_FILE="${WORK_DIR}/admin.pw"
printf '%s' "${LDAP_ADMIN_PASSWORD}" > "${ADMIN_PW_FILE}"

echo "==> Configuración solicitada"
echo "    URI:       ${LDAP_URI}"
echo "    Base DN:   ${LDAP_BASE_DN}"
echo "    Admin DN:  ${LDAP_ADMIN_DN}"

if ! dpkg-query -W -f='${Status}' slapd 2>/dev/null | grep -q 'install ok installed'; then
    echo "==> Primera instalación de slapd; precargando la base inicial"
    debconf-set-selections <<EOF
slapd slapd/no_configuration boolean false
slapd slapd/domain string ${LDAP_DOMAIN}
slapd shared/organization string ${LDAP_ORG_NAME}
slapd slapd/password1 password ${LDAP_ADMIN_PASSWORD}
slapd slapd/password2 password ${LDAP_ADMIN_PASSWORD}
slapd slapd/purge_database boolean false
slapd slapd/move_old_database boolean false
EOF
    apt-get update -q
    DEBIAN_FRONTEND=noninteractive apt-get install -y -q slapd ldap-utils
else
    echo "==> slapd ya está instalado; no se ejecutará dpkg-reconfigure"
    DEBIAN_FRONTEND=noninteractive apt-get install -y -q ldap-utils
fi

systemctl enable --now slapd

echo "==> Verificando que la base existente sea la esperada"
DB_DN="$(ldapsearch -Q -LLL -Y EXTERNAL -H ldapi:/// -b cn=config \
    '(&(objectClass=olcMdbConfig)(olcSuffix=*))' dn olcSuffix 2>/dev/null |
    awk -v wanted="${LDAP_BASE_DN}" '
        /^dn: / { dn=substr($0,5) }
        /^olcSuffix: / { suffix=substr($0,12); if (suffix==wanted) { print dn; exit } }
    ')"

if [[ -z "${DB_DN}" ]]; then
    echo "ERROR: slapd existe, pero no contiene la base ${LDAP_BASE_DN}." >&2
    echo "       Se detuvo para no borrar ni reconfigurar datos existentes." >&2
    echo "       Bases detectadas:" >&2
    ldapsearch -Q -LLL -Y EXTERNAL -H ldapi:/// -b cn=config \
        '(&(objectClass=olcDatabaseConfig)(olcSuffix=*))' olcSuffix 2>/dev/null >&2 || true
    exit 1
fi

if ! ldapwhoami -x -H "${LDAP_URI}" -D "${LDAP_ADMIN_DN}" -y "${ADMIN_PW_FILE}" >/dev/null; then
    echo "ERROR: no fue posible autenticar ${LDAP_ADMIN_DN}; compruebe la contraseña." >&2
    exit 1
fi

ldap_exists() {
    local dn="$1"
    ldapsearch -x -LLL -H "${LDAP_URI}" -D "${LDAP_ADMIN_DN}" -y "${ADMIN_PW_FILE}" \
        -b "${dn}" -s base '(objectClass=*)' dn >/dev/null 2>&1
}

ldap_add_file() {
    local file="$1"
    ldapadd -x -H "${LDAP_URI}" -D "${LDAP_ADMIN_DN}" -y "${ADMIN_PW_FILE}" -f "${file}"
}

ensure_base() {
    if ldap_exists "${LDAP_BASE_DN}"; then
        echo "    = Base existente: ${LDAP_BASE_DN}"
        return
    fi
    cat > "${WORK_DIR}/base.ldif" <<EOF
dn: ${LDAP_BASE_DN}
objectClass: top
objectClass: dcObject
objectClass: organization
o: ${LDAP_ORG_NAME}
dc: ${LDAP_FIRST_DC}
EOF
    ldap_add_file "${WORK_DIR}/base.ldif"
}

ensure_ou() {
    local ou="$1" description="$2" dn="ou=${ou},${LDAP_BASE_DN}"
    if ldap_exists "${dn}"; then
        echo "    = OU existente: ${dn}"
        return
    fi
    cat > "${WORK_DIR}/ou.ldif" <<EOF
dn: ${dn}
objectClass: top
objectClass: organizationalUnit
ou: ${ou}
description: ${description}
EOF
    ldap_add_file "${WORK_DIR}/ou.ldif"
}

ensure_group() {
    local name="$1" gid="$2" description="$3"
    shift 3
    local dn="cn=${name},ou=Groups,${LDAP_BASE_DN}"
    local members="" member
    for member in "$@"; do
        members+="memberUid: ${member}"$'\n'
    done

    if ! ldap_exists "${dn}"; then
        cat > "${WORK_DIR}/group.ldif" <<EOF
dn: ${dn}
objectClass: top
objectClass: posixGroup
cn: ${name}
gidNumber: ${gid}
description: ${description}
${members}
EOF
        ldap_add_file "${WORK_DIR}/group.ldif"
        return
    fi

    cat > "${WORK_DIR}/group.ldif" <<EOF
dn: ${dn}
changetype: modify
replace: gidNumber
gidNumber: ${gid}
-
replace: description
description: ${description}
-
replace: memberUid
${members}
EOF
    ldapmodify -x -H "${LDAP_URI}" -D "${LDAP_ADMIN_DN}" -y "${ADMIN_PW_FILE}" \
        -f "${WORK_DIR}/group.ldif" >/dev/null
    echo "    ~ Grupo reconciliado: ${dn}"
}

echo "==> Creando o reconciliando la estructura LDAP"
ensure_base
ensure_ou People "Usuarios ficticios del Hospital Privado Castillejos"
ensure_ou Groups "Grupos de autorización del hospital"
ensure_group medicos 5001 "Personal médico" medico01 medico02
ensure_group ti 5002 "Equipo de tecnología" ti01 ti02
ensure_group laboratorio 5003 "Personal de laboratorio" laboratorio01 laboratorio02

echo "==> Activando logs de operaciones para las evidencias"
cat > "${WORK_DIR}/loglevel.ldif" <<EOF
dn: cn=config
changetype: modify
replace: olcLogLevel
olcLogLevel: stats
EOF
ldapmodify -Q -Y EXTERNAL -H ldapi:/// -f "${WORK_DIR}/loglevel.ldif" >/dev/null

echo "==> Configurando el cliente LDAP local"
cat > "${WORK_DIR}/ldap.conf" <<EOF
BASE    ${LDAP_BASE_DN}
URI     ${LDAP_URI}
TLS_CACERT /etc/ssl/certs/ca-certificates.crt
EOF
install -m 644 -o root -g root "${WORK_DIR}/ldap.conf" /etc/ldap/ldap.conf

echo "==> Verificación final"
slaptest -u >/dev/null
ldapsearch -x -LLL -H "${LDAP_URI}" -D "${LDAP_ADMIN_DN}" -y "${ADMIN_PW_FILE}" \
    -b "ou=Groups,${LDAP_BASE_DN}" '(objectClass=posixGroup)' cn gidNumber memberUid
ss -ltn | awk 'NR == 1 || $4 ~ /:389$/'
echo "OK: OpenLDAP quedó activo sin reconfiguración destructiva."
echo "AVISO: restrinja TCP/389 con SG/UFW; este script no modifica el firewall ni SSH."

