#!/bin/bash
# Fase 4 · F3 — Servidores (10.0.0.46): acceso desde la VPN.
#   ufw: 80/tcp desde 10.8.0.0/24 · 22/tcp solo desde 10.8.0.2
#   Apache: agrega 10.8.0.0/24 a las 3 líneas `Require ip` (LDAP por grupo sin cambios).
# Respaldo: /etc/apache2/sites-available/hospital-intranet.conf.bak.fase4
# Reversión: sudo bash vpn-servidores.sh --revertir
set -euo pipefail
F=/etc/apache2/sites-available/hospital-intranet.conf
B=$F.bak.fase4

if [[ "${1:-}" == "--revertir" ]]; then
  sudo ufw delete allow from 10.8.0.0/24 to any port 80 proto tcp || true
  sudo ufw delete allow from 10.8.0.2 to any port 22 proto tcp || true
  sudo cp -a "$B" "$F" && sudo apache2ctl configtest && sudo systemctl reload apache2
  echo "Revertido."; exit 0
fi

echo "== 1. ufw"
sudo ufw allow from 10.8.0.0/24 to any port 80 proto tcp comment 'fase4: Intranet desde la VPN'
sudo ufw allow from 10.8.0.2 to any port 22 proto tcp comment 'fase4: SSH desde VPN peer hospital-ti'

echo "== 2. Apache"
[[ -e "$B" ]] || sudo cp -a "$F" "$B"
sudo sed -i -E '/^\s*Require ip / { /10\.8\.0\.0\/24/! s#10\.0\.0\.112/28 #10.0.0.112/28 10.8.0.0/24 # }' "$F"
if sudo apache2ctl configtest 2>&1 | grep -q 'Syntax OK'; then
  sudo systemctl reload apache2
  echo "   configtest OK, Apache recargado"
else
  sudo apache2ctl configtest || true
  sudo cp -a "$B" "$F"; echo "   ERROR de sintaxis: se restauró el respaldo"; exit 1
fi
sudo grep -n 'Require ip' "$F"
echo "   diferencias con el respaldo:"; sudo diff "$B" "$F" | grep -viE 'password|bindpw' || true
systemctl is-active apache2

echo "== 3. Regresión local"
curl -s -o /dev/null -w "   http://127.0.0.1/ -> %{http_code}\n" http://127.0.0.1/
curl -s -o /dev/null -w "   http://127.0.0.1/intranet/ (sin credenciales) -> %{http_code}\n" http://127.0.0.1/intranet/
sudo ufw status numbered | grep -E 'fase4|^\s*To|Status'
