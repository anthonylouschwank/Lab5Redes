#!/usr/bin/env bash
# nat-instance.sh — Convierte la EC2 de la DMZ en NAT instance (Fase 3, Hospital).
#
# Dónde: en la EC2 NAT (subred DMZ, con IP pública). NO en las privadas.
# Uso:
#   sudo bash nat-instance.sh              # aplicar (idempotente: se puede repetir)
#   sudo bash nat-instance.sh --estado     # solo mostrar el estado actual
#   sudo bash nat-instance.sh --revertir   # quitar NAT y forwarding
#
# Qué hace:
#   1. net.ipv4.ip_forward=1 persistente en /etc/sysctl.d/60-fase3-nat.conf
#   2. Reglas (aplicadas por el servicio systemd fase3-nat, así sobreviven al reinicio
#      sin instalar iptables-persistent):
#        - nat/POSTROUTING: -s <subred> ! -d <VPC> -o <iface> -j MASQUERADE
#        - cadena FASE3-NAT al inicio de FORWARD: deja salir <subred> -> Internet y
#          volver solo el tráfico de respuesta (ESTABLISHED,RELATED).
#        - política de FORWARD = DROP: nada iniciado desde Internet atraviesa la NAT,
#          y la NAT no sirve de puente entre subredes de la VPC.
#   3. Verifica forwarding, reglas, contadores y que la NAT tenga salida a Internet.
#
# Vía elegida para el firewall: reglas propias de iptables (backend nft de Ubuntu 24.04)
# en la cadena FASE3-NAT. ufw NO gestiona la NAT: si hardening.sh activa ufw en esta
# máquina (rol nat), ufw solo filtra la ENTRADA y este servicio se reinicia después.
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"

SYSCTL_FILE=/etc/sysctl.d/60-fase3-nat.conf
REGLAS_BIN=/usr/local/sbin/fase3-nat-reglas
UNIDAD=/etc/systemd/system/fase3-nat.service
CADENA=FASE3-NAT

modo="aplicar"
case "${1:-}" in
    "") ;;
    --estado) modo="estado" ;;
    --revertir) modo="revertir" ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) die "Opción desconocida: $1 (usa --estado, --revertir o nada)" ;;
esac

require_root
cargar_env
iniciar_evidencia "nat-instance.sh" "$modo"
revisar_ubuntu

mostrar_estado() {
    mostrar "sysctl net.ipv4.ip_forward" sysctl net.ipv4.ip_forward
    mostrar "iptables -t nat -S POSTROUTING" iptables -t nat -S POSTROUTING
    mostrar "iptables -L FORWARD (política y primeras reglas)" sh -c 'iptables -L FORWARD -n --line-numbers | head -n 8'
    mostrar "contadores de $CADENA" iptables -L "$CADENA" -v -n
    mostrar "contadores de MASQUERADE" iptables -t nat -L POSTROUTING -v -n
    mostrar "servicio fase3-nat (habilitado / activo)" sh -c 'systemctl is-enabled fase3-nat.service; systemctl is-active fase3-nat.service'
}

# ---------------------------------------------------------------- --estado
if [[ "$modo" == "estado" ]]; then
    paso "Estado de la NAT"
    mostrar_estado
    resumen_final "estado mostrado"
    exit $?
fi

# ---------------------------------------------------------------- --revertir
if [[ "$modo" == "revertir" ]]; then
    paso "Revirtiendo la NAT"
    if [[ -f "$UNIDAD" ]]; then
        systemctl disable --now fase3-nat.service 2>/dev/null || true
        respaldar "$UNIDAD"; rm -f "$UNIDAD"
        systemctl daemon-reload
        ok "Servicio fase3-nat detenido y eliminado"
    fi
    if [[ -x "$REGLAS_BIN" ]]; then
        "$REGLAS_BIN" stop || true
        respaldar "$REGLAS_BIN"; rm -f "$REGLAS_BIN"
        ok "Reglas de NAT y cadena $CADENA eliminadas"
    fi
    if [[ -f "$SYSCTL_FILE" ]]; then
        respaldar "$SYSCTL_FILE"; rm -f "$SYSCTL_FILE"
    fi
    sysctl -q -w net.ipv4.ip_forward=0
    ok "net.ipv4.ip_forward=0"
    if ! ufw status 2>/dev/null | grep -q 'Status: active'; then
        iptables -P FORWARD ACCEPT
        info "Política de FORWARD vuelta a ACCEPT (valor por defecto de Ubuntu)."
    fi
    mostrar_estado
    resumen_final "NAT revertida"
    exit $?
