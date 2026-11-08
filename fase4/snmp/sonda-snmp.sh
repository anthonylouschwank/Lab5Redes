#!/bin/bash
# Fase 4 · F6 — Sonda SNMPv3 sin credenciales (paquete de descubrimiento de engineID, como net-snmp).
# Si el agente es alcanzable responde con un REPORT; si SG/NACL/ufw lo filtran -> timeout.
# Uso: bash sonda-snmp.sh <esperado: responde|bloqueado> <ip> [ip...]
esp=$1; shift
echo "# Sonda SNMP desde $(hostname) $(date -Is) (esperado: $esp)"
for ip in "$@"; do
  r=$(python3 - "$ip" <<'PY'
import socket, sys
pkt = bytes.fromhex("303a020103300f02024a69020300ffe3040104020103041030"
                    "0e0400020100020100040004000400301204000400a00c020237f0020100020100"
                    "3000")
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM); s.settimeout(3)
try:
    s.sendto(pkt, (sys.argv[1], 161)); d, _ = s.recvfrom(4096)
    print("responde (REPORT %d bytes)" % len(d))
except socket.timeout:
    print("bloqueado (timeout 3s)")
except OSError as e:
    print("bloqueado (%s)" % e)
PY
)
  case "$r" in responde*) o=responde ;; *) o=bloqueado ;; esac
  [[ "$o" == "$esp" ]] && res=PASS || res=FAIL
  echo "$(hostname),$ip,udp/161,$esp,$r,$res"
done
