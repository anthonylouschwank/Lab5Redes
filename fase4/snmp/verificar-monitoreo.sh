#!/bin/bash
# Fase 4 · F6 — Verificación de Prometheus/Grafana en TI (solo lectura).
echo "# Monitoreo en $(hostname) $(date -Is)"
echo "== Objetivos de Prometheus"
curl -s http://127.0.0.1:9090/api/v1/targets | python3 -c '
import json,sys
for t in json.load(sys.stdin)["data"]["activeTargets"]:
    l=t["labels"]; print("   %-14s %-12s %-11s %-5s %s" % (l["job"], l.get("equipo","-"), l["instance"], t["health"], t.get("lastError","")))'
q() { curl -s --data-urlencode "query=$1" http://127.0.0.1:9090/api/v1/query | python3 -c '
import json,sys
for r in json.load(sys.stdin)["data"]["result"]:
    print("   %-12s %s" % (r["metric"].get("equipo","-"), r["value"][1]))'; }
echo "== Uptime del equipo (h)"; q 'round(hrSystemUptime{job="snmp"}/100/3600, 0.1)'
echo "== Memoria usada (%)";     q 'round(100*(1-memAvailReal{job="snmp"}/memTotalReal{job="snmp"}))'
echo "== Disco / (%)";           q 'dskPercent{job="snmp",dskPath="/"}'
echo "== Carga 1 min";           q 'laLoadInt{job="snmp",laIndex="1"}/100'
echo "== Tráfico ens5 entrada (bit/s, 5m)"; q 'round(rate(ifHCInOctets{job="snmp",ifDescr="ens5"}[5m])*8)'
echo "== Grafana"
curl -s http://127.0.0.1:3000/api/health | tr -d '\n '; echo
sudo journalctl -u grafana-server --since "-15 min" --no-pager 2>/dev/null | grep -iE 'provision|dashboard|datasource' | grep -iE 'error|fail|inserted|finished' | tail -5 | sed 's/^/   /'
echo "   sqlite: $(sudo sqlite3 /var/lib/grafana/grafana.db "select count(*)||' dashboards: '||group_concat(title) from dashboard;" 2>/dev/null || echo 'sqlite3 no instalado')"
echo "   datasources: $(sudo sqlite3 /var/lib/grafana/grafana.db "select group_concat(name||' -> '||url) from data_source;" 2>/dev/null)"
echo "== Puertos de monitoreo"; sudo ss -tlnp | grep -E ':(3000|9090|9116)\s' | awk '{print "   "$4}'
