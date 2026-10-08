#!/usr/bin/env bash
# Instala vsftpd para ftp.hospital.redes.test con usuarios LDAP enjaulados.
# Requiere ftp/instalar-nslcd.sh (los usuarios LDAP deben verse con getent).
# Uso (en la VM, desde la raíz del repo): sudo bash ftp/instalar-vsftpd.sh
set -euo pipefail
cd "$(dirname "$0")/.."
source lab.env

echo "==> Instalando vsftpd"
DEBIAN_FRONTEND=noninteractive apt-get install -y -q vsftpd

echo "==> Directorios autorizados en /srv/ftp"
# /srv/ftp                  root  711  (no se puede listar qué usuarios hay)
# /srv/ftp/<u>              root  755  raíz del chroot, solo lectura
# /srv/ftp/<u>/LEEME.txt    root  644  archivo de prueba para descargar
# /srv/ftp/<u>/archivos     <u>   700  único lugar donde el usuario escribe
install -d -m 711 -o root -g root /srv/ftp
: > /etc/vsftpd.userlist
for u in $USERS; do
    getent passwd "$u" >/dev/null || { echo "ERROR: $u no existe (¿nslcd?)"; exit 1; }
    install -d -m 755 -o root -g root "/srv/ftp/$u"
    install -d -m 700 -o "$u" -g "$(id -g "$u")" "/srv/ftp/$u/archivos"
    printf 'Hospital Privado Castillejos\nDirectorio FTP de %s (%s)\nSuba sus archivos a la carpeta archivos/.\n' \
        "$(getent passwd "$u" | cut -d: -f5)" "$u" > "/srv/ftp/$u/LEEME.txt"
    chmod 644 "/srv/ftp/$u/LEEME.txt"
    echo "$u" >> /etc/vsftpd.userlist
done
chmod 644 /etc/vsftpd.userlist

echo "==> Configuración"
install -m 644 ftp/vsftpd.conf /etc/vsftpd.conf
touch /var/log/vsftpd.log && chmod 640 /var/log/vsftpd.log
systemctl enable vsftpd
systemctl restart vsftpd

ss -lntp | grep ':21 '
ls -l /srv/ftp/anthony
