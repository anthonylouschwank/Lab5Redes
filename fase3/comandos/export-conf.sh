d=~/fase3/config-final; rm -rf "$d"; mkdir -p "$d"
h=$(hostname)
sudo ufw status verbose > "$d/ufw-$h.txt"
sudo cat /etc/ssh/sshd_config.d/01-fase3-hardening.conf > "$d/sshd-01-fase3-hardening.conf" 2>/dev/null
for f in /etc/chrony/conf.d/fase3-*.conf /etc/chrony/conf.d/00-cpc.conf; do [ -f "$f" ] && cp "$f" "$d/chrony-$(basename "$f")"; done
if [ "$h" = "ip-10-0-0-46" ]; then
  sudo cat /etc/apache2/sites-available/hospital-intranet.conf > "$d/apache-hospital-intranet.conf"
  grep -n '^SLAPD_SERVICES' /etc/default/slapd > "$d/slapd-default-SLAPD_SERVICES.txt"
  apache2ctl -M 2>/dev/null | grep -E 'ldap|include' > "$d/apache-modulos.txt"
fi
echo "== revision de secretos"; grep -RniE 'password|passwd|secret|SSHA|BEGIN' "$d" | grep -viE 'PasswordAuthentication|KbdInteractive' || echo "(sin coincidencias sensibles)"
ls -l "$d"
