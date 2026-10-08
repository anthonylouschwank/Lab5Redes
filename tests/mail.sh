#!/usr/bin/env bash
# Matriz de pruebas de correo (MAIL-01 a MAIL-07) más casos SMTP y logs.
# Uso (en la VM): bash tests/mail.sh
# Las contraseñas nunca aparecen en la evidencia: curl usa archivos netrc temporales
# y swaks las toma de variables de entorno y las oculta (--auth-hide-password).
set -uo pipefail
source "$(dirname "$0")/lib.sh"
source "${TESTS_DIR}/../secrets/credenciales.env"

MAILHOST="mail.${DOMAIN}"
CA="/etc/ssl/certs/${MAILHOST}.crt"     # certificado autofirmado del servidor
MAILLOG="/var/log/mail.log"
ASUNTO="Prueba MAIL-05 $(date '+%H:%M:%S')"

TMPD="$(mktemp -d /tmp/mail.XXXX)"; trap 'rm -rf "$TMPD"' EXIT
netrc() { printf 'machine %s login %s password %s\n' "$MAILHOST" "$1" "$2" > "${TMPD}/$3"; }
netrc anthony  "$PASS_anthony"  anthony
netrc isabella "$PASS_isabella" isabella
netrc anthony  "ContrasenaIncorrecta" anthony-mala
export NETRC_DIR="$TMPD" MAILHOST CA MAILLOG ASUNTO DOMAIN

# enviar <usuario> <destino> <asunto>: SMTP 587 + STARTTLS + AUTH, luego busca el ID en el log
enviar() {
    local u="$1" pass_var="PASS_$1" out id
    out="$(SWAKS_OPT_auth_password="${!pass_var}" swaks --server "$MAILHOST" --port 587 --tls \
        --auth LOGIN --auth-user "$u" --auth-hide-password \
        --from "${u}@${DOMAIN}" --to "$2" --header "Subject: $3" \
        --body "Mensaje de prueba del Laboratorio 5 enviado por ${u}." 2>&1)"
    echo "$out"
    id="$(grep -oP 'queued as \K[0-9A-F]+' <<<"$out")"
    sleep 2
    echo; echo "--- ${MAILLOG} (cola ${id}) ---"
    sudo grep -E "${id}|sasl_username=${u}" "$MAILLOG" | tail -n 6
}
export -f enviar
export PASS_anthony PASS_isabella

# leer <usuario> <asunto>: busca el mensaje por IMAP (143 + STARTTLS) y lo descarga
leer() {
    local base="imap://${MAILHOST}/INBOX" n
    local c=(curl -s --ssl-reqd --cacert "$CA" --netrc-file "${NETRC_DIR}/$1")
    echo "\$ SEARCH SUBJECT \"$2\""
    n="$("${c[@]}" "$base" -X "SEARCH SUBJECT \"$2\"" | tr -d '\r' | tee /dev/stderr | awk '{print $NF}')"
    echo "\$ FETCH mensaje ${n}"
    "${c[@]}" "${base};MAILINDEX=${n}" | tr -d '\r' | grep -E '^(From|To|Subject|Date|Message-Id):|^Mensaje'
}
export -f leer

prueba MAIL-01 "Resolución de mail.${DOMAIN} y registro MX" \
    "dig +noall +answer ${DOMAIN} MX; dig +noall +answer ${MAILHOST} A" \
    "grep -qE 'IN\s+MX\s+10\s+mail\.${D_RE}\.' \$SALIDA && grep -qE '^mail\.${D_RE}\.\s+[0-9]+\s+IN\s+A\s+${IP_RE}$' \$SALIDA"

prueba MAIL-02 "Servicios para Thunderbird: SMTP 587 y IMAP 143 con STARTTLS" \
    "echo '== SMTP submission 587 (EHLO después de STARTTLS) =='; printf 'EHLO cliente\r\nQUIT\r\n' | openssl s_client -quiet -starttls smtp -connect ${MAILHOST}:587 -CAfile ${CA} -verify_hostname ${MAILHOST} 2>&1 | tr -d '\r'; echo; echo '== IMAP 143 (STARTTLS) =='; printf 'a CAPABILITY\na LOGOUT\n' | openssl s_client -quiet -starttls imap -connect ${MAILHOST}:143 -CAfile ${CA} -verify_hostname ${MAILHOST} 2>&1 | tr -d '\r'" \
    "grep -q '250-AUTH PLAIN LOGIN' \$SALIDA && grep -q 'AUTH=PLAIN' \$SALIDA && grep -c 'verify return:1' \$SALIDA | grep -qx 2"

