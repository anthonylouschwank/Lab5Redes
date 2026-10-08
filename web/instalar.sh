#!/usr/bin/env bash
# Instala Apache y publica el sitio en http://www.hospital.redes.test
# Uso (en la VM, desde la raíz del repo): sudo bash web/instalar.sh
set -euo pipefail
cd "$(dirname "$0")/.."
source lab.env

echo "==> Instalando Apache"
DEBIAN_FRONTEND=noninteractive apt-get install -y -q apache2

echo "==> Módulos: LDAP (autenticación) e include (páginas .shtml)"
a2enmod -q ldap authnz_ldap include

echo "==> Publicando sitio"
rm -rf /var/www/hospital
cp -r web/sitio /var/www/hospital
chown -R root:www-data /var/www/hospital
find /var/www/hospital -type d -exec chmod 755 {} +
find /var/www/hospital -type f -exec chmod 644 {} +

echo "ServerName www.${DOMAIN}" > /etc/apache2/conf-available/servername.conf
a2enconf -q servername
install -m 644 web/apache/hospital.conf /etc/apache2/sites-available/hospital.conf
a2dissite -q 000-default || true
a2ensite -q hospital

apache2ctl configtest
systemctl enable apache2
systemctl reload-or-restart apache2
curl -s -o /dev/null -w "GET http://www.${DOMAIN}/ -> %{http_code}\n" "http://www.${DOMAIN}/"
