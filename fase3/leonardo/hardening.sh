#!/usr/bin/env bash
# hardening.sh — Cierra los puertos que no se usan y endurece SSH (Fase 3, Hospital).
#
# Uso:  sudo bash hardening.sh <ti|servidores|nat|cliente>
#       sudo bash hardening.sh --revertir
# Va AL FINAL en cada EC2 (después de instalar sus servicios), y siempre desde una sesión
# por el EC2 Instance Connect Endpoint con OTRA sesión lista para probar el acceso.
#
# Qué hace:
#   1. Inventario ANTES: ss -tulnp -> hardening-antes-<host>.txt
#   2. SSH: /etc/ssh/sshd_config.d/01-fase3-hardening.conf
#        PasswordAuthentication no · PermitRootLogin no · X11Forwarding no
#      (01- porque en sshd gana el PRIMER valor leído: un 99- quedaría tapado por
#       50-cloud-init.conf). Se valida con 'sshd -t' antes de recargar.
#   3. ufw: deny incoming, allow outgoing, deny routed + solo los puertos del rol:
#        ti / cliente: 22 desde SSH_ALLOW_CIDRS (subred TI: ahí está el endpoint 10.0.0.122)
#        servidores:   22 + LDAP desde LDAP_ALLOW_CIDRS + intranet desde INTRANET_ALLOW_CIDRS
#                      (nunca Visitantes) + UDP 123 desde NTP_ALLOW_CIDRS
#        nat:          22; el reenvío lo gestiona fase3-nat (nat-instance.sh), no ufw
#   4. SEGURO ANTI-LOCKOUT: antes de activar nada programa
#        systemd-run --on-active=<HARDENING_ROLLBACK_SEG> --unit=ufw-rollback ...
#      que desactiva ufw y quita el drop-in de SSH. Solo se cancela si confirmas (SI) que
#      sigues entrando por el endpoint desde otra sesión. Si no confirmas, se revierte solo.
#   5. Servicios innecesarios: deshabilita (con confirmación) los de SERVICIOS_DESHABILITAR
#      que estén corriendo; el resto que no sea del rol solo se lista para revisar.
#   6. Inventario DESPUÉS, diferencias y justificación de cada puerto que queda abierto.
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"

DROPIN=/etc/ssh/sshd_config.d/01-fase3-hardening.conf
UNIDAD_ROLLBACK=ufw-rollback

rol="${1:-}"
case "$rol" in
    ti|servidores|nat|cliente|--revertir) ;;
    -h|--help|"") sed -n '2,8p' "$0"; [[ -n "$rol" ]] && exit 0; exit 2 ;;
    *) die "Rol desconocido: '$rol'. Usa: ti | servidores | nat | cliente | --revertir" ;;
esac

require_root
cargar_env
iniciar_evidencia "hardening.sh" "$rol"
revisar_ubuntu
host="$(hostname)"
DIR_EVID="${FASE3_EVID_DIR:-$PWD}"

recargar_ssh() {
    if systemctl is-active --quiet ssh.service; then
        systemctl reload ssh.service
    fi
    # Con ssh.socket (Ubuntu 24.04) las conexiones nuevas leen la configuración al conectar.
}

# ---------------------------------------------------------------- --revertir
if [[ "$rol" == "--revertir" ]]; then
    paso "Revirtiendo el hardening"
    systemctl stop "${UNIDAD_ROLLBACK}.timer" 2>/dev/null || true
    ufw --force disable >/dev/null && ok "ufw desactivado (las reglas quedan guardadas: 'ufw show added')"
    if [[ -f "$DROPIN" ]]; then
        respaldar "$DROPIN"; rm -f "$DROPIN"
        sshd -t && recargar_ssh
        ok "Quitado $DROPIN y SSH recargado"
    fi
    info "Servicios deshabilitados por este script (si hubo): ver $FASE3_REGISTRO_RESPALDOS y reactivar con 'systemctl enable --now <svc>'."
    resumen_final "hardening revertido"
    exit $?
fi

# ---------------------------------------------------------------- reglas por rol
# Cada regla: "proto|puerto|origen|motivo"
REGLAS=()
for c in $SSH_ALLOW_CIDRS; do REGLAS+=("tcp|22|$c|SSH de administración (endpoint en la subred TI)"); done
case "$rol" in
    servidores)
        for c in $LDAP_ALLOW_CIDRS; do REGLAS+=("tcp|$LDAP_PORT|$c|LDAP (Sebastián)"); done
        for p in $INTRANET_PORTS; do
            for c in $INTRANET_ALLOW_CIDRS; do
                [[ "$c" == "$SUBNET_VISITANTES" ]] && die "INTRANET_ALLOW_CIDRS incluye Visitantes ($c): la regla 4 lo prohíbe."
                REGLAS+=("tcp|$p|$c|Intranet (Isabella)")
            done
        done
        for c in $NTP_ALLOW_CIDRS; do REGLAS+=("udp|123|$c|NTP interno (chrony)"); done
        ;;
