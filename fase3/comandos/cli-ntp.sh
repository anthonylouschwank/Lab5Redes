# Se antepone por PowerShell: NTP_SRV=<ip>
set -e
cd ~/fase3/leonardo
sed -i 's/\r$//' *.sh fase3.env fase3.env.example
mkdir -p ~/fase3/evidencias
echo "######## Equipo"; hostname; date -Is; ip -4 -br a
echo "######## DHCP (E5.2): concesión recibida de AWS"
sudo grep -hE '^(ADDRESS|NETMASK|ROUTER|DNS|DOMAINNAME|SERVER_ADDRESS|LIFETIME)=' /run/systemd/netif/leases/*
ip -4 route
resolvectl status ens5 | sed -n '1,8p'
echo "######## Puertos en escucha (antes de hardening)"
sudo ss -tulnpH | awk '{print $1, $5, $7}'
echo "######## chrony-cliente.sh (NTP_SERVER=$NTP_SRV)"
sudo NTP_SERVER="$NTP_SRV" FASE3_EVID_DIR=$HOME/fase3/evidencias bash chrony-cliente.sh 2>&1 | sed 's/\x1b\[[0-9;]*m//g'
