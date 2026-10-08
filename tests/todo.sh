#!/usr/bin/env bash
# Ejecuta la matriz completa y genera tests/evidencias/MATRIZ.md a partir de resumen.tsv.
# Uso (en la VM): bash tests/todo.sh            (todas las pruebas, sin reinicio)
#                 bash tests/todo.sh --reinicio (además INT-02; correr tras "sudo reboot")
set -uo pipefail
cd "$(dirname "$0")"

for s in dns ldap web mail ftp integracion; do
    echo "===== ${s} ====="
    bash "${s}.sh"
done
[ "${1:-}" = "--reinicio" ] && { echo "===== reinicio ====="; bash reinicio.sh; }

source lib.sh
{
    echo "# Matriz de pruebas – resultados"
    echo
    echo "Generado en \`$(hostname -f)\` el $(date '+%F %T %Z'). Cada ID enlaza a su evidencia."
    echo
    echo "| ID | Resultado | Prueba | Fecha |"
    echo "|---|---|---|---|"
    tail -n +2 "$RESUMEN" | sort -t$'\t' -k1,1V | while IFS=$'\t' read -r id res desc fecha; do
        [ "$res" = "OK" ] && res="✅ OK" || res="❌ FALLA"
        echo "| [${id}](${id}.txt) | ${res} | ${desc} | ${fecha} |"
    done
    echo
    echo "**Total:** $(tail -n +2 "$RESUMEN" | grep -c $'\tOK\t') OK de $(tail -n +2 "$RESUMEN" | wc -l) pruebas."
} > "${EVID_DIR}/MATRIZ.md"

echo
tail -n 1 "${EVID_DIR}/MATRIZ.md"
