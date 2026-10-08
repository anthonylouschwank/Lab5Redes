#!/usr/bin/env bash
# Instala Postfix para hospital.redes.test con buzones validados contra OpenLDAP.
# Uso (en la VM, desde la raíz del repo): sudo bash mail/instalar-postfix.sh
set -euo pipefail
cd "$(dirname "$0")/.."
source lab.env

MAILHOST="mail.${DOMAIN}"
CRT="/etc/ssl/certs/${MAILHOST}.crt"
KEY="/etc/ssl/private/${MAILHOST}.key"

echo "==> Instalando Postfix (con soporte LDAP)"
debconf-set-selections <<EOF
postfix postfix/main_mailer_type select Internet Site
postfix postfix/mailname string ${MAILHOST}
EOF
DEBIAN_FRONTEND=noninteractive apt-get install -y -q postfix postfix-ldap swaks

echo "==> Certificado TLS autofirmado para ${MAILHOST}"
if [ ! -f "$CRT" ]; then
    openssl req -x509 -newkey rsa:2048 -nodes -days 365 \
        -subj "/O=${ORG_NAME}/CN=${MAILHOST}" \
        -addext "subjectAltName=DNS:${MAILHOST}" \
        -keyout "$KEY" -out "$CRT"
    chmod 600 "$KEY"
fi

echo "==> Buzones virtuales: usuario vmail (5000) y /var/vmail"
getent group vmail  >/dev/null || groupadd -g 5000 vmail
getent passwd vmail >/dev/null || useradd -u 5000 -g vmail -d /var/vmail -M -s /usr/sbin/nologin vmail
install -d -m 770 -o vmail -g vmail /var/vmail

echo "==> Configuración"
echo "${MAILHOST}" > /etc/mailname
install -m 644 mail/postfix/main.cf          /etc/postfix/main.cf
install -m 644 mail/postfix/ldap-usuarios.cf /etc/postfix/ldap-usuarios.cf
install -m 644 mail/postfix/virtual          /etc/postfix/virtual
postmap /etc/postfix/virtual
newaliases

# Puerto 587 (submission): envío de los clientes, exige STARTTLS y autenticación
postconf -M "submission/inet=submission inet n - y - - smtpd"
postconf -P "submission/inet/syslog_name=postfix/submission" \
            "submission/inet/smtpd_tls_security_level=encrypt" \
            "submission/inet/smtpd_sasl_auth_enable=yes" \
            "submission/inet/smtpd_tls_auth_only=yes" \
            "submission/inet/smtpd_client_restrictions=permit_sasl_authenticated,reject" \
            "submission/inet/smtpd_relay_restrictions=permit_sasl_authenticated,reject"

postfix check
systemctl enable postfix
systemctl restart postfix

echo "==> Consulta LDAP desde Postfix"
postmap -q "anthony@${DOMAIN}" "ldap:/etc/postfix/ldap-usuarios.cf" || echo "(sin resultado)"
postmap -q "noexiste@${DOMAIN}" "ldap:/etc/postfix/ldap-usuarios.cf" || echo "noexiste@${DOMAIN}: no existe en LDAP"
