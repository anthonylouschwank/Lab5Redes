#!/bin/bash
# Fase 4 · F2.3 — Certificado Let's Encrypt + redirección http -> https.
# Reversión: sudo cp -a /etc/nginx/sites-available/citas.pre-certbot /etc/nginx/sites-available/citas
#            && sudo nginx -t && sudo systemctl reload nginx
#            (opcional) sudo certbot delete --cert-name hospital-castillejos.duckdns.org
set -euo pipefail
DOM=hospital-castillejos.duckdns.org

echo "== 1. Respaldo de nginx"
[[ -e /etc/nginx/sites-available/citas.pre-certbot ]] || sudo cp -a /etc/nginx/sites-available/citas /etc/nginx/sites-available/citas.pre-certbot
ls -l /etc/nginx/sites-available/

echo "== 2. certbot --nginx --redirect"
sudo certbot --nginx -d "$DOM" --redirect --agree-tos --register-unsafely-without-email --non-interactive

echo "== 3. Configuración resultante"
sudo nginx -t
sudo grep -nE 'listen|server_name|return|ssl_certificate|Strict-Transport|managed by Certbot' /etc/nginx/sites-available/citas

echo "== 4. Certificado"
sudo certbot certificates 2>/dev/null | grep -E 'Certificate Name|Domains|Expiry'
echo | openssl s_client -connect 127.0.0.1:443 -servername "$DOM" 2>/dev/null | openssl x509 -noout -subject -issuer -dates

echo "== 5. Renovación"
systemctl is-enabled certbot.timer; systemctl list-timers certbot.timer --no-pager | head -3
sudo certbot renew --dry-run 2>&1 | grep -E 'Simulating|succeeded|failed|Congratulations'