fi

# ---------------------------------------------------------------- aplicar
paso "1. Comprobaciones previas"
command -v iptables >/dev/null || asegurar_paquetes iptables
info "iptables: $(iptables --version)"
IFACE="$(interfaz_salida)"
[[ -n "$IFACE" ]] || die "No hay ruta por defecto: esta EC2 no tiene salida. La NAT debe estar en la DMZ con IP pública y ruta 0.0.0.0/0 -> Internet Gateway."
ok "Interfaz de salida detectada: $IFACE ($(ip -o -4 addr show dev "$IFACE" | awk '{print $4}' | head -n1))"
for c in $NAT_SOURCE_CIDRS; do info "Subred que saldrá por la NAT: $c"; done
info "VPC (nunca se enmascara ni se reenvía entre subredes): $VPC_CIDR"

paso "2. IP forwarding persistente"
escribir_si_cambia "$SYSCTL_FILE" 644 <<'EOF'
# Fase 3 (Hospital) — NAT instance: reenviar paquetes entre la VPC e Internet.
# Generado por nat-instance.sh. Revertir: sudo bash nat-instance.sh --revertir
net.ipv4.ip_forward = 1
EOF
sysctl -q -p "$SYSCTL_FILE"
otros="$(grep -rlsE '^[[:space:]]*net\.ipv4\.ip_forward[[:space:]]*=[[:space:]]*0' /etc/sysctl.conf /etc/sysctl.d/ /usr/lib/sysctl.d/ /run/sysctl.d/ 2>/dev/null || true)"
if [[ -n "$otros" ]]; then
    aviso "Otro archivo pone ip_forward=0 y podría ganar al reiniciar: $otros"
fi
if [[ "$(sysctl -n net.ipv4.ip_forward)" == "1" ]]; then
    ok "net.ipv4.ip_forward = 1"
else
    falla "net.ipv4.ip_forward no quedó en 1"
fi

paso "3. Script de reglas y servicio systemd (persistencia)"
escribir_si_cambia "$REGLAS_BIN" 755 <<EOF
#!/usr/bin/env bash
# Generado por nat-instance.sh (Fase 3). No editar: volver a correr nat-instance.sh.
# Uso: fase3-nat-reglas start|stop   (lo llama el servicio fase3-nat)
set -euo pipefail
VPC_CIDR="${VPC_CIDR}"
ORIGENES="${NAT_SOURCE_CIDRS}"
CADENA="${CADENA}"
COMENTARIO="fase3-nat"

iface() {
    ip -o -4 route show to default | awk '{for (k=1;k<NF;k++) if (\$k=="dev") {print \$(k+1); exit}}'
}

quitar_masquerade() {
    # "|| true": la primera vez no hay reglas previas y grep devuelve 1 (con pipefail abortaría).
    iptables -t nat -S POSTROUTING | { grep -- "--comment \$COMENTARIO" || true; } | sed 's/^-A /-D /' |
        while read -r regla; do eval "iptables -t nat \$regla"; done
}

case "\${1:-start}" in
start)
    IF="\$(iface)"
    [[ -n "\$IF" ]] || { echo "fase3-nat: no hay ruta por defecto" >&2; exit 1; }
    iptables -N "\$CADENA" 2>/dev/null || true
    iptables -F "\$CADENA"
    quitar_masquerade
    for o in \$ORIGENES; do
        iptables -A "\$CADENA" -s "\$o" ! -d "\$VPC_CIDR" -o "\$IF" -j ACCEPT
        iptables -A "\$CADENA" -d "\$o" -i "\$IF" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
        iptables -t nat -A POSTROUTING -s "\$o" ! -d "\$VPC_CIDR" -o "\$IF" \\
            -m comment --comment "\$COMENTARIO" -j MASQUERADE
    done
    while iptables -D FORWARD -j "\$CADENA" 2>/dev/null; do :; done
    iptables -I FORWARD 1 -j "\$CADENA"
    iptables -P FORWARD DROP
    echo "fase3-nat: NAT activa por \$IF para: \$ORIGENES"
    ;;
