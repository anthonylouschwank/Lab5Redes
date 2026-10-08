#!/usr/bin/env bash
# Instala Dovecot (IMAP + LMTP) con autenticación contra OpenLDAP.
# Requiere haber corrido antes mail/instalar-postfix.sh (certificado, vmail, Postfix).
# Uso (en la VM, desde la raíz del repo): sudo bash mail/instalar-dovecot.sh
set -euo pipefail
cd "$(dirname "$0")/.."
source lab.env

echo "==> Instalando Dovecot"
DEBIAN_FRONTEND=noninteractive apt-get install -y -q \
    dovecot-core dovecot-imapd dovecot-lmtpd dovecot-ldap

echo "==> Configuración"
install -m 644 -o root -g dovecot mail/dovecot/dovecot.conf /etc/dovecot/dovecot.conf
install -m 640 -o root -g dovecot mail/dovecot/dovecot-ldap.conf.ext /etc/dovecot/dovecot-ldap.conf.ext
doveconf -n >/dev/null

systemctl enable dovecot
systemctl restart dovecot

echo "==> Entregando correo pendiente en la cola de Postfix"
postqueue -f
sleep 2
mailq | tail -n 1

ss -lntp | grep -E ':(25|587|143) '
