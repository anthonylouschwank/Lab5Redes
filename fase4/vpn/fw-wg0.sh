#!/bin/bash
# /etc/wireguard/fw-wg0.sh up|down — reglas de reenvío por peer (Fase 4).
#   10.8.0.2  hospital-ti     : TCP 22 a TI (.117), Servidores (.46), Médicos (.28); TCP 80 a .46
#   10.8.0.10 hospital-medico : TCP 80 a .46
#   Todo lo demás desde/hacia wg0 se rechaza (Visitantes, Internet, DMZ->VPN, peer<->peer).
# Sin NAT: los equipos internos ven la IP real del peer (10.8.0.x).
set -u
IPT=iptables
C=WG-FWD

down() {
  while $IPT -C FORWARD -j $C 2>/dev/null; do $IPT -D FORWARD -j $C; done
  $IPT -F $C 2>/dev/null; $IPT -X $C 2>/dev/null
  for d in "-i wg0" "-o wg0"; do
    while $IPT -t mangle -C FORWARD $d -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null; do
      $IPT -t mangle -D FORWARD $d -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
    done
  done
  return 0
}

up() {
  down
  $IPT -N $C
  $IPT -I FORWARD 1 -j $C
  $IPT -A $C -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
  $IPT -A $C -i wg0 -s 10.8.0.2/32  -d 10.0.0.117,10.0.0.46,10.0.0.28 -p tcp --dport 22 -m conntrack --ctstate NEW -j ACCEPT
  $IPT -A $C -i wg0 -s 10.8.0.2/32  -d 10.0.0.46 -p tcp --dport 80 -m conntrack --ctstate NEW -j ACCEPT
  $IPT -A $C -i wg0 -s 10.8.0.10/32 -d 10.0.0.46 -p tcp --dport 80 -m conntrack --ctstate NEW -j ACCEPT
  $IPT -A $C -i wg0 -j REJECT --reject-with icmp-admin-prohibited
  $IPT -A $C -o wg0 -j REJECT --reject-with icmp-admin-prohibited
  $IPT -A $C -j RETURN
  # MTU de wg0 (1420) < VPC (9001): fijar MSS evita agujeros negros de PMTU.
  for d in "-i wg0" "-o wg0"; do
    $IPT -t mangle -A FORWARD $d -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
  done
}

case "${1:-}" in
  up) up ;;
  down) down ;;
  *) echo "uso: $0 up|down"; exit 1 ;;
esac
