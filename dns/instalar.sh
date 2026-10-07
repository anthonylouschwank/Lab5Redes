#!/usr/bin/env bash
# Instala y configura BIND9 como servidor autoritativo de hospital.redes.test.
# Uso (en la VM, desde la raíz del repo): sudo bash dns/instalar.sh
set -euo pipefail
cd "$(dirname "$0")/.."
source lab.env

echo "==> Instalando BIND9"
apt-get update -q
DEBIAN_FRONTEND=noninteractive apt-get install -y -q bind9 bind9-utils bind9-dnsutils

echo "==> Copiando configuración y zonas"
install -m 644 -o root -g bind dns/named.conf.options /etc/bind/named.conf.options
install -m 644 -o root -g bind dns/named.conf.local   /etc/bind/named.conf.local
install -d -m 755 -o root -g bind /etc/bind/zones
install -m 644 -o root -g bind dns/zones/db.hospital.redes.test /etc/bind/zones/
install -m 644 -o root -g bind dns/zones/db.10.0.0              /etc/bind/zones/

echo "==> Validando"
named-checkconf
named-checkzone "${DOMAIN}" /etc/bind/zones/db.hospital.redes.test
named-checkzone 0.0.10.in-addr.arpa /etc/bind/zones/db.10.0.0

echo "==> Iniciando servicio"
systemctl enable named
systemctl restart named
systemctl --no-pager --lines=0 status named

echo "==> Prueba rápida"
dig +short @127.0.0.1 "ns1.${DOMAIN}" A

echo "==> La VM usa su propio BIND9 como DNS"
install -m 600 dns/netplan/61-lab5-dns.yaml /etc/netplan/61-lab5-dns.yaml
netplan apply
sleep 2
resolvectl status enp0s8 | grep -E 'DNS Servers|DNS Domain'
dig +short "www.${DOMAIN}" A
