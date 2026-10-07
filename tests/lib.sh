#!/usr/bin/env bash
# Funciones comunes de la matriz de pruebas.
# Cada prueba guarda su evidencia en tests/evidencias/<ID>.txt y registra el resultado
# en tests/evidencias/resumen.tsv.

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EVID_DIR="${TESTS_DIR}/evidencias"
RESUMEN="${EVID_DIR}/resumen.tsv"
mkdir -p "$EVID_DIR"
source "${TESTS_DIR}/../lab.env"

# Versiones escapadas para usar en expresiones regulares
re() { sed 's/\./\\./g' <<<"$1"; }
D_RE="$(re "$DOMAIN")"
IP_RE="$(re "$SERVER_IP")"

# prueba <ID> <descripción> <comando> <verificación>
#   comando:      se ejecuta con bash -c; su salida (stdout+stderr) es la evidencia.
#   verificación: comando que recibe la salida por stdin; éxito = prueba OK.
prueba() {
    local id="$1" desc="$2" cmd="$3" check="$4"
    local f="${EVID_DIR}/${id}.txt" salida rc=0 res

    salida="$(bash -c "$cmd" 2>&1)" || rc=$?
    if printf '%s\n' "$salida" | bash -c "$check" >/dev/null 2>&1; then res="OK"; else res="FALLA"; fi

    {
        echo "# ${id} — ${desc}"
        echo "# Fecha: $(date '+%F %T %Z')   Equipo: $(hostname -f)"
        echo "# Resultado: ${res}"
        echo
        echo "\$ ${cmd}"
        printf '%s\n' "$salida"
        echo
        echo "# Código de salida: ${rc}"
    } > "$f"

    [ -f "$RESUMEN" ] || printf 'ID\tResultado\tPrueba\tFecha\n' > "$RESUMEN"
    sed -i "/^${id}\t/d" "$RESUMEN"
    printf '%s\t%s\t%s\t%s\n' "$id" "$res" "$desc" "$(date '+%F %T')" >> "$RESUMEN"

    printf '[%-5s] %-8s %s\n' "$res" "$id" "$desc"
}