esac

# Motivo de cada puerto que puede quedar escuchando (para la justificación final).
motivo_puerto() {
    case "$1" in
        22) echo "SSH: administración por el endpoint (solo desde ${SSH_ALLOW_CIDRS})" ;;
        53) echo "systemd-resolved: resolvedor local (127.0.0.53/54), no expuesto" ;;
        68) echo "cliente DHCP de AWS (systemd-networkd)" ;;
        123) echo "chrony: servidor NTP interno (rol servidores)" ;;
        323) echo "chronyc: control local de chrony (solo 127.0.0.1/::1)" ;;
        "$LDAP_PORT") echo "LDAP (rol servidores)" ;;
        80|443) echo "intranet Apache (rol servidores)" ;;
        *) echo "REVISAR: no previsto para el rol '$rol'" ;;
    esac
}

inventario() {
    # proto  dirección:puerto  proceso   (sin pid, para que la comparación antes/después sea estable)
    ss -tulnpH 2>/dev/null | awk '{p=$7; sub(/^users:\(\("/, "", p); sub(/".*/, "", p); print $1, $5, (p == "" ? "-" : p)}' | sort -u
}

paso "1. Inventario ANTES"
asegurar_paquetes ufw
inventario > "$DIR_EVID/hardening-antes-${host}.txt"
ss -tulnp > "$DIR_EVID/hardening-antes-${host}-completo.txt"
mostrar "puertos en escucha (proto  dirección:puerto  proceso)" cat "$DIR_EVID/hardening-antes-${host}.txt"
mostrar "ufw antes" ufw status verbose
ufw_estaba_activo=no
ufw status | grep -q 'Status: active' && ufw_estaba_activo=si

paso "2. Revisión previa de seguridad"
# Orígenes de las sesiones SSH abiertas (sudo borra SSH_CONNECTION, por eso se mira con ss).
# Con el endpoint de AWS (Preserve client IP = No) el origen es la IP del endpoint, 10.0.0.122.
mapfile -t origenes_ssh < <({ ss -tnH state established '( sport = :22 )' 2>/dev/null || true; } |
    awk '{print $4}' | sed -E 's/^\[?(::ffff:)?([^]]*)\]?:[0-9]+$/\2/' | sort -u)