prueba MAIL-03 "IMAP: autenticación válida (anthony)" \
    "curl -s --ssl-reqd --cacert ${CA} --netrc-file ${TMPD}/anthony imap://${MAILHOST}/; sleep 1; sudo grep 'imap-login: Login: user=<anthony@' ${MAILLOG} | tail -n 1" \
    "grep -q 'INBOX' \$SALIDA && grep -q 'Login: user=<anthony@${D_RE}>' \$SALIDA"

prueba MAIL-04 "IMAP: contraseña incorrecta" \
    "curl -sS --ssl-reqd --cacert ${CA} --netrc-file ${TMPD}/anthony-mala imap://${MAILHOST}/; sleep 3; sudo grep -E 'auth failed|Disconnected \(auth failed' ${MAILLOG} | tail -n 2" \
    "grep -q 'Login denied' \$SALIDA && grep -q 'auth failed' \$SALIDA"

prueba MAIL-04b "SMTP: contraseña incorrecta en submission (587)" \
    "SWAKS_OPT_auth_password=ContrasenaIncorrecta swaks --server ${MAILHOST} --port 587 --tls --auth LOGIN --auth-user anthony --auth-hide-password --from anthony@${DOMAIN} --to isabella@${DOMAIN} 2>&1 | grep -E '535|AUTH'; sleep 1; sudo grep 'authentication failed' ${MAILLOG} | tail -n 1" \
    "grep -q '535 5.7.8' \$SALIDA"

prueba MAIL-05 "Envío interno isabella -> anthony (SMTP + entrega LMTP)" \
    "enviar isabella anthony@${DOMAIN} '${ASUNTO}'" \
    "grep -q 'queued as' \$SALIDA && grep -q 'status=sent' \$SALIDA && grep -q 'dovecot-lmtp' \$SALIDA"

prueba MAIL-05b "Respuesta anthony -> isabella (intercambio entre usuarios)" \
    "enviar anthony isabella@${DOMAIN} 'Re: ${ASUNTO}'" \
    "grep -q 'queued as' \$SALIDA && grep -q 'status=sent' \$SALIDA"

prueba MAIL-06 "Recepción por IMAP en el buzón de anthony" \
    "sudo ls -l /var/vmail/${DOMAIN}/anthony/Maildir/new | tail -n 3; echo; leer anthony '${ASUNTO}'" \
    "grep -q 'Subject: ${ASUNTO}' \$SALIDA && grep -q 'From: isabella@${D_RE}' \$SALIDA"

prueba MAIL-06b "Recepción por IMAP en el buzón de isabella" \
    "leer isabella 'Re: ${ASUNTO}'" \
    "grep -q 'Subject: Re: ${ASUNTO}' \$SALIDA"

prueba MAIL-07 "Destinatario inexistente" \
    "swaks --server ${MAILHOST} --from isabella@${DOMAIN} --to noexiste@${DOMAIN} 2>&1 | grep -E 'RCPT|550'; sleep 1; sudo grep 'noexiste@' ${MAILLOG} | tail -n 1" \
    "grep -q '550 5.1.1' \$SALIDA && grep -q 'User unknown' \$SALIDA"

prueba MAIL-08 "Logs de Postfix y Dovecot de las pruebas" \
    "sudo grep -E 'postfix/(submission/smtpd|smtpd|lmtp|qmgr)|dovecot: (imap-login|auth|lmtp)' ${MAILLOG} | grep -vE 'connect from|disconnect from' | tail -n 25" \
    "grep -q 'dovecot: imap-login: Login' \$SALIDA && grep -q 'postfix/lmtp' \$SALIDA && grep -q 'dovecot: lmtp' \$SALIDA"
