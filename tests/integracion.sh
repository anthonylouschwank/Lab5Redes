#!/usr/bin/env bash
# Pruebas de integración INT-01, INT-03 e INT-04 (INT-02 está en tests/reinicio.sh).
# Uso (en la VM): bash tests/integracion.sh
set -uo pipefail
source "$(dirname "$0")/lib.sh"
source "${TESTS_DIR}/../secrets/credenciales.env"

TMPD="$(mktemp -d /tmp/int.XXXX)"; trap 'rm -rf "$TMPD"' EXIT
for h in www mail ftp; do
    printf 'machine %s.%s login anthony password %s\n' "$h" "$DOMAIN" "$PASS_anthony" >> "${TMPD}/netrc"
done
printf '%s' "$PASS_anthony" > "${TMPD}/pw"
CA="/etc/ssl/certs/mail.${DOMAIN}.crt"

prueba INT-01 "Uso exclusivo de nombres DNS (FQDN) en clientes y configuración" \
    "echo '== Acceso a cada servicio por su FQDN =='
     echo -n 'Web  (www):  '; curl -s -o /dev/null -w 'HTTP %{http_code} desde %{remote_ip}\n' --netrc-file ${TMPD}/netrc http://www.${DOMAIN}/intranet/
     echo -n 'LDAP (ldap): '; ldapwhoami -x -H ldap://ldap.${DOMAIN} -D uid=anthony,${PEOPLE_DN} -y ${TMPD}/pw
     echo -n 'IMAP (mail): '; curl -s --ssl-reqd --cacert ${CA} --netrc-file ${TMPD}/netrc imap://mail.${DOMAIN}/ -w 'login OK desde %{remote_ip}\n' -o /dev/null
     echo -n 'SMTP (mail): '; printf 'QUIT\r\n' | curl -s smtp://mail.${DOMAIN}:25 -X NOOP -w '%{response_code} desde %{remote_ip}\n' -o /dev/null
     echo -n 'FTP  (ftp):  '; curl -s --netrc-file ${TMPD}/netrc ftp://ftp.${DOMAIN}/ -o /dev/null -w 'login %{response_code} desde %{remote_ip}\n'
     echo; echo '== Los servicios se refieren entre sí por nombre (búsqueda de la IP 10.0.0.37) =='
     sudo grep -rn '10\.0\.0\.37' /etc/apache2/sites-enabled/ /etc/postfix/main.cf /etc/postfix/ldap-usuarios.cf /etc/dovecot/dovecot.conf /etc/dovecot/dovecot-ldap.conf.ext /etc/nslcd.conf /etc/ldap/ldap.conf /etc/vsftpd.conf || echo 'Ninguna configuración de servicio usa la IP directamente.'
     echo; sudo grep -hE '^(uri|uris|server_host|URI)\b|AuthLDAPURL' /etc/nslcd.conf /etc/dovecot/dovecot-ldap.conf.ext /etc/postfix/ldap-usuarios.cf /etc/ldap/ldap.conf /etc/apache2/sites-enabled/hospital.conf | sed 's/^ *//' | sort -u" \
    "grep -q 'HTTP 200' \$SALIDA && grep -q 'dn:uid=anthony' \$SALIDA && grep -q 'login OK' \$SALIDA && grep -q 'login 226' \$SALIDA && grep -q 'Ninguna configuración' \$SALIDA"

prueba INT-03 "Puertos en escucha (ss -lntup)" \
    "sudo ss -lntup | grep -E 'Netid|:(53|389|80|25|587|143|21) ' ; echo; echo 'Rango pasivo FTP configurado:'; grep -E '^pasv_(min|max)_port' /etc/vsftpd.conf" \
    "for p in 53 389 80 25 587 143 21; do grep -qE \":\$p\\s\" \$SALIDA || exit 1; done"

prueba INT-04 "Revisión de logs de cada servicio" \
    "ult() { sudo grep -E \"\$1\" \"\$2\" | tail -n \${3:-2}; }
     echo '== BIND9: consultas a la zona =='; sudo journalctl -u named --no-pager | grep 'query:' | grep '${DOMAIN}' | tail -n 3
     echo; echo '== OpenLDAP: bind aceptado (err=0) y rechazado (err=49) =='; for e in 0 49; do sudo journalctl -u slapd --no-pager | grep \"RESULT tag=97 err=\$e \" | tail -n 1; done
     echo; echo '== Apache: accesos 200/401/500 y motivo de los rechazos =='; for c in 200 401 500; do ult \"\\\" \$c \" /var/log/apache2/hospital-access.log 1; done; ult 'Password Mismatch|not found|contact LDAP' /var/log/apache2/hospital-error.log 3
     echo; echo '== Dovecot: login IMAP correcto y fallido =='; ult 'imap-login: Login' /var/log/mail.log 1; ult 'auth failed' /var/log/mail.log 1
     echo; echo '== Postfix: entrega y destinatario rechazado =='; ult 'postfix/lmtp.*status=sent' /var/log/mail.log 1; ult 'User unknown' /var/log/mail.log 1
     echo; echo '== vsftpd: logins, rechazos y transferencias =='; for e in 'OK LOGIN' 'FAIL LOGIN' 'OK UPLOAD' 'OK DOWNLOAD'; do ult \"\$e\" /var/log/vsftpd.log 1; done" \
    "grep -q 'query:' \$SALIDA && grep -q 'err=49' \$SALIDA && grep -q 'imap-login: Login' \$SALIDA && grep -q 'status=sent' \$SALIDA && grep -q 'OK LOGIN' \$SALIDA && grep -q 'FAIL LOGIN' \$SALIDA"
