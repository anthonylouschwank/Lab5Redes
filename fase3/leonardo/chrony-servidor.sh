#!/usr/bin/env bash
# chrony-servidor.sh — Servidor NTP interno del Hospital con chrony (Fase 3).
#
# Dónde: Hospital-EC2-Servidores (10.0.0.46). Va PRIMERO en el orden de Servidores
#        (chrony -> LDAP -> Apache -> hardening -> pruebas).
# Uso:
#   sudo bash chrony-servidor.sh              # aplicar (idempotente)
#   sudo bash chrony-servidor.sh --estado     # solo inspeccionar
#   sudo bash chrony-servidor.sh --revertir   # quitar la configuración de la Fase 3
#
# Qué hace:
#   1. Inspecciona lo que ya hay (las AMI de Ubuntu en AWS suelen traer chrony contra
#      Amazon Time Sync): fuentes, tracking, chrony.conf, conf.d y sources.d.
#   2. Escribe /etc/chrony/conf.d/fase3-servidor.conf con:
#        server <NTP_UPSTREAM> prefer iburst minpoll 4 maxpoll 4   (si no estaba ya)
#        allow <NTP_ALLOW_CIDRS>            -> los clientes de la VPC pueden consultarlo
#        local stratum <NTP_LOCAL_STRATUM>  -> sigue sirviendo hora si pierde el upstream
#   3. Reinicia chrony y verifica: fuente ^*, Leap status Normal, escucha en UDP 123.
# No toca el Security Group: UDP 123 de entrada en SG-Servidores lo pone Anthony.
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"

CONF=/etc/chrony/conf.d/fase3-servidor.conf
CHRONY_CONF=/etc/chrony/chrony.conf

modo="aplicar"
case "${1:-}" in
    "") ;;
    --estado) modo="estado" ;;
    --revertir) modo="revertir" ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) die "Opción desconocida: $1" ;;
esac

require_root
cargar_env
iniciar_evidencia "chrony-servidor.sh" "$modo"
revisar_ubuntu

if [[ "$modo" == "revertir" ]]; then
    paso "Revirtiendo el servidor NTP de la Fase 3"
    if [[ -f "$CONF" ]]; then
        respaldar "$CONF"; rm -f "$CONF"
        systemctl restart chrony
        ok "Quitado $CONF y chrony reiniciado (vuelve a su configuración original)"
    else
        info "No había configuración de la Fase 3 ($CONF)"
    fi
    chrony_estado
    resumen_final "servidor NTP revertido"
    exit $?
fi

paso "1. Inspección previa (no cambia nada)"
if dpkg-query -W -f='${Status}' chrony 2>/dev/null | grep -q 'install ok installed'; then
    ok "chrony instalado: $(chronyd -v 2>/dev/null | head -n1)"
    chrony_estado
else
    info "chrony no está instalado (¿usa systemd-timesyncd?):"
    mostrar "timedatectl" timedatectl show -p NTPSynchronized -p NTP
fi
if [[ -f "$CHRONY_CONF" ]]; then
    mostrar "líneas activas de $CHRONY_CONF" grep -vE '^[[:space:]]*(#|$)' "$CHRONY_CONF"
fi
mostrar "/etc/chrony/conf.d y sources.d" sh -c 'ls -l /etc/chrony/conf.d /etc/chrony/sources.d 2>&1; grep -HvE "^[[:space:]]*(#|$)" /etc/chrony/conf.d/* /etc/chrony/sources.d/* 2>/dev/null'

if [[ "$modo" == "estado" ]]; then
    resumen_final "inspección del servidor NTP"
    exit $?
fi

paso "2. chrony instalado"
asegurar_paquetes chrony
if ! grep -qE '^[[:space:]]*confdir[[:space:]]+/etc/chrony/conf\.d' "$CHRONY_CONF"; then
    respaldar "$CHRONY_CONF"
    printf '\n# Fase 3: cargar /etc/chrony/conf.d\nconfdir /etc/chrony/conf.d\n' >> "$CHRONY_CONF"
    ok "Agregado 'confdir /etc/chrony/conf.d' a $CHRONY_CONF"
fi

