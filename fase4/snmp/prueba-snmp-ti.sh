#!/bin/bash
# Fase 4 · F6 — Pruebas SNMP desde TI (usa /root/.snmp/snmp.conf; sin credenciales en la línea de comandos).
# OID: sysName .1.3.6.1.2.1.1.5.0 · sysUpTime .1.3.6.1.2.1.1.3.0 · laLoad.1 .1.3.6.1.4.1.2021.10.1.3.1
#      memAvailReal .1.3.6.1.4.1.2021.4.6.0 · dskPercent.1 .1.3.6.1.4.1.2021.9.1.9.1 · ifNumber .1.3.6.1.2.1.2.1.0
echo "# Pruebas SNMP desde $(hostname) $(date -Is)"
echo "prueba,destino,esperado,obtenido,resultado"
F=0
for ip in 10.0.0.117 10.0.0.46 10.0.0.28 10.0.0.69 10.0.0.100; do
  out=$(sudo snmpget -m '' -O qv -t 2 -r 1 "$ip" .1.3.6.1.2.1.1.5.0 .1.3.6.1.2.1.1.3.0 .1.3.6.1.4.1.2021.10.1.3.1 .1.3.6.1.4.1.2021.4.6.0 .1.3.6.1.4.1.2021.9.1.9.1 .1.3.6.1.2.1.2.1.0 2>&1 | tr '\n' ' ')
  if [[ "$out" == *ip-10-0-0-* ]]; then r=PASS; else r=FAIL; F=$((F+1)); fi
  echo "v3-authPriv,$ip,responde,\"$out\",$r"
done
for ip in 10.0.0.46 10.0.0.100; do
  out=$(snmpget -m '' -v2c -c public -t 2 -r 0 "$ip" .1.3.6.1.2.1.1.5.0 2>&1 | head -1)
  if [[ "$out" == *Timeout* ]]; then r=PASS; else r=FAIL; F=$((F+1)); fi
  echo "v2c-public,$ip,rechazado,\"$out\",$r"
done
out=$(snmpget -m '' -v3 -l authPriv -u monitor -a SHA -A clave-incorrecta-123 -x AES -X clave-incorrecta-123 -t 2 -r 0 10.0.0.46 .1.3.6.1.2.1.1.5.0 2>&1 | head -1)
if [[ "$out" == *"Authentication failure"* || "$out" == *"Decryption error"* || "$out" == *Timeout* ]]; then r=PASS; else r=FAIL; F=$((F+1)); fi
echo "v3-clave-incorrecta,10.0.0.46,rechazado,\"$out\",$r"
out=$(snmpget -m '' -v3 -l noAuthNoPriv -u monitor -t 2 -r 0 10.0.0.46 .1.3.6.1.2.1.1.5.0 2>&1 | head -1)
if [[ "$out" != *ip-10-0-0-46* ]]; then r=PASS; else r=FAIL; F=$((F+1)); fi
echo "v3-noAuthNoPriv,10.0.0.46,rechazado,\"$out\",$r"
echo "# FAIL: $F"