if ((${#origenes_ssh[@]} == 0)); then
    aviso "No hay sesiones SSH abiertas (¿consola?). Asegúrate de tener acceso por el endpoint."
else
    fuera=()
    for o in "${origenes_ssh[@]}"; do
        # shellcheck disable=SC2086  # SSH_ALLOW_CIDRS es una lista separada por espacios
        if python3 - "$o" $SSH_ALLOW_CIDRS <<'PY' 2>/dev/null
import ipaddress, sys
ip = ipaddress.ip_address(sys.argv[1])
sys.exit(0 if any(ip in ipaddress.ip_network(c, strict=False) for c in sys.argv[2:]) else 1)
PY
        then ok "Sesión SSH desde $o: permitida por SSH_ALLOW_CIDRS (${SSH_ALLOW_CIDRS})"
        else fuera+=("$o"); aviso "Sesión SSH desde $o: NO está en SSH_ALLOW_CIDRS (${SSH_ALLOW_CIDRS})"
        fi
    done
    if ((${#fuera[@]} == ${#origenes_ssh[@]})); then
        aviso "Ninguna sesión abierta viene de un origen permitido: después del cambio no podrás abrir sesiones NUEVAS."
        confirmar "¿Seguir de todos modos? (el seguro anti-lockout revertirá en ${HARDENING_ROLLBACK_SEG}s si no confirmas acceso)" 60 \
            || die "Cancelado por seguridad: no se cambió nada. Ajusta SSH_ALLOW_CIDRS en fase3.env."
    fi
fi
if [[ "$rol" == "nat" ]] && ! systemctl is-active --quiet fase3-nat.service; then
    aviso "fase3-nat no está activo: corre primero nat-instance.sh."
fi

paso "3. Seguro anti-lockout (rollback automático en ${HARDENING_ROLLBACK_SEG}s)"
systemctl stop "${UNIDAD_ROLLBACK}.timer" "${UNIDAD_ROLLBACK}.service" 2>/dev/null || true
systemctl reset-failed "${UNIDAD_ROLLBACK}.service" 2>/dev/null || true
rollback_cmd="/usr/sbin/ufw --force disable; [ -f ${DROPIN} ] && mv -f ${DROPIN} ${DROPIN}.rollback; systemctl reload ssh.service 2>/dev/null; true"
if [[ "$ufw_estaba_activo" == "si" ]]; then
    aviso "ufw ya estaba activo: el rollback lo DESACTIVA (queda más abierto que antes, pero no te deja fuera)."
fi
systemd-run --quiet --unit="$UNIDAD_ROLLBACK" --on-active="${HARDENING_ROLLBACK_SEG}" \
    --description="Fase 3: rollback de hardening.sh" /bin/sh -c "$rollback_cmd" \
    || die "No se pudo programar el rollback (systemd-run). No se aplica nada."
ok "Rollback programado: ${UNIDAD_ROLLBACK}.timer (se ejecuta en ${HARDENING_ROLLBACK_SEG}s si no lo cancelas)"

paso "4. SSH endurecido"
escribir_si_cambia "$DROPIN" 644 <<'EOF'
# Fase 3 (Hospital) — hardening de SSH. Generado por hardening.sh.
# Nombre 01-: en sshd gana el primer valor leído y los drop-in se leen en orden alfabético.
# Revertir: sudo bash hardening.sh --revertir
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
X11Forwarding no
EOF
if ! sshd -t 2>/tmp/fase3-sshd-t.err; then
    cat /tmp/fase3-sshd-t.err >&2
    rm -f "$DROPIN"
    systemctl stop "${UNIDAD_ROLLBACK}.timer" 2>/dev/null || true
    die "sshd -t rechazó la configuración: se quitó el drop-in y no se cambió nada."
fi
ok "sshd -t: configuración válida"
recargar_ssh
efectivo="$({ sshd -T 2>/dev/null || true; } | grep -E '^(passwordauthentication|permitrootlogin|x11forwarding|kbdinteractiveauthentication) ' | sort || true)"
mostrar "valores efectivos (sshd -T)" printf '%s\n' "$efectivo"
for esperado in "passwordauthentication no" "permitrootlogin no" "x11forwarding no"; do
    if grep -qx "$esperado" <<<"$efectivo"; then ok "$esperado"; else falla "No quedó efectivo: $esperado"; fi
done
mostrar "ssh.service / ssh.socket" systemctl is-active ssh.service ssh.socket

paso "5. Firewall (ufw) — rol: $rol"
ufw default deny incoming >/dev/null
ufw default allow outgoing >/dev/null
ufw default deny routed >/dev/null
for r in "${REGLAS[@]}"; do
    IFS='|' read -r proto puerto origen motivo <<<"$r"
    ufw allow proto "$proto" from "$origen" to any port "$puerto" comment "fase3: $motivo" >/dev/null
    info "permitir $proto/$puerto desde $origen  ($motivo)"
done
# Reglas que existían antes y no son de la Fase 3: se avisan, no se borran.
extra="$(ufw show added 2>/dev/null | grep '^ufw ' | grep -v 'fase3: ' || true)"
if [[ -n "$extra" ]]; then
    aviso "Hay reglas de ufw que no son de la Fase 3 (revísalas; borrar con 'ufw delete <regla>'):"
    printf '%s\n' "$extra" | sed 's/^/        /' >&2
fi
ufw --force enable >/dev/null
ok "ufw activo"
if [[ "$rol" == "nat" ]] && systemctl is-enabled --quiet fase3-nat.service 2>/dev/null; then
    systemctl restart fase3-nat.service
    ok "fase3-nat reiniciado (su cadena vuelve a quedar al inicio de FORWARD)"
fi
mostrar "ufw status verbose" ufw status verbose

paso "6. Confirmación de acceso"
cat <<EOF
    AHORA, sin cerrar esta sesión, abre OTRA terminal y conéctate a esta EC2 por el endpoint:
        aws ec2-instance-connect ssh --instance-id <id-de-esta-EC2> --connection-type eice
    Si entras, vuelve aquí y escribe SI.
    Si no entras (o no respondes), en ${HARDENING_ROLLBACK_SEG}s se desactiva ufw y se quita el
    drop-in de SSH automáticamente.
EOF
if confirmar "¿Entraste por el endpoint en otra sesión?" $((HARDENING_ROLLBACK_SEG - 30)); then
    systemctl stop "${UNIDAD_ROLLBACK}.timer" 2>/dev/null || true
    ok "Acceso confirmado: rollback cancelado"
    evid "    Acceso confirmado por ${SUDO_USER:-root} a las $(date '+%T')"
else
    falla "Acceso NO confirmado: el rollback se ejecutará solo (systemctl list-timers ${UNIDAD_ROLLBACK}.timer)."
fi

paso "7. Servicios en ejecución"
blanca_base='^(ssh|chrony|cron|dbus|rsyslog|systemd-.*|polkit|snapd|snap\..*|amazon-ssm-agent|ec2-instance-connect.*|getty@.*|serial-getty@.*|cloud-.*|networkd-dispatcher|unattended-upgrades|multipathd|irqbalance|udisks2|user@.*|ufw|acpid|atd|fwupd|packagekit|upower|apport|uuidd|nscd|nslcd|fase3-nat|containerd|iscsid|open-iscsi|ModemManager)$'
case "$rol" in
    servidores) blanca_rol='^(slapd|apache2|apache-htcacheclean|nslcd|chrony)$' ;;
    *)          blanca_rol='^$' ;;
esac
corriendo="$(systemctl list-units --type=service --state=running --no-legend --plain | awk '{print $1}' | sed 's/\.service$//' | sort)"
a_deshabilitar=()
for s in $SERVICIOS_DESHABILITAR; do
    if grep -qx "$s" <<<"$corriendo"; then a_deshabilitar+=("$s"); fi
done
if ((${#a_deshabilitar[@]} > 0)); then
    info "Corriendo y en la lista para deshabilitar: ${a_deshabilitar[*]}"
    if confirmar "¿Deshabilitar ${a_deshabilitar[*]}?" 60; then
        for s in "${a_deshabilitar[@]}"; do
            systemctl disable --now "$s" >/dev/null 2>&1 && ok "Deshabilitado: $s (revertir: systemctl enable --now $s)"
            printf '%s servicio deshabilitado: %s (revertir: systemctl enable --now %s)\n' "$(date '+%F %T')" "$s" "$s" >> "$FASE3_REGISTRO_RESPALDOS"
        done
    else
        info "No se deshabilitó ninguno."
    fi
else
    ok "Ninguno de la lista SERVICIOS_DESHABILITAR está corriendo"
fi
revisar=""
while read -r s; do
    [[ -z "$s" ]] && continue
    if ! grep -qE "$blanca_base" <<<"$s" && ! grep -qE "$blanca_rol" <<<"$s"; then revisar+="$s "; fi
done <<<"$corriendo"
if [[ -n "$revisar" ]]; then
    aviso "Servicios corriendo que no son del rol '$rol' (revisar a mano, no se tocaron): $revisar"
else
    ok "Todos los servicios en ejecución son esperables para el rol '$rol'"
fi

paso "8. Inventario DESPUÉS y justificación"
inventario > "$DIR_EVID/hardening-despues-${host}.txt"
ss -tulnp > "$DIR_EVID/hardening-despues-${host}-completo.txt"
mostrar "diferencias en puertos en escucha (- antes / + después)" \
    sh -c "diff -u '$DIR_EVID/hardening-antes-${host}.txt' '$DIR_EVID/hardening-despues-${host}.txt' | tail -n +3 || true"
info "Puertos en escucha y por qué se conservan (el acceso real lo limita ufw + SG/NACL):"
while read -r proto dir _; do
    puerto="${dir##*:}"
    local_only=""
    [[ "$dir" =~ ^(127\.|\[::1\]|::1) ]] && local_only=" [solo local]"
    printf '      %-4s %-28s %s%s\n' "$proto" "$dir" "$(motivo_puerto "$puerto")" "$local_only"
    evid "      $proto $dir $(motivo_puerto "$puerto")$local_only"
    if [[ -z "$local_only" && "$(motivo_puerto "$puerto")" == REVISAR* ]]; then
        aviso "Puerto $proto/$puerto expuesto y no previsto para el rol (ufw lo bloquea, pero conviene apagar el servicio)."
    fi
done < "$DIR_EVID/hardening-despues-${host}.txt"

paso "9. Servicios del rol siguen respondiendo"
case "$rol" in
    servidores)
        for s in chrony slapd apache2; do
            if systemctl is-active --quiet "$s"; then ok "$s activo"; else aviso "$s no está activo (¿aún no instalado?)"; fi
        done
        for p in "$LDAP_PORT" $INTRANET_PORTS; do
            if ss -tlnH "sport = :$p" | grep -q .; then ok "escuchando en TCP $p"; else aviso "nada escucha en TCP $p"; fi
        done
        if ss -ulnH 'sport = :123' | grep -q .; then ok "escuchando en UDP 123 (NTP)"; else aviso "nada escucha en UDP 123"; fi
        ;;
    nat)
        if systemctl is-active --quiet fase3-nat.service; then ok "fase3-nat activo"; else falla "fase3-nat no está activo"; fi
        ;;
esac
if [[ "$rol" != "servidores" ]] && systemctl is-active --quiet chrony; then ok "chrony activo"; fi
chown "${SUDO_USER:-root}": "$DIR_EVID"/hardening-*-"${host}"*.txt 2>/dev/null || true
info "Inventarios: $DIR_EVID/hardening-antes-${host}.txt y hardening-despues-${host}.txt"

resumen_final "hardening '$rol' en $host"
