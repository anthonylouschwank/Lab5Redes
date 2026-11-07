#!/bin/bash
# Fase 4 · F5 — Verificación de la DMZ tras hardening.sh cliente (+ reinicio de wg0 para fijar WG-FWD al inicio de FORWARD).
set -uo pipefail
echo "# Post-hardening $(hostname) $(date -Is)"
echo "== 1. rollback"; systemctl list-timers ufw-rollback.timer --no-pager --all | sed -n '1,3p'; systemctl is-active ufw-rollback.timer || true
echo "== 2. sshd efectivo"; sudo sshd -T | grep -E '^(permitrootlogin|passwordauthentication|kbdinteractiveauthentication|x11forwarding|pubkeyauthentication) '
echo "== 3. ufw"; sudo ufw status verbose
echo "== 4. FORWARD antes de reiniciar wg0"; sudo iptables -S FORWARD | head -4
sudo systemctl restart wg-quick@wg0; sleep 1
echo "== 5. FORWARD después de reiniciar wg0"; sudo iptables -S FORWARD | head -4
echo "   wg-quick@wg0: $(systemctl is-active wg-quick@wg0)  ip_forward=$(sysctl -n net.ipv4.ip_forward)"
echo "== 6. servicios"; for s in nginx citas snmpd wg-quick@wg0 ssh chrony ModemManager certbot.timer; do printf '   %-14s %s / %s\n' "$s" "$(systemctl is-active $s)" "$(systemctl is-enabled $s 2>/dev/null)"; done
echo "== 7. puertos en escucha (después)"
sudo ss -tulnpH | awk '{p=$7; sub(/^users:\(\("/,"",p); sub(/".*/,"",p); print "   "$1, $5, p}' | sort -u
echo "== 8. diff de inventario antes/después (hardening.sh)"
diff -u /home/ubuntu/fase3/evidencias/hardening-antes-ip-10-0-0-100.txt /home/ubuntu/fase3/evidencias/hardening-despues-ip-10-0-0-100.txt | tail -n +3 || true
echo "== 9. web local"
curl -s -o /dev/null -w "   https dominio -> %{http_code}\n" --resolve hospital-castillejos.duckdns.org:443:127.0.0.1 https://hospital-castillejos.duckdns.org/salud
