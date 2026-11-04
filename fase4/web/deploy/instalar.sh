#!/bin/bash
# Fase 4 · F2 — Despliegue de la app de citas en Hospital-EC2-DMZ.
# Requiere el código copiado en ~ubuntu/web (rscp.ps1 ... fase4/web /home/ubuntu/).
# Idempotente. No ejecuta certbot (paso aparte).
# Reversión: sudo bash instalar.sh --revertir
set -euo pipefail
SRC=/home/ubuntu/web
DOM=hospital-castillejos.duckdns.org

if [[ "${1:-}" == "--revertir" ]]; then
  sudo systemctl disable --now citas || true
  sudo rm -f /etc/systemd/system/citas.service /etc/nginx/sites-enabled/citas \
             /etc/nginx/sites-available/citas /etc/nginx/snippets/citas-proxy.conf
  [[ -e /etc/nginx/sites-available/default ]] && sudo ln -sf /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default
  sudo systemctl daemon-reload; sudo nginx -t && sudo systemctl reload nginx
  echo "Revertido (paquetes y /var/lib/citas se conservan)."; exit 0
fi

echo "== 1. Paquetes"
export DEBIAN_FRONTEND=noninteractive
sudo apt-get update -qq
sudo apt-get install -y -qq nginx certbot python3-certbot-nginx python3-flask gunicorn sqlite3 >/dev/null
dpkg -l nginx certbot python3-certbot-nginx python3-flask gunicorn | awk '/^ii/{print "   "$2" "$3}'

echo "== 2. Usuario de servicio y archivos"
id citas >/dev/null 2>&1 || sudo useradd --system --home /nonexistent --shell /usr/sbin/nologin citas
sudo install -d -o root -g root -m 755 /opt/citas
sudo cp -r "$SRC/app.py" "$SRC/templates" "$SRC/static" /opt/citas/
sudo chown -R root:root /opt/citas; sudo chmod -R u=rwX,go=rX /opt/citas
sudo install -d -o citas -g citas -m 750 /var/lib/citas

echo "== 3. systemd"
sudo install -m 644 "$SRC/deploy/citas.service" /etc/systemd/system/citas.service
sudo systemctl daemon-reload
sudo systemctl enable --now citas
sudo systemctl restart citas
sleep 2
systemctl is-active citas
curl -fsS http://127.0.0.1:8000/salud; echo

echo "== 4. nginx"
sudo install -m 644 "$SRC/deploy/citas-proxy.conf" /etc/nginx/snippets/citas-proxy.conf
if [[ ! -e /etc/nginx/sites-available/citas ]] || ! sudo grep -q 'managed by Certbot' /etc/nginx/sites-available/citas; then
  sudo install -m 644 "$SRC/deploy/nginx-citas.conf" /etc/nginx/sites-available/citas
else
  echo "   sites-available/citas ya fue modificado por Certbot: no se sobrescribe."
fi
sudo ln -sf /etc/nginx/sites-available/citas /etc/nginx/sites-enabled/citas
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t
sudo systemctl enable --now nginx
sudo systemctl reload nginx
sleep 2   # el reload de nginx es asíncrono

echo "== 5. Comprobación local"
curl -s -o /dev/null -w "   Host=$DOM  -> %{http_code}\n" -H "Host: $DOM" http://127.0.0.1/salud
curl -s -o /dev/null -w "   Host=IP    -> %{http_code} (444 esperado = sin respuesta)\n" http://127.0.0.1/ || echo "   Host=IP    -> conexión cerrada (444) OK"
sudo ss -tlnp | grep -E ':(80|443|8000)\s' | sed 's/users:.*"\([^"]*\)".*/\1/'