stop)
    while iptables -D FORWARD -j "\$CADENA" 2>/dev/null; do :; done
    iptables -F "\$CADENA" 2>/dev/null || true
    iptables -X "\$CADENA" 2>/dev/null || true
    quitar_masquerade
    echo "fase3-nat: reglas quitadas"
    ;;
*) echo "uso: \$0 start|stop" >&2; exit 2 ;;
esac
EOF

escribir_si_cambia "$UNIDAD" 644 <<EOF
[Unit]
Description=Fase 3 (Hospital): reglas de NAT instance (MASQUERADE + FORWARD)
After=network-online.target ufw.service
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=${REGLAS_BIN} start
ExecStop=${REGLAS_BIN} stop

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable fase3-nat.service >/dev/null 2>&1
systemctl restart fase3-nat.service || die "El servicio fase3-nat falló: journalctl -u fase3-nat -n 20"
ok "Servicio fase3-nat activo y habilitado al arranque"

if ufw status 2>/dev/null | grep -q 'Status: active'; then
    info "ufw está activo: filtra la entrada; la NAT la gestiona fase3-nat (cadena $CADENA al inicio de FORWARD)."
fi

paso "4. Verificación"
mostrar_estado
if iptables -t nat -S POSTROUTING | grep -q -- '--comment fase3-nat'; then
    ok "Regla MASQUERADE presente"
else
    falla "No se encontró la regla MASQUERADE"
fi
if iptables -S FORWARD | sed -n '2p' | grep -q -- "-j $CADENA"; then
    ok "La cadena $CADENA es la primera regla de FORWARD"
else
    falla "La cadena $CADENA no está al inicio de FORWARD"
fi
if [[ "$(systemctl is-active fase3-nat.service)" == "active" ]]; then
    ok "fase3-nat activo"
else
    falla "fase3-nat no está activo"
fi

info "Probando salida a Internet desde la propia NAT (${INTERNET_TEST_URL})..."
codigo="$(curl -sS -m 8 -o /dev/null -w '%{http_code}' "$INTERNET_TEST_URL" 2>/dev/null || true)"
if [[ "$codigo" =~ ^[23] ]]; then
    ok "La NAT tiene Internet (HTTP $codigo)"
else
    falla "La NAT no tiene salida a Internet (código '${codigo:-ninguno}'). Revisar: IP pública/Elastic IP asociada, Internet Gateway, ruta 0.0.0.0/0 -> IGW en Hospital-RT-Publica, SG de salida."
fi

paso "Pendiente en la consola de AWS (no lo hace este script)"
cat <<EOF | tee -a "${EVIDENCIA}"
    1. EC2 NAT -> Acciones -> Redes -> Cambiar comprobación de origen/destino -> DESACTIVAR
       (sin esto AWS descarta el tráfico reenviado).
    2. La NAT con IP pública (Elastic IP) en la DMZ; Hospital-RT-Publica con 0.0.0.0/0 -> IGW.
    3. Tablas privadas (Hospital-RT-Privada): 0.0.0.0/0 -> la ENI/instancia NAT.
    4. SG de la NAT: entrada solo desde ${VPC_CIDR} (y SSH desde la subred TI);
       NADA iniciado desde Internet. Salida: todo.
    5. NACL de la DMZ y de las subredes privadas: permitir la salida y los puertos efímeros
       (1024-65535) de retorno.
    Prueba desde una privada:  curl -sS -m 8 -o /dev/null -w '%{http_code}\n' ${INTERNET_TEST_URL}
EOF

resumen_final "NAT instance configurada en $(hostname)"
