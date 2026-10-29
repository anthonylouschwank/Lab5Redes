echo "== fecha"; date -Is
echo "== puertos en escucha"; sudo ss -tulnpH | awk '{print $1, $5, $7}'
echo "== ufw"; sudo ufw status verbose
echo "== sshd efectivo"; sudo sshd -T 2>/dev/null | grep -E '^(passwordauthentication|permitrootlogin|x11forwarding|kbdinteractiveauthentication) '
echo "== slapd services"; grep -n '^SLAPD_SERVICES' /etc/default/slapd
echo "== vhost Require"; sudo grep -nE 'Require|Location|Directory|AuthLDAPURL' /etc/apache2/sites-available/hospital-intranet.conf
echo "== chrony"; chronyc -n tracking; chronyc -n sources; sudo grep -RnsE '^[[:space:]]*(server|pool|allow|local|bindaddress|sourcedir|confdir)' /etc/chrony
echo "== DHCP lease"; sudo grep -hE '^(ADDRESS|NETMASK|ROUTER|DNS|DOMAINNAME|SERVER_ADDRESS|LIFETIME)=' /run/systemd/netif/leases/* ; ip -4 route; resolvectl status ens5 | sed -n '1,12p'
echo "== fase3 dir"; ls -la ~/fase3 ~/fase3/isabella/evidencias 2>/dev/null
echo "== servicios corriendo"; systemctl list-units --type=service --state=running --no-legend --plain | awk '{print $1}'
