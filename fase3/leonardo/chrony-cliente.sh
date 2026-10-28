#!/usr/bin/env bash
# chrony-cliente.sh — Cliente NTP que usa el servidor interno del Hospital (Fase 3).
#
# Dónde: TI, Médicos, Visitantes, DMZ/NAT… (todo lo que no sea Servidores).
#        Requisito: chrony-servidor.sh ya corrió en 10.0.0.46 y el SG-Servidores
#        permite UDP 123 desde la subred de este equipo.
# Uso:
#   sudo bash chrony-cliente.sh              # aplicar (idempotente)
#   sudo bash chrony-cliente.sh --estado     # solo inspeccionar
#   sudo bash chrony-cliente.sh --revertir   # volver a las fuentes originales
#
# Qué hace:
#   1. Inspecciona chrony (fuentes, tracking, configuración).
#   2. /etc/chrony/conf.d/fase3-cliente.conf:  server <NTP_SERVER> iburst prefer
#      (+ Amazon Time Sync como respaldo si NTP_RESPALDO_AWS=si).
#   3. Si NTP_SOLO_INTERNO=si, comenta las demás fuentes (pool de Ubuntu, la de la AMI,
#      las de DHCP) para que la demo muestre que se usa el servidor interno. Respaldo previo.
#   4. Reinicia chrony, espera la marca ^* y, si no llega, explica la causa probable.
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"

CONF=/etc/chrony/conf.d/fase3-cliente.conf
CHRONY_CONF=/etc/chrony/chrony.conf
MARCA="#fase3# "

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
iniciar_evidencia "chrony-cliente.sh" "$modo"
revisar_ubuntu

# Archivos donde pueden estar declaradas otras fuentes.
archivos_fuentes() {
    printf '%s\n' "$CHRONY_CONF"
    find /etc/chrony/sources.d /etc/chrony/conf.d -maxdepth 1 -type f \( -name '*.sources' -o -name '*.conf' \) \
        ! -path "$CONF" 2>/dev/null | sort
}

if [[ "$modo" == "revertir" ]]; then
    paso "Revirtiendo el cliente NTP de la Fase 3"
    if [[ -f "$CONF" ]]; then respaldar "$CONF"; rm -f "$CONF"; ok "Quitado $CONF"; fi
    while read -r f; do
        if grep -q "^${MARCA}" "$f"; then
            respaldar "$f"
            sed -i "s/^${MARCA}//" "$f"
            ok "Fuentes reactivadas en $f"
        fi
    done < <(archivos_fuentes)
    systemctl restart chrony
    chrony_estado
    resumen_final "cliente NTP revertido"
    exit $?
fi

paso "1. Inspección previa (no cambia nada)"
if dpkg-query -W -f='${Status}' chrony 2>/dev/null | grep -q 'install ok installed'; then
    ok "chrony instalado: $(chronyd -v 2>/dev/null | head -n1)"
    chrony_estado
else
    info "chrony no está instalado."
fi
mostrar "fuentes declaradas" sh -c 'grep -HnE "^[[:space:]]*(server|pool|peer|sourcedir)[[:space:]]" /etc/chrony/chrony.conf /etc/chrony/conf.d/* /etc/chrony/sources.d/* 2>/dev/null'

if [[ "$modo" == "estado" ]]; then
    resumen_final "inspección del cliente NTP"
    exit $?
fi

paso "2. chrony instalado"
asegurar_paquetes chrony
if ! grep -qE '^[[:space:]]*confdir[[:space:]]+/etc/chrony/conf\.d' "$CHRONY_CONF"; then
    respaldar "$CHRONY_CONF"
    printf '\n# Fase 3: cargar /etc/chrony/conf.d\nconfdir /etc/chrony/conf.d\n' >> "$CHRONY_CONF"
    ok "Agregado 'confdir /etc/chrony/conf.d' a $CHRONY_CONF"
fi

