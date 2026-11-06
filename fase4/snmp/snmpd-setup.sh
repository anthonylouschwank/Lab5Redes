#!/bin/bash
# Fase 4 · F4 — snmpd SNMPv3 authPriv (usuario monitor, SHA/AES), solo lectura, sin v1/v2c.
# Requiere AUTH y PRIV en el entorno (los inyecta distribuir-snmp.ps1 por stdin; nunca se imprimen).
# Reversión: sudo cp -a /etc/snmp/snmpd.conf.bak.fase4 /etc/snmp/snmpd.conf;
#            sudo systemctl disable --now snmpd; sudo ufw delete allow from 10.0.0.117 to any port 161 proto udp
set -euo pipefail
: "${AUTH:?falta AUTH}" "${PRIV:?falta PRIV}"
C=/etc/snmp/snmpd.conf
P=/var/lib/snmp/snmpd.conf
echo "== $(hostname)"

echo "-- 1. paquetes"
export DEBIAN_FRONTEND=noninteractive
sudo apt-get install -y -qq snmpd >/dev/null 2>&1
dpkg -l snmpd | awk '/^ii/{print "   "$2" "$3}'
[[ "$(hostname)" == "ip-10-0-0-117" ]] && { sudo apt-get install -y -qq snmp >/dev/null 2>&1; dpkg -l snmp | awk '/^ii/{print "   "$2" "$3}'; }

echo "-- 2. configuración"
[[ -e "$C.bak.fase4" ]] || sudo cp -a "$C" "$C.bak.fase4"
sudo tee "$C" >/dev/null <<'EOF'
# Fase 4 — SNMPv3 authPriv de solo lectura. Sin comunidades v1/v2c.
agentAddress udp:161
# Vista de solo lectura: system, interfaces, ifX, host-resources y UCD (carga, memoria, disco)
view hospital included .1.3.6.1.2.1.1
view hospital included .1.3.6.1.2.1.2
view hospital included .1.3.6.1.2.1.31
view hospital included .1.3.6.1.2.1.25
view hospital included .1.3.6.1.4.1.2021
rouser -s usm monitor priv -V hospital
sysLocation AWS us-east-1a - Hospital Privado Castillejos
sysContact TI Hospital Castillejos
disk / 10%
load 4 4 4
dontLogTCPWrappersConnects yes
EOF

echo "-- 3. usuario SNMPv3 (createUser con snmpd detenido)"
sudo systemctl stop snmpd
sudo touch "$P"
sudo sed -i -E '/^(usmUser|createUser) /d' "$P"
printf 'createUser monitor SHA "%s" AES "%s"\n' "$AUTH" "$PRIV" | sudo tee -a "$P" >/dev/null
sudo chmod 600 "$P"
sudo systemctl enable snmpd >/dev/null 2>&1
if ! sudo systemctl start snmpd || ! systemctl is-active --quiet snmpd; then
  sudo journalctl -u snmpd -n 15 --no-pager
  sudo cp -a "$C.bak.fase4" "$C"; sudo systemctl restart snmpd || true
  echo "   ERROR: snmpd no arrancó; se restauró el respaldo"; exit 1
fi
sleep 1
echo "   snmpd $(systemctl is-active snmpd)"
echo "   createUser pendiente en $P: $(sudo grep -c '^createUser' "$P") (0 = ya convertido a usmUser localizado)"
echo "   comunidades v1/v2c en $C: $(sudo grep -cE '^\s*(rocommunity|rwcommunity|com2sec)' "$C" || true)"
sudo ss -ulnp | grep ':161 ' | awk '{print "   "$1" "$5}'

echo "-- 4. ufw"
sudo ufw allow from 10.0.0.117 to any port 161 proto udp comment 'fase4: SNMP desde TI (monitoreo)' | sed 's/^/   /'
sudo ufw status | grep -E '161/udp|Status' | sed 's/^/   /'
