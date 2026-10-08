#!/usr/bin/env bash
# Matriz de pruebas FTP (FTP-01 a FTP-08) más conexión de control vs. datos y logs.
# Uso (en la VM): bash tests/ftp.sh
set -uo pipefail
source "$(dirname "$0")/lib.sh"
source "${TESTS_DIR}/../secrets/credenciales.env"

FTPHOST="ftp.${DOMAIN}"
URL="ftp://${FTPHOST}"
TMPD="$(mktemp -d /tmp/ftp.XXXX)"; trap 'rm -rf "$TMPD"' EXIT
netrc() { printf 'machine %s login %s password %s\n' "$FTPHOST" "$1" "$2" > "${TMPD}/$3"; }
netrc anthony  "$PASS_anthony"         anthony
netrc anthony  "ContrasenaIncorrecta"  anthony-mala

ARCH="prueba-ftp-$(date +%H%M%S).txt"
printf 'Archivo de prueba FTP del Laboratorio 5\nGenerado: %s\n' "$(date)" > "${TMPD}/${ARCH}"

# ftpv: curl con el diálogo FTP visible (-v) y el comando PASS enmascarado
ftpv() { curl -sS -v "$@" 2>&1 | sed -E 's/^> PASS .*/> PASS ********/'; }
export -f ftpv
A="--netrc-file ${TMPD}/anthony"

prueba FTP-01 "Resolución de ${FTPHOST}" \
    "dig +noall +answer ${FTPHOST} A" \
    "grep -qE '^ftp\.${D_RE}\.\s+[0-9]+\s+IN\s+A\s+${IP_RE}$'"

prueba FTP-02 "Autenticación válida (anthony)" \
    "ftpv ${A} ${URL}/ -o /dev/null | grep -E '^[<>] (220|USER|331|PASS|230|PWD|257)'" \
    "grep -q '< 230 Login successful'"

prueba FTP-03 "Autenticación con contraseña incorrecta" \
    "ftpv --netrc-file ${TMPD}/anthony-mala ${URL}/ | grep -E '^[<>] (220|USER|331|PASS|530)|curl:'" \
    "grep -q '< 530 Login incorrect'"

prueba FTP-04 "Acceso anónimo" \
    "ftpv ${URL}/ | grep -E '^[<>] (220|USER|331|PASS|530)|curl:'" \
    "grep -q 'USER anonymous' \$SALIDA && grep -q '< 530' \$SALIDA"

prueba FTP-05 "Listado del directorio autorizado" \
    "ftpv ${A} ${URL}/ | grep -vE '^[*{}]|^> (USER|PASS)|^< (331|220)'" \
    "grep -q 'LEEME.txt' \$SALIDA && grep -q 'archivos' \$SALIDA"

prueba FTP-06 "Carga de archivo a archivos/" \
    "ftpv ${A} -T ${TMPD}/${ARCH} ${URL}/archivos/ | grep -E '^[<>] (EPSV|PASV|227|229|TYPE|STOR|150|226)'; echo; sudo ls -l /srv/ftp/anthony/archivos/${ARCH}; sudo sha256sum /srv/ftp/anthony/archivos/${ARCH}" \
    "grep -q '< 226' \$SALIDA && grep -q '${ARCH}' \$SALIDA"

prueba FTP-07 "Descarga del archivo sin alteraciones" \
    "ftpv ${A} -o ${TMPD}/descargado.txt ${URL}/archivos/${ARCH} | grep -E '^[<>] (RETR|150|226)'; echo; cd ${TMPD} && sha256sum ${ARCH} descargado.txt && cmp ${ARCH} descargado.txt && echo 'Archivos idénticos'" \
    "grep -q '< 226' \$SALIDA && grep -q 'Archivos idénticos' \$SALIDA"

prueba FTP-08 "Restricción de directorios (chroot y permisos)" \
    "echo '== CWD /etc dentro del FTP =='; ftpv ${A} -Q 'CWD /etc' ${URL}/ | grep -E '^[<>] (CWD|550)|curl:'; echo; echo '== CWD ../.. y PWD: sigue en la raíz del chroot =='; ftpv ${A} -Q 'CWD ../..' -Q 'PWD' ${URL}/ -o /dev/null | grep -E '^[<>] (CWD|250|PWD|257)'; echo; echo '== Permisos en el sistema de archivos =='; ls -ld /srv/ftp /srv/ftp/anthony; sudo ls -ld /srv/ftp/anthony/archivos; echo '\$ sudo -u isabella ls /srv/ftp/anthony/archivos'; sudo -u isabella ls /srv/ftp/anthony/archivos 2>&1" \
    "grep -q '< 550' \$SALIDA && grep -q '257 \"/\"' \$SALIDA && grep -q 'Permission denied' \$SALIDA"

prueba FTP-09 "Conexión de control (21) vs. conexión de datos (pasivo 40000-40100)" \
    "ftpv ${A} --disable-epsv ${URL}/LEEME.txt | grep -E '^\* (Connected|Connecting)|^[<>] (PASV|227|RETR|150|226)'" \
    "grep -q 'port 21' \$SALIDA && grep -qE 'Connecting to ${IP_RE} \(${IP_RE}\) port 40(0[0-9][0-9]|100)' \$SALIDA"

prueba FTP-10 "Log de vsftpd (logins, rechazos y transferencias)" \
    "sudo grep -E 'OK LOGIN|FAIL LOGIN|OK UPLOAD|OK DOWNLOAD' /var/log/vsftpd.log | tail -n 12" \
    "grep -q 'OK LOGIN' \$SALIDA && grep -q 'FAIL LOGIN' \$SALIDA && grep -q 'OK UPLOAD' \$SALIDA && grep -q 'OK DOWNLOAD' \$SALIDA"
