#!/bin/bash
# Fase 4 · F3 — WireGuard en Hospital-EC2-DMZ (10.0.0.100).
# wg0 10.8.0.1/24, UDP 51820, ip_forward SIN masquerade (la VPC enruta 10.8.0.0/24 -> ENI DMZ).
# Filtrado por peer en la cadena WG-FWD (fw-wg0.sh, cargada por PostUp).
# La clave privada del servidor se genera aquí, queda en /etc/wireguard/server.key (0600 root)
# y NUNCA se imprime ni se escribe en wg0.conf.
# Reversión: sudo bash wg-dmz.sh --revertir
set -euo pipefail
PEER_TI_PUB='tEeBEkG/4XI/5Wm39iqWqLKUWRDoxEemzvmWDHrjEx0='
PEER_MED_PUB='s1tYepKqtvkK+u08qPRl853fY0qpLTy5l4LCQHZJigU='
SRC=/home/ubuntu/vpn

if [[ "${1:-}" == "--revertir" ]]; then
  sudo systemctl disable --now wg-quick@wg0 || true
  sudo rm -f /etc/sysctl.d/99-fase4-wg.conf; sudo sysctl -w net.ipv4.ip_forward=0
  sudo bash /etc/wireguard/fw-wg0.sh down || true
  echo "Revertido (claves y wg0.conf se conservan en /etc/wireguard)."; exit 0
fi

echo "== 1. Paquete"
export DEBIAN_FRONTEND=noninteractive
sudo apt-get install -y -qq wireguard-tools >/dev/null
dpkg -l wireguard-tools | awk '/^ii/{print "   "$2" "$3}'

echo "== 2. Claves del servidor (solo root)"
sudo install -d -m 700 -o root -g root /etc/wireguard
if ! sudo test -s /etc/wireguard/server.key; then
  sudo sh -c 'umask 077; wg genkey > /etc/wireguard/server.key'
  echo "   clave nueva generada"
else
  echo "   clave existente conservada"
fi
sudo sh -c 'umask 077; wg pubkey < /etc/wireguard/server.key > /etc/wireguard/server.pub'
sudo chmod 600 /etc/wireguard/server.key; sudo chmod 644 /etc/wireguard/server.pub
sudo ls -l /etc/wireguard/ | awk '{print "   "$1" "$3" "$9}'

echo "== 3. Firewall de reenvío y wg0.conf"
tr -d '\r' < "$SRC/fw-wg0.sh" | sed '1s/^\xEF\xBB\xBF//' | sudo tee /etc/wireguard/fw-wg0.sh >/dev/null
sudo chown root:root /etc/wireguard/fw-wg0.sh; sudo chmod 700 /etc/wireguard/fw-wg0.sh
sudo bash -n /etc/wireguard/fw-wg0.sh
[[ -e /etc/wireguard/wg0.conf ]] && sudo cp -a /etc/wireguard/wg0.conf "/etc/wireguard/wg0.conf.bak.$(date +%s)"
sudo tee /etc/wireguard/wg0.conf >/dev/null <<EOF
# Fase 4 — VPN de acceso remoto. La clave privada se carga desde server.key (no se guarda aquí).
[Interface]
Address = 10.8.0.1/24
ListenPort = 51820
PostUp = wg set %i private-key /etc/wireguard/server.key
PostUp = /etc/wireguard/fw-wg0.sh up
PostDown = /etc/wireguard/fw-wg0.sh down

# hospital-ti: SSH a TI/Servidores/Médicos, intranet y Grafana (vía SSH a TI)
[Peer]
PublicKey = $PEER_TI_PUB
AllowedIPs = 10.8.0.2/32

# hospital-medico: solo intranet 10.0.0.46:80
[Peer]
PublicKey = $PEER_MED_PUB
AllowedIPs = 10.8.0.10/32
EOF
sudo chmod 600 /etc/wireguard/wg0.conf

echo "== 4. ip_forward"
echo 'net.ipv4.ip_forward = 1' | sudo tee /etc/sysctl.d/99-fase4-wg.conf >/dev/null
sudo sysctl -p /etc/sysctl.d/99-fase4-wg.conf

echo "== 5. Servicio"
sudo systemctl enable wg-quick@wg0 >/dev/null 2>&1
sudo systemctl restart wg-quick@wg0
systemctl is-active wg-quick@wg0
ip -br addr show wg0

echo "== 6. Estado (sin claves privadas)"
echo "   Clave pública del servidor: $(sudo cat /etc/wireguard/server.pub)"
sudo wg show wg0 | grep -vi 'private'
sudo iptables -S WG-FWD
sudo iptables -S FORWARD | head -3
sudo iptables -t mangle -S FORWARD | grep TCPMSS
sudo ss -ulnp | grep 51820 || true
