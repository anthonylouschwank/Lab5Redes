#!/usr/bin/env bash
# Cambia la IP del servidor del laboratorio y regenera lo que depende de ella:
# zona directa e inversa (con serial nuevo), named.conf.*, netplan y lab.env.
# Los demás servicios (LDAP, Apache, Postfix, Dovecot, vsftpd) usan nombres DNS y no cambian.
#
# Uso (en la VM, desde ~/lab5):
#   sudo bash infra/cambiar-ip.sh <IP/prefijo> [--cliente <IP>] [--simular]
# Ejemplos:
#   sudo bash infra/cambiar-ip.sh 192.168.1.50/24                       # red de la exposición
#   sudo bash infra/cambiar-ip.sh 10.0.0.37/27 --cliente 10.0.0.33      # volver a la red Host-Only
#   bash infra/cambiar-ip.sh 192.168.1.50/24 --simular                  # solo genera archivos (práctica)
set -euo pipefail
cd "$(dirname "$0")/.."
source lab.env

[ $# -ge 1 ] || { sed -n '6,12p' "$0"; exit 1; }
NUEVA="$1"; shift
CLIENTE=""; SIMULAR=0
while [ $# -gt 0 ]; do
    case "$1" in
        --cliente) CLIENTE="${2:?Falta la IP del cliente}"; shift 2 ;;
        --simular) SIMULAR=1; shift ;;
        *) echo "Opción desconocida: $1"; exit 1 ;;
    esac
done

# IP, prefijo, red, zona inversa (/24 que contiene la IP) y último octeto
read -r IP PREFIJO RED REV ULT < <(python3 - "$NUEVA" <<'EOF'
import ipaddress, sys
i = ipaddress.ip_interface(sys.argv[1])
o = str(i.ip).split('.')
print(i.ip, i.network.prefixlen, i.network, f"{o[2]}.{o[1]}.{o[0]}.in-addr.arpa", o[3])
EOF
)
REVFILE="db.$(echo "$REV" | awk -F. '{print $3"."$2"."$1}')"
OLD_IP="$SERVER_IP"; OLD_NET="$LAB_NET"
esc() { sed 's/[.]/\\./g' <<<"$1"; }

# Serial AAAAMMDDNN siempre mayor que el actual
ACTUAL="$(awk '$1 ~ /^[0-9]+$/ && $3 == "Serial" {print $1}' dns/zones/db.hospital.redes.test)"
HOY="$(date +%Y%m%d)01"
SERIAL=$(( ACTUAL >= HOY ? ACTUAL + 1 : HOY ))

echo "==> ${OLD_IP} (${OLD_NET})  ->  ${IP}/${PREFIJO} (${RED}), serial ${SERIAL}"

echo "==> Zona directa dns/zones/db.hospital.redes.test"
cat > dns/zones/db.hospital.redes.test <<EOF
; Zona directa: hospital.redes.test
; Hospital Privado Castillejos – Laboratorio 5 CC3067
; Generada por infra/cambiar-ip.sh para la red ${RED}.
;
; Serial con formato AAAAMMDDNN: incrementarlo en cada cambio de la zona.

\$ORIGIN hospital.redes.test.
\$TTL 3600

@       IN  SOA ns1.hospital.redes.test. admin.hospital.redes.test. (
                ${SERIAL}  ; Serial
                3600        ; Refresh (1 h)
                900         ; Retry (15 min)
                604800      ; Expire (1 semana)
                300 )       ; TTL negativo (NXDOMAIN, 5 min)

; Servidor de nombres y servidor de correo del dominio
@       IN  NS  ns1.hospital.redes.test.
@       IN  MX  10 mail.hospital.redes.test.

; Servicios (todos en la VM srv)
ns1     IN  A   ${IP}
ldap    IN  A   ${IP}
www     IN  A   ${IP}
mail    IN  A   ${IP}
ftp     IN  A   ${IP}

; Equipos
srv     IN  A   ${IP}
EOF
[ -n "$CLIENTE" ] && printf 'cliente IN  A   %s\n' "$CLIENTE" >> dns/zones/db.hospital.redes.test

echo "==> Zona inversa dns/zones/${REVFILE} (${REV})"
for f in dns/zones/db.*; do
    [ "$f" != "dns/zones/db.hospital.redes.test" ] && [ "$f" != "dns/zones/${REVFILE}" ] && rm -f "$f"