paso "3. Servidor interno ${NTP_SERVER}"
{
    echo "# Fase 3 (Hospital) — cliente del NTP interno. Generado por chrony-cliente.sh."
    echo "# Revertir: sudo bash chrony-cliente.sh --revertir"
    echo "server ${NTP_SERVER} iburst prefer"
    if [[ "$NTP_RESPALDO_AWS" == "si" ]]; then
        echo "# Respaldo: Amazon Time Sync (solo se usa si el interno falla)"
        echo "server ${NTP_UPSTREAM} iburst"
    fi
} | escribir_si_cambia "$CONF" 644

if [[ "$NTP_SOLO_INTERNO" == "si" ]]; then
    info "NTP_SOLO_INTERNO=si: se comentan las demás fuentes (quedan con la marca '${MARCA}')."
    while read -r f; do
        # Líneas activas de fuentes que no apuntan al servidor interno.
        if grep -qE "^[[:space:]]*(server|pool|peer|sourcedir)[[:space:]]" "$f" &&
           grep -E "^[[:space:]]*(server|pool|peer|sourcedir)[[:space:]]" "$f" | grep -qvF "$NTP_SERVER"; then
            respaldar "$f"
            awk -v m="$MARCA" -v ip="$NTP_SERVER" '
                /^[[:space:]]*(server|pool|peer|sourcedir)[[:space:]]/ && index($0, ip) == 0 { print m $0; next }
                { print }' "$f" > "$f.tmp.fase3"
            cat "$f.tmp.fase3" > "$f"; rm -f "$f.tmp.fase3"
            ok "Fuentes externas comentadas en $f"
        fi
    done < <(archivos_fuentes)
else
    info "NTP_SOLO_INTERNO=no: se conservan las demás fuentes; ${NTP_SERVER} va con 'prefer'."
fi

chronyd -p >/dev/null 2>&1 || die "La configuración de chrony no es válida (chronyd -p)."
ok "Configuración válida (chronyd -p)"

paso "4. Reinicio y verificación"
systemctl enable chrony >/dev/null 2>&1 || true
systemctl restart chrony
sleep 2
info "Esperando a que chrony seleccione ${NTP_SERVER} (máx. 90 s)..."
if chrony_esperar "$NTP_SERVER" 90; then
    ok "Sincronizado con el servidor interno ${NTP_SERVER} (marca ^*)"
else
    rx="$(chrony_rx "$NTP_SERVER")"
    if [[ "${rx:-0}" == "0" ]]; then
        falla "${NTP_SERVER} no responde por UDP 123 (0 paquetes recibidos). Causas probables, en orden:"
        info "  1. SG-Servidores sin entrada UDP 123 desde la subred de este equipo."
        info "  2. NACL de esta subred o de Servidores: UDP 123 de ida y puertos efímeros de vuelta."
        info "  3. chrony-servidor.sh no corrió o su 'allow' no incluye esta subred."
        info "  4. ufw en Servidores sin 123/udp (hardening.sh servidores lo abre)."
        info "Comprobar en el servidor: sudo chronyc clients   (¿aparece la IP de este equipo?)"
    else
        falla "${NTP_SERVER} responde (${rx} paquetes) pero aún no está seleccionado; espera 1-2 min y repite: sudo bash chrony-cliente.sh --estado"
    fi
fi
chrony_estado
mostrar "chronyc ntpdata ${NTP_SERVER}" sh -c "chronyc -n ntpdata ${NTP_SERVER} | grep -E 'Remote address|Stratum|Total TX|Total RX|Total valid RX'"
leap="$({ chronyc tracking 2>/dev/null || true; } | awk -F': ' '/^Leap status/ {print $2}')"
if [[ "$leap" == "Normal" ]]; then ok "Leap status: Normal"; else falla "Leap status: ${leap:-desconocido}"; fi
ntpsync="$(timedatectl show -p NTPSynchronized --value 2>/dev/null || true)"
if [[ "$ntpsync" == "yes" ]]; then ok "timedatectl NTPSynchronized=yes"; else aviso "timedatectl NTPSynchronized=${ntpsync:-?} (puede tardar un poco más que chrony)"; fi

resumen_final "cliente NTP de ${NTP_SERVER} en $(hostname)"
