#!/bin/bash
# Fase 4 · F4 — Cliente SNMPv3 en TI para root: /root/.snmp/snmp.conf (0600) a partir de /etc/snmp-fase4/creds.
# Permite `sudo snmpwalk 10.0.0.46 system` sin credenciales en la línea de comandos.
# Reversión: sudo rm -f /root/.snmp/snmp.conf
set -euo pipefail
sudo bash -c '
  set -euo pipefail
  . /etc/snmp-fase4/creds
  install -d -m 700 /root/.snmp
  umask 077
  cat > /root/.snmp/snmp.conf <<EOF
defVersion 3
defSecurityName monitor
defSecurityLevel authPriv
defAuthType SHA
defPrivType AES
defAuthPassphrase $AUTH
defPrivPassphrase $PRIV
EOF
  stat -c "%A %U:%G %n" /root/.snmp/snmp.conf
'
echo "== prueba local"
# sysName.0 y sysUpTime.0 (Ubuntu no trae los MIB: se usan OID numéricos)
sudo snmpget -m '' -t 2 -r 1 127.0.0.1 .1.3.6.1.2.1.1.5.0 .1.3.6.1.2.1.1.3.0
