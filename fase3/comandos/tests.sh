# Se antepone por PowerShell: ORIGEN=<ti|servidores|medicos|visitantes>
cd ~/fase3/leonardo
export FASE3_EVID_DIR=$HOME/fase3/evidencias
rm -f "$FASE3_EVID_DIR/resultados-${ORIGEN}-$(date +%F).csv"
bash tests_fase3.sh "$ORIGEN" 2>&1 | sed 's/\x1b\[[0-9;]*m//g'
echo
echo "######## Pruebas complementarias (MATRIZ-E4.2 §4 y E8.x)"
CSV="$FASE3_EVID_DIR/resultados-${ORIGEN}-$(date +%F).csv"
tcp() {  # id destino ip puerto esperado
  local rc=0; timeout 5 bash -c "exec 3<>/dev/tcp/$3/$4" 2>/dev/null || rc=$?
  local obt est; if ((rc==0)); then est=conecta; obt=conectado; elif ((rc==124)); then est=bloq; obt="timeout 5s"; else est=otro; obt="rc=$rc"; fi
  local res=FAIL; { [[ $5 == permitido && $est == conecta ]] || [[ $5 == bloqueado && $est == bloq ]]; } && res=PASS
  printf '%-7s %-26s TCP/%-5s %-10s %-5s %s\n' "$1" "$2 ($3)" "$4" "$5" "$res" "$obt"
  printf '%s,%s,%s (%s),TCP/%s,%s,%s,%s\n' "$(date '+%F %T')" "$ORIGEN" "$2" "$3" "$4" "$5" "$obt" "$res" >> "$CSV"
}
http() {  # id ruta esperado-codigo
  local code; code="$(curl -s -m 5 -o /dev/null -w '%{http_code}' "http://10.0.0.46$2")"
  local res=FAIL; [[ "$code" == "$3" ]] && res=PASS
  printf '%-7s %-26s HTTP/80   %-10s %-5s HTTP %s\n' "$1" "servidores $2" "$3" "$res" "$code"
  printf '%s,%s,servidores (10.0.0.46) %s,HTTP/80,HTTP %s,HTTP %s,%s\n' "$(date '+%F %T')" "$ORIGEN" "$2" "$3" "$code" "$res" >> "$CSV"
}
case "$ORIGEN" in
  medicos)
    tcp MED-06 servidores 10.0.0.46 22 bloqueado
    tcp MED-07 visitantes 10.0.0.69 22 bloqueado
    http MED-08 /intranet/ 401
    http MED-09 /intranet/ti/ 401
    code="$(curl -s -m 8 -o /dev/null -w '%{http_code}' https://example.com)"; r=FAIL; [[ $code == 200 ]] && r=PASS
    echo "MED-10  Internet https://example.com  HTTPS     permitido  $r HTTP $code"
    echo "$(date '+%F %T'),medicos,internet (example.com),HTTPS/443,permitido,HTTP $code,$r" >> "$CSV" ;;
  ti)
    code="$(curl -s -m 8 -o /dev/null -w '%{http_code}' https://example.com)"; r=FAIL; [[ $code == 200 ]] && r=PASS
    echo "TI-09   Internet https://example.com  HTTPS     permitido  $r HTTP $code"
    echo "$(date '+%F %T'),ti,internet (example.com),HTTPS/443,permitido,HTTP $code,$r" >> "$CSV"
    http TI-10 /intranet/ 401
    tcp TI-11 medicos 10.0.0.28 22 permitido ;;
  visitantes)
    tcp VIS-14 servidores 10.0.0.46 80 bloqueado
    tcp VIS-15 servidores 10.0.0.46 389 bloqueado
    echo "Salida pública vista desde Visitantes (IP del NAT, no se publica en el informe):"; curl -s -m 8 https://checkip.amazonaws.com >/dev/null && echo "  obtenida (oculta)" ;;
esac
echo; echo "CSV: $CSV"; echo "Totales CSV: PASS=$(grep -c ',PASS$' "$CSV") FAIL=$(grep -c ',FAIL$' "$CSV")"
