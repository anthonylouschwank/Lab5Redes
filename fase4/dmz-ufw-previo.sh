#!/bin/bash
# Fase 4 · F5 — Reglas ufw de la DMZ creadas ANTES de hardening.sh (ufw aún inactivo), para que al
# activarse no se corten la web ni la VPN. hardening.sh no hace `ufw reset`: las conserva.
#   Entrada:  80/tcp y 443/tcp (Internet), 51820/udp (WireGuard). 161/udp desde 10.0.0.117 ya existe (D19).
#             22/tcp desde la subred TI lo agrega hardening.sh (rol cliente).
#   Reenvío:  reglas `route` por peer equivalentes a la cadena WG-FWD (segunda capa si WG-FWD faltara).
# Reversión: sudo ufw delete <regla>  (las reglas llevan el comentario "fase4:")
set -euo pipefail
echo "== ufw: $(sudo ufw status | head -1)"
a() { sudo ufw "$@" | sed 's/^/   /'; }
a allow 80/tcp  comment 'fase4: web publica (ACME + 301 a https)'
a allow 443/tcp comment 'fase4: web publica HTTPS'
a allow 51820/udp comment 'fase4: WireGuard VPN'
for d in 10.0.0.117 10.0.0.46 10.0.0.28; do
  a route allow in on wg0 out on ens5 proto tcp from 10.8.0.2 to "$d" port 22 comment 'fase4: VPN hospital-ti SSH'
done
a route allow in on wg0 out on ens5 proto tcp from 10.8.0.2  to 10.0.0.46 port 80 comment 'fase4: VPN hospital-ti intranet'
a route allow in on wg0 out on ens5 proto tcp from 10.8.0.10 to 10.0.0.46 port 80 comment 'fase4: VPN hospital-medico intranet'
echo "== reglas añadidas (ufw show added)"
sudo ufw show added | sed 's/^/   /'
echo "== preparar directorio de evidencias de hardening"
mkdir -p /home/ubuntu/fase3/evidencias
ls -l /home/ubuntu/fase3/leonardo/hardening.sh /home/ubuntu/fase3/leonardo/lib.sh /home/ubuntu/fase3/leonardo/fase3.env
