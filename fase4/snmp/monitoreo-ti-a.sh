#!/bin/bash
# Fase 4 · F4 (etapa A) — TI: swap de 1 GiB + prometheus + prometheus-snmp-exporter (apt Ubuntu).
# Reversión: sudo swapoff /swapfile && sudo rm /swapfile && sudo sed -i '/^\/swapfile /d' /etc/fstab;
#            sudo apt-get purge prometheus prometheus-snmp-exporter
set -euo pipefail
echo "== 1. swap"
if ! swapon --show | grep -q /swapfile; then
  sudo fallocate -l 1G /swapfile && sudo chmod 600 /swapfile && sudo mkswap /swapfile >/dev/null && sudo swapon /swapfile
  grep -q '^/swapfile ' /etc/fstab || echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab >/dev/null
  echo 'vm.swappiness = 10' | sudo tee /etc/sysctl.d/99-fase4-swap.conf >/dev/null; sudo sysctl -q -p /etc/sysctl.d/99-fase4-swap.conf
fi
swapon --show; free -m | head -2

echo "== 2. paquetes (sin recommends)"
export DEBIAN_FRONTEND=noninteractive
sudo apt-get install -y -qq --no-install-recommends prometheus prometheus-snmp-exporter >/dev/null 2>&1
dpkg -l prometheus prometheus-snmp-exporter | awk '/^ii/{print "   "$2" "$3}'
dpkg -l | awk '/^ii/ && /node-exporter/{print "   AVISO: instalado "$2}'

echo "== 3. valores por defecto"
for f in /etc/default/prometheus /etc/default/prometheus-snmp-exporter; do echo "-- $f"; grep -vE '^\s*(#|$)' "$f" || true; done
systemctl cat prometheus-snmp-exporter | grep -E 'ExecStart|User|EnvironmentFile'
ls -l /etc/prometheus/
echo "-- módulos en snmp.yml"; grep -nE '^  [a-z_]+:$' /etc/prometheus/snmp.yml | grep -vE '^\s*[0-9]+:\s+(public_v[12]|.*_v3)' | head -40
echo "-- auths:"; awk '/^auths:/{f=1;next} /^[a-z]/{f=0} f && /^  [a-z_0-9]+:$/' /etc/prometheus/snmp.yml
echo "-- ayuda config.file"; prometheus-snmp-exporter --help 2>&1 | grep -A2 -E 'config.file|dry-run|web.listen' | head -15
ss -tlnp | grep -E ':(9090|9116|9100)\s' | awk '{print "   escucha "$4}'