paso "3. Configuración del servidor NTP interno"
# ¿El upstream ya está declarado en otra parte (AMI de AWS)? Entonces no se duplica.
upstream_re="${NTP_UPSTREAM//./\\.}"
ya_declarado="$(grep -lsE "^[[:space:]]*(server|pool)[[:space:]]+${upstream_re}([[:space:]]|$)" \
    "$CHRONY_CONF" /etc/chrony/conf.d/*.conf /etc/chrony/sources.d/*.sources 2>/dev/null | grep -v "^${CONF}$" || true)"
{
    echo "# Fase 3 (Hospital) — servidor NTP interno. Generado por chrony-servidor.sh."
    echo "# Revertir: sudo bash chrony-servidor.sh --revertir"
    if [[ -n "$ya_declarado" ]]; then
        echo "# Upstream ${NTP_UPSTREAM} ya declarado en: $(echo "$ya_declarado" | tr '\n' ' ')"
    else
        echo "server ${NTP_UPSTREAM} prefer iburst minpoll 4 maxpoll 4"
    fi
    for c in $NTP_ALLOW_CIDRS; do echo "allow ${c}"; done
    if [[ -n "$NTP_LOCAL_STRATUM" ]]; then
        echo "# Si se pierde el upstream, seguir sirviendo la hora local con estrato alto"
        echo "local stratum ${NTP_LOCAL_STRATUM}"
    fi
} | escribir_si_cambia "$CONF" 644
if [[ -n "$ya_declarado" ]]; then
    info "El upstream ${NTP_UPSTREAM} ya estaba en: $ya_declarado (no se duplica)"
fi

if ! chronyd -p >/dev/null 2>&1; then
    die "La configuración de chrony no es válida (chronyd -p). Revisa $CONF"
fi
ok "Configuración válida (chronyd -p)"

paso "4. Reinicio y verificación"
systemctl enable chrony >/dev/null 2>&1 || true
systemctl restart chrony
sleep 2
info "Esperando a que chrony seleccione ${NTP_UPSTREAM} (máx. 90 s)..."
if chrony_esperar "$NTP_UPSTREAM" 90; then
    ok "Sincronizado con ${NTP_UPSTREAM} (marca ^*)"
else
    rx="$(chrony_rx "$NTP_UPSTREAM")"
    if [[ "${rx:-0}" == "0" ]]; then
        falla "${NTP_UPSTREAM} no responde (0 paquetes recibidos)."
        info "En AWS: Amazon Time Sync (169.254.169.123) es link-local y no necesita Internet ni NAT."
        info "Revisar: que sea una EC2 (no funciona fuera de AWS) y las reglas de SALIDA del SG"
        info "(SG-Servidores no tiene reglas de salida; ver README, 'Pendiente de confirmar en AWS')."
    else
        falla "${NTP_UPSTREAM} responde (${rx} paquetes) pero aún no está seleccionado; espera y repite --estado."
    fi
    if [[ -n "$NTP_LOCAL_STRATUM" ]]; then
        aviso "Mientras tanto el servidor sirve su hora local con estrato ${NTP_LOCAL_STRATUM} (los clientes igual sincronizan)."
    fi
fi
chrony_estado
mostrar "ss -ulnp (UDP 123)" ss -ulnp 'sport = :123'
if ss -ulnH 'sport = :123' | grep -q .; then
    ok "chronyd escucha en UDP 123 (sirve hora a: ${NTP_ALLOW_CIDRS})"
else
    falla "chronyd no escucha en UDP 123 (¿falta 'allow' en la configuración?)"
fi
leap="$({ chronyc tracking 2>/dev/null || true; } | awk -F': ' '/^Leap status/ {print $2}')"
if [[ "$leap" == "Normal" ]]; then
    ok "Leap status: Normal"
else
    falla "Leap status: ${leap:-desconocido} (aún no sincroniza)"
fi
if ufw status 2>/dev/null | grep -q 'Status: active' && ! ufw status | grep -qE '^123/udp'; then
    aviso "ufw está activo y no permite 123/udp: los clientes no llegarán (lo agrega hardening.sh servidores)."
fi

paso "Pendiente fuera de este script"
info "SG-Servidores: entrada UDP 123 desde ${NTP_ALLOW_CIDRS} (Anthony)."
info "Luego, en cada cliente: sudo bash chrony-cliente.sh"

resumen_final "servidor NTP en $(hostname)"
