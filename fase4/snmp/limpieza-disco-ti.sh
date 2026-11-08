#!/bin/bash
# Fase 4 · F4 — Liberar disco en TI tras instalar Grafana.
#  - apt clean (caché de paquetes .deb)
#  - Grafana: desactivar plugins "preinstalados" (no se usan; Prometheus es integrado) y borrarlos
#  - journald limitado a 50 MB
# Reversión: quitar GF_PLUGINS_PREINSTALL_DISABLED de /etc/default/grafana-server y reiniciar grafana-server
#            (vuelve a descargar los plugins); borrar /etc/systemd/journald.conf.d/50-fase4.conf
set -euo pipefail
echo "antes: $(df -h / | awk 'NR==2{print $3" usados, "$4" libres ("$5")"}')"
echo "-- plugins de Grafana:"; sudo ls /var/lib/grafana/plugins 2>/dev/null | sed 's/^/   /'; sudo du -sh /var/lib/grafana/* 2>/dev/null | sed 's/^/   /'
sudo apt-get clean
grep -q '^GF_PLUGINS_PREINSTALL_DISABLED=' /etc/default/grafana-server 2>/dev/null || \
  echo 'GF_PLUGINS_PREINSTALL_DISABLED=true' | sudo tee -a /etc/default/grafana-server >/dev/null
sudo systemctl stop grafana-server
sudo rm -rf /var/lib/grafana/plugins/*
sudo systemctl start grafana-server
sudo install -d /etc/systemd/journald.conf.d
printf '[Journal]\nSystemMaxUse=50M\n' | sudo tee /etc/systemd/journald.conf.d/50-fase4.conf >/dev/null
sudo systemctl restart systemd-journald; sudo journalctl --vacuum-size=50M -q
for i in $(seq 1 30); do curl -fs http://127.0.0.1:3000/api/health >/dev/null && break; sleep 2; done
echo "grafana: $(curl -s http://127.0.0.1:3000/api/health | tr -d '\n ')"
sleep 5; echo "-- plugins tras reinicio:"; sudo ls /var/lib/grafana/plugins 2>/dev/null | sed 's/^/   /'
echo "después: $(df -h / | awk 'NR==2{print $3" usados, "$4" libres ("$5")"}')"
