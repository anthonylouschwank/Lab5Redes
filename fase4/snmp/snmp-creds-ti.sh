#!/bin/bash
# Fase 4 · F4 — Genera (una sola vez) las credenciales SNMPv3 en TI.
# /etc/snmp-fase4/creds (0600 root): AUTH=<hex32> PRIV=<hex32>. Nunca se imprimen.
# Reversión: sudo rm -rf /etc/snmp-fase4
set -euo pipefail
sudo install -d -m 700 -o root -g root /etc/snmp-fase4
if sudo test -s /etc/snmp-fase4/creds; then
  echo "credenciales existentes conservadas"
else
  sudo sh -c 'umask 077; printf "AUTH=%s\nPRIV=%s\n" "$(openssl rand -hex 16)" "$(openssl rand -hex 16)" > /etc/snmp-fase4/creds'
  echo "credenciales nuevas generadas"
fi
sudo stat -c '%A %U:%G %s bytes %n' /etc/snmp-fase4/creds
