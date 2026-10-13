#!/usr/bin/env bash
# Genera ldap/usuarios.ldif a partir de ldap/usuarios.csv y secrets/credenciales.env
# (contraseñas guardadas como hash SSHA) y lo carga en OpenLDAP.
# Uso (en la VM, desde la raíz del repo): sudo bash ldap/usuarios.sh
#   sudo bash ldap/usuarios.sh --cargar   # NO regenera: carga el usuarios.ldif del repo tal cual
#                                         # (mismos hashes = mismas contraseñas; solo pide LDAP_ADMIN_PASS)
#   Con LDAP_URI=ldap://localhost se carga en el slapd local aunque el DNS apunte a otro equipo.
set -euo pipefail
cd "$(dirname "$0")/.."
source lab.env
source secrets/credenciales.env

LDIF="ldap/usuarios.ldif"
URI="${LDAP_URI:-ldap://ldap.${DOMAIN}}"
PWFILE="$(mktemp)"; trap 'rm -f "$PWFILE"' EXIT
printf '%s' "$LDAP_ADMIN_PASS" > "$PWFILE"

if [ "${1:-}" != "--cargar" ]; then
echo "==> Generando ${LDIF}"
{
    echo "# Usuarios del grupo: una cuenta por integrante en ${PEOPLE_DN}"
    echo "# Generado por ldap/usuarios.sh — las contraseñas están como hash SSHA."
    tail -n +2 ldap/usuarios.csv | while IFS=, read -r uid given sn grupo gid uidnum title; do
        var="PASS_${uid}"
        hash="$(slappasswd -h '{SSHA}' -s "${!var}")"
        cat <<EOF

dn: uid=${uid},${PEOPLE_DN}
objectClass: inetOrgPerson
objectClass: posixAccount
objectClass: shadowAccount
uid: ${uid}
cn: ${given} ${sn}
givenName: ${given}
sn: ${sn}
displayName: ${given} ${sn}
title: ${title}
ou: ${grupo}
mail: ${uid}@${DOMAIN}
uidNumber: ${uidnum}
gidNumber: ${gid}
homeDirectory: /home/${uid}
loginShell: /bin/bash
userPassword: ${hash}
EOF
    done
} > "$LDIF"
fi

echo "==> Cargando usuarios en ${URI} (se omiten los que ya existen)"
ldapadd -c -x -H "$URI" -D "cn=admin,${BASE_DN}" -y "$PWFILE" -f "$LDIF" || true

ldapsearch -x -LLL -H "$URI" -b "$PEOPLE_DN" "(objectClass=inetOrgPerson)" uid cn mail
