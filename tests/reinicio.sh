#!/usr/bin/env bash
# INT-02: después de reiniciar la VM, los servicios arrancan solos y las pruebas básicas pasan.
# Uso (en la VM, DESPUÉS de "sudo reboot"): bash tests/reinicio.sh
set -uo pipefail
source "$(dirname "$0")/lib.sh"
source "${TESTS_DIR}/../secrets/credenciales.env"

SERVICIOS="named slapd apache2 postfix dovecot nslcd vsftpd"
TMPD="$(mktemp -d /tmp/rei.XXXX)"; trap 'rm -rf "$TMPD"' EXIT
for h in www mail ftp; do
    printf 'machine %s.%s login isabella password %s\n' "$h" "$DOMAIN" "$PASS_isabella" >> "${TMPD}/netrc"
done
printf '%s' "$PASS_isabella" > "${TMPD}/pw"

prueba INT-02 "Reinicio: servicios habilitados, activos y pruebas básicas" \
    "echo \"Último arranque: \$(uptime -s)   (uptime: \$(uptime -p))\"; echo
     printf '%-9s %-10s %s\n' SERVICIO HABILITADO ESTADO
     for s in ${SERVICIOS}; do printf '%-9s %-10s %s\n' \$s \$(systemctl is-enabled \$s 2>/dev/null) \$(systemctl is-active \$s); done
     echo; echo '== Red persistente =='; ip -4 -br addr show enp0s8; resolvectl dns enp0s8
     echo; echo '== Pruebas básicas después del reinicio =='
     echo -n 'DNS:  '; dig +short www.${DOMAIN} A
     echo -n 'LDAP: '; ldapwhoami -x -H ldap://ldap.${DOMAIN} -D uid=isabella,${PEOPLE_DN} -y ${TMPD}/pw
     echo -n 'Web:  '; curl -s -o /dev/null -w 'HTTP %{http_code}\n' --netrc-file ${TMPD}/netrc http://www.${DOMAIN}/intranet/
     echo -n 'IMAP: '; curl -s --ssl-reqd --cacert /etc/ssl/certs/mail.${DOMAIN}.crt --netrc-file ${TMPD}/netrc imap://mail.${DOMAIN}/ -o /dev/null -w 'login OK\n'
     echo -n 'FTP:  '; curl -s --netrc-file ${TMPD}/netrc ftp://ftp.${DOMAIN}/ -o /dev/null -w 'login %{response_code}\n'" \
    "[ \$(grep -cE ' enabled +active$' \$SALIDA) -eq 7 ] && grep -q '10.0.0.37/27' \$SALIDA && grep -q 'dn:uid=isabella' \$SALIDA && grep -q 'HTTP 200' \$SALIDA && grep -q 'login OK' \$SALIDA && grep -q 'login 226' \$SALIDA"
