#!/usr/bin/env bash
# Instala OpenLDAP con base dc=hospital,dc=redes,dc=test y carga OUs y grupos.
# Uso (en la VM, desde la raíz del repo): sudo bash ldap/instalar.sh
# ATENCIÓN: reconfigura slapd desde cero (borra el directorio si ya existía).
set -euo pipefail
cd "$(dirname "$0")/.."
source lab.env
source secrets/credenciales.env

ADMIN_DN="cn=admin,${BASE_DN}"
PWFILE="$(mktemp)"; trap 'rm -f "$PWFILE"' EXIT
printf '%s' "$LDAP_ADMIN_PASS" > "$PWFILE"

# slapd borra la contraseña de debconf tras usarla: se precarga antes de cada uso
preconfigurar() {
    debconf-set-selections <<EOF
slapd slapd/no_configuration boolean false
slapd slapd/domain string ${DOMAIN}
slapd shared/organization string ${ORG_NAME}
slapd slapd/password1 password ${LDAP_ADMIN_PASS}
slapd slapd/password2 password ${LDAP_ADMIN_PASS}
slapd slapd/purge_database boolean true
slapd slapd/move_old_database boolean true
EOF
}

echo "==> Instalando slapd (dominio ${DOMAIN})"
preconfigurar
if dpkg -s slapd >/dev/null 2>&1; then
    DEBIAN_FRONTEND=noninteractive dpkg-reconfigure -f noninteractive slapd
else
    DEBIAN_FRONTEND=noninteractive apt-get install -y -q slapd ldap-utils
fi

echo "==> Cliente LDAP por nombre DNS"
cat > /etc/ldap/ldap.conf <<EOF
BASE    ${BASE_DN}
URI     ldap://ldap.${DOMAIN}
TLS_CACERT /etc/ssl/certs/ca-certificates.crt
EOF

echo "==> Ajustes de cn=config (logs e índices)"
ldapmodify -Q -c -Y EXTERNAL -H ldapi:/// -f ldap/config.ldif || true

echo "==> Cargando OUs y grupos"
ldapadd -x -H "ldap://ldap.${DOMAIN}" -D "$ADMIN_DN" -y "$PWFILE" -f ldap/base.ldif
ldapadd -x -H "ldap://ldap.${DOMAIN}" -D "$ADMIN_DN" -y "$PWFILE" -f ldap/grupos.ldif

systemctl enable slapd
systemctl --no-pager --lines=0 status slapd
ldapsearch -x -LLL -b "$BASE_DN" "(|(objectClass=organizationalUnit)(objectClass=posixGroup))" dn
