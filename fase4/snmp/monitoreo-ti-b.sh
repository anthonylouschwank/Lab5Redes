#!/bin/bash
# Fase 4 · F4 (etapa B) — TI: configurar snmp_exporter + Prometheus (127.0.0.1) e instalar Grafana OSS (repo oficial).
# Requiere los archivos en /home/ubuntu/snmp/monitoreo (rscp) y /etc/snmp-fase4/creds.
# Reversión: ver fase4/CAMBIOS-Y-REVERSION.md (D21–D22).
set -euo pipefail
M=/home/ubuntu/snmp/monitoreo
crlf() { tr -d '\r' < "$1" | sed '1s/^\xEF\xBB\xBF//'; }

echo "== 1. snmp_exporter"
[[ -e /etc/prometheus/snmp.yml.dist ]] || sudo cp -a /etc/prometheus/snmp.yml /etc/prometheus/snmp.yml.dist
crlf "$M/snmp.yml" | sudo tee /etc/prometheus/snmp.yml >/dev/null
sudo bash -c '
  set -euo pipefail; . /etc/snmp-fase4/creds; umask 027
  cat > /etc/prometheus/snmp-auth.yml <<EOF
# Credenciales SNMPv3 (Fase 4) — 0640 root:prometheus. No imprimir.
auths:
  hospital_v3:
    version: 3
    security_level: authPriv
    username: monitor
    auth_protocol: SHA
    password: "$AUTH"
    priv_protocol: AES
    priv_password: "$PRIV"
EOF
  chown root:prometheus /etc/prometheus/snmp-auth.yml; chmod 640 /etc/prometheus/snmp-auth.yml'
sudo stat -c '   %A %U:%G %n' /etc/prometheus/snmp.yml /etc/prometheus/snmp-auth.yml
sudo -u prometheus prometheus-snmp-exporter --dry-run --config.file=/etc/prometheus/snmp.yml --config.file=/etc/prometheus/snmp-auth.yml 2>&1 | tail -2
echo 'ARGS="--web.listen-address=127.0.0.1:9116 --config.file=/etc/prometheus/snmp.yml --config.file=/etc/prometheus/snmp-auth.yml"' | sudo tee /etc/default/prometheus-snmp-exporter >/dev/null
sudo systemctl restart prometheus-snmp-exporter; sleep 2
systemctl is-active prometheus-snmp-exporter
curl -s 'http://127.0.0.1:9116/snmp?target=10.0.0.46&module=hospital&auth=hospital_v3' | grep -E '^(sysName|sysUpTime|memAvailReal|dskPercent|laLoadInt\{laIndex="1"\}|ifHCInOctets)' | head -8 | sed 's/^/   /'

echo "== 2. Prometheus"
[[ -e /etc/prometheus/prometheus.yml.dist ]] || sudo cp -a /etc/prometheus/prometheus.yml /etc/prometheus/prometheus.yml.dist
crlf "$M/prometheus.yml" | sudo tee /etc/prometheus/prometheus.yml >/dev/null
promtool check config /etc/prometheus/prometheus.yml | sed 's/^/   /'
echo 'ARGS="--web.listen-address=127.0.0.1:9090 --storage.tsdb.retention.time=7d"' | sudo tee /etc/default/prometheus >/dev/null
sudo systemctl restart prometheus; sleep 3
systemctl is-active prometheus

echo "== 3. Grafana OSS (apt.grafana.com)"
export DEBIAN_FRONTEND=noninteractive
sudo apt-get install -y -qq apt-transport-https gnupg >/dev/null 2>&1
sudo install -d -m 755 /etc/apt/keyrings
curl -fsSL https://apt.grafana.com/gpg.key | sudo gpg --dearmor --yes -o /etc/apt/keyrings/grafana.gpg
gpg --show-keys --with-fingerprint /etc/apt/keyrings/grafana.gpg 2>/dev/null | grep -E '^\s+[0-9A-F ]{40,}|uid' | sed 's/^/   /'
echo 'deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main' | sudo tee /etc/apt/sources.list.d/grafana.list >/dev/null
sudo apt-get update -qq >/dev/null 2>&1
sudo apt-get install -y -qq grafana >/dev/null 2>&1
dpkg -l grafana | awk '/^ii/{print "   "$2" "$3}'

echo "== 4. Configuración de Grafana (solo 127.0.0.1)"
sudo bash -c '
  set -euo pipefail
  F=/etc/default/grafana-server
  [[ -e $F.dist ]] || cp -a $F $F.dist
  sed -i "/^GF_/d" $F
  cat >> $F <<EOF
GF_SERVER_HTTP_ADDR=127.0.0.1
GF_SERVER_HTTP_PORT=3000
GF_USERS_ALLOW_SIGN_UP=false
GF_AUTH_ANONYMOUS_ENABLED=false
GF_ANALYTICS_REPORTING_ENABLED=false
GF_ANALYTICS_CHECK_FOR_UPDATES=false
GF_SECURITY_COOKIE_SECURE=false
GF_SECURITY_DISABLE_GRAVATAR=true
EOF
  # Contraseña inicial aleatoria (nadie la conoce); el usuario la reemplaza con grafana-cli.
  if [[ ! -e /var/lib/grafana/grafana.db ]]; then
    echo "GF_SECURITY_ADMIN_PASSWORD=$(openssl rand -hex 24)" >> $F
  fi
  chmod 640 $F; chown root:grafana $F'
sudo install -d -o root -g grafana -m 750 /var/lib/grafana/dashboards
crlf "$M/grafana-datasource.yaml" | sudo tee /etc/grafana/provisioning/datasources/prometheus-hospital.yaml >/dev/null
crlf "$M/grafana-dashboards.yaml" | sudo tee /etc/grafana/provisioning/dashboards/hospital.yaml >/dev/null
crlf "$M/red-hospital.json" | sudo tee /var/lib/grafana/dashboards/red-hospital.json >/dev/null
sudo chown root:grafana /etc/grafana/provisioning/datasources/prometheus-hospital.yaml /etc/grafana/provisioning/dashboards/hospital.yaml /var/lib/grafana/dashboards/red-hospital.json
sudo chmod 640 /etc/grafana/provisioning/datasources/prometheus-hospital.yaml /etc/grafana/provisioning/dashboards/hospital.yaml /var/lib/grafana/dashboards/red-hospital.json
sudo systemctl daemon-reload
sudo systemctl enable grafana-server >/dev/null 2>&1
sudo systemctl restart grafana-server
for i in $(seq 1 30); do curl -fs http://127.0.0.1:3000/api/health >/dev/null && break; sleep 2; done
curl -s http://127.0.0.1:3000/api/health | tr -d '\n'; echo
# Una vez creada la BD, se quita la contraseña inicial del archivo de entorno.
sudo sed -i '/^GF_SECURITY_ADMIN_PASSWORD=/d' /etc/default/grafana-server

echo "== 5. Puertos (deben ser solo 127.0.0.1)"
sudo ss -tlnp | grep -E ':(3000|9090|9116|9100)\s' | awk '{print "   "$4}'
free -m | head -2