done
cat > "dns/zones/${REVFILE}" <<EOF
; Zona inversa: ${REV}
; Generada por infra/cambiar-ip.sh para la red ${RED}.

\$ORIGIN ${REV}.
\$TTL 3600

@       IN  SOA ns1.hospital.redes.test. admin.hospital.redes.test. (
                ${SERIAL}  ; Serial
                3600        ; Refresh
                900         ; Retry
                604800      ; Expire
                300 )       ; TTL negativo

@       IN  NS  ns1.hospital.redes.test.

${ULT}      IN  PTR srv.hospital.redes.test.
EOF
if [ -n "$CLIENTE" ] && [ "${CLIENTE%.*}" = "${IP%.*}" ]; then
    printf '%s      IN  PTR cliente.hospital.redes.test.\n' "${CLIENTE##*.}" >> "dns/zones/${REVFILE}"
fi

echo "==> dns/named.conf.local y dns/named.conf.options"
cat > dns/named.conf.local <<EOF
// /etc/bind/named.conf.local
// Zonas de las que este servidor es autoritativo (primario).

zone "hospital.redes.test" {
    type primary;
    file "/etc/bind/zones/db.hospital.redes.test";
    allow-transfer { none; };
};

zone "${REV}" {
    type primary;
    file "/etc/bind/zones/${REVFILE}";
    allow-transfer { none; };
};
EOF
sed -i "s#$(esc "$OLD_NET")#${RED}#g; s#$(esc "$OLD_IP")#${IP}#g" dns/named.conf.options

echo "==> netplan y lab.env"
sed -i -E "s#^(\s+- )[0-9.]+/[0-9]+#\1${IP}/${PREFIJO}#" infra/netplan/60-lab5.yaml
sed -i "s#$(esc "$OLD_IP")#${IP}#g" dns/netplan/61-lab5-dns.yaml
sed -i -E "s#^SERVER_IP=\"[^\"]*\"#SERVER_IP=\"${IP}\"#; s#^LAB_NET=\"[^\"]*\"#LAB_NET=\"${RED}\"#" lab.env

if [ "$SIMULAR" = 1 ]; then
    echo "==> Simulación: archivos regenerados en $(pwd), no se aplicó nada al sistema"
    named-checkzone hospital.redes.test dns/zones/db.hospital.redes.test
    named-checkzone "$REV" "dns/zones/${REVFILE}"
    exit 0
fi

echo "==> Aplicando en el sistema"
install -m 644 -o root -g bind dns/named.conf.options /etc/bind/named.conf.options
install -m 644 -o root -g bind dns/named.conf.local   /etc/bind/named.conf.local
rm -f /etc/bind/zones/db.*
install -m 644 -o root -g bind dns/zones/db.hospital.redes.test "dns/zones/${REVFILE}" /etc/bind/zones/
named-checkconf
named-checkzone hospital.redes.test /etc/bind/zones/db.hospital.redes.test
named-checkzone "$REV" "/etc/bind/zones/${REVFILE}"

install -m 600 infra/netplan/60-lab5.yaml   /etc/netplan/60-lab5.yaml
install -m 600 dns/netplan/61-lab5-dns.yaml /etc/netplan/61-lab5-dns.yaml
netplan apply
sleep 2
systemctl restart named

# Cachés de nombres (nscd guarda también hosts) y servicios con conexiones abiertas a LDAP
if command -v nscd >/dev/null; then nscd -i hosts; fi
resolvectl flush-caches
for s in nslcd apache2 postfix dovecot vsftpd; do
    systemctl is-active --quiet "$s" && systemctl restart "$s"
done

echo "==> Verificación"
ip -4 -br addr show enp0s8
for n in ns1 ldap www mail ftp; do printf '%-26s %s\n' "$n.${DOMAIN}" "$(dig +short "$n.${DOMAIN}" A)"; done
printf '%-26s %s\n' "MX ${DOMAIN}" "$(dig +short "${DOMAIN}" MX)"
printf '%-26s %s\n' "PTR ${IP}" "$(dig +short -x "${IP}")"
echo
echo "Listo. En los clientes Windows (como administrador):"
echo "  powershell -ExecutionPolicy Bypass -File infra\\windows-dns.ps1 -Dns ${IP}"
