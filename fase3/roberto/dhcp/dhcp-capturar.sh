#!/usr/bin/env bash
# dhcp-capturar.sh — Evidencia de DHCP (E5.1–E5.2): qué configuración recibe una EC2 del DHCP de AWS.
#
# Se corre EN cada EC2 (Ubuntu 24.04), sin root, solo lectura:
#   bash dhcp-capturar.sh [carpeta_salida]
# Deja dhcp-<host>-<fecha>.txt (por defecto en la carpeta actual). Cada corrida crea un archivo
# nuevo: no pisa evidencia anterior. Oculta IDs de cuenta (12 dígitos) y ARN antes de guardar.
# No modifica nada del equipo. Lo que no exista o no se pueda leer se anota, no hace fallar el script.
set -euo pipefail

SALIDA_DIR="${1:-$PWD}"
mkdir -p "$SALIDA_DIR"
HOST="$(hostname -s)"
SALIDA="${SALIDA_DIR}/dhcp-${HOST}-$(date +%F_%H%M).txt"
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

seccion() {   # seccion "<título>" <comando...>
    local titulo="$1"; shift
    { printf '\n===== %s =====\n$ %s\n' "$titulo" "$*"
      "$@" 2>&1 || printf '(el comando terminó con error o no está disponible)\n'
    } >> "$TMP"
}

{
    echo "# Evidencia DHCP administrado por AWS (DHCP option set de la VPC)"
    echo "# Equipo: $(hostname -f 2>/dev/null || hostname)   Fecha: $(date '+%F %T %Z')   Kernel: $(uname -r)"
    echo "# Qué se espera ver si el equipo es una EC2 de la VPC: IP privada de la subred, puerta de enlace (router de la VPC),"
    echo "# DNS y dominio del option set, y duración del lease. Este archivo solo muestra lo observado en el equipo."
} > "$TMP"

seccion "1. Direcciones IPv4 asignadas" ip -4 -br addr
seccion "2. Ruta por defecto (gateway entregado por DHCP)" ip -4 route
seccion "3. DNS y dominio recibidos (resolvectl)" resolvectl status
seccion "4. /etc/resolv.conf (stub local de systemd-resolved)" cat /etc/resolv.conf

# Leases de systemd-networkd (existen si la interfaz usa DHCP vía networkd; contienen ADDRESS, ROUTER, DNS, DOMAINS, LIFETIME)
if compgen -G "/run/systemd/netif/leases/*" >/dev/null; then
    for f in /run/systemd/netif/leases/*; do seccion "5. Lease DHCP ($f)" cat "$f"; done
else
    printf '\n===== 5. Lease DHCP =====\n(no hay archivos en /run/systemd/netif/leases/; ver sección 6)\n' >> "$TMP"
fi

IFACE="$({ ip -4 route show default 2>/dev/null || true; } | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')"
if [[ -n "$IFACE" ]]; then
    seccion "6. Estado de la interfaz $IFACE (networkctl: incluye servidor DHCP y lease)" networkctl status "$IFACE" --no-pager
fi
seccion "7. Configuración netplan (solo lectura)" bash -c 'for f in /etc/netplan/*.yaml; do echo "--- $f"; cat "$f"; done'
seccion "8. Registros de DHCP en systemd-networkd (últimos 15)" bash -c "journalctl -u systemd-networkd --no-pager 2>/dev/null | grep -i dhcp | tail -n 15"

# Metadatos de red por IMDSv2 (IP privada, MAC y CIDR de la subred/VPC). No se consultan datos de la cuenta.
imds() {
    local tok
    tok="$(curl -sS -m 2 -X PUT 'http://169.254.169.254/latest/api/token' -H 'X-aws-ec2-metadata-token-ttl-seconds: 60')" || return 1
    curl -sS -m 2 -H "X-aws-ec2-metadata-token: $tok" "http://169.254.169.254/latest/meta-data/$1"
}
{
    printf '\n===== 9. Metadatos de red (IMDSv2; contraste con lo asignado por DHCP) =====\n'
    if mac="$(imds mac 2>/dev/null)" && [[ -n "$mac" ]]; then
        printf 'local-ipv4:        %s\n' "$(imds local-ipv4 2>/dev/null || echo '?')"
        printf 'subnet-ipv4-cidr:  %s\n' "$(imds "network/interfaces/macs/${mac}/subnet-ipv4-cidr-block" 2>/dev/null || echo '?')"
        printf 'vpc-ipv4-cidr:     %s\n' "$(imds "network/interfaces/macs/${mac}/vpc-ipv4-cidr-blocks" 2>/dev/null | tr '\n' ' ' || echo '?')"
    else
        echo '(no se pudo consultar el servicio de metadatos)'
    fi
} >> "$TMP"

# Ocultar IDs de cuenta (12 dígitos seguidos) y ARN; el resto queda tal cual para que sea verificable.
sed -E -e 's/(^|[^0-9])[0-9]{12}([^0-9]|$)/\1************\2/g' -e 's#arn:aws[a-z-]*:[^ "]+#arn:aws:<oculto>#g' "$TMP" > "$SALIDA"
chmod 600 "$SALIDA"
printf 'Evidencia guardada en: %s\n' "$SALIDA"
printf 'Revísala antes de subirla al repo (MAC e IPs privadas se dejan; no hay contraseñas ni claves).\n'
