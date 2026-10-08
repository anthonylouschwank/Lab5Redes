#!/usr/bin/env bash
# Integra el sistema con OpenLDAP (nslcd + NSS + PAM) para que vsftpd autentique
# a los usuarios del directorio.
# Uso (en la VM, desde la raíz del repo): sudo bash ftp/instalar-nslcd.sh
set -euo pipefail
cd "$(dirname "$0")/.."
source lab.env

echo "==> Instalando nslcd, libnss-ldapd y libpam-ldapd"
debconf-set-selections <<EOF
nslcd nslcd/ldap-uris string ldap://ldap.${DOMAIN}
nslcd nslcd/ldap-base string ${BASE_DN}
nslcd nslcd/ldap-auth-type select none
libnss-ldapd libnss-ldapd/nsswitch multiselect passwd, group, shadow
libpam-ldapd libpam-ldapd/enable_shadow boolean true
EOF
DEBIAN_FRONTEND=noninteractive apt-get install -y -q nslcd libnss-ldapd libpam-ldapd

install -m 640 -o root -g nslcd ftp/nslcd.conf /etc/nslcd.conf
systemctl enable nslcd
systemctl restart nslcd

echo "==> SSH solo para el administrador local (lab)"
install -m 644 ftp/sshd-lab5.conf /etc/ssh/sshd_config.d/lab5.conf
sshd -t
systemctl reload ssh

echo "==> Verificación"
grep -E '^(passwd|group|shadow):' /etc/nsswitch.conf
for u in $USERS; do getent passwd "$u"; done
getent group medicos ti laboratorio
