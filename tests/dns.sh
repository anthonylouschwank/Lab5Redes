#!/usr/bin/env bash
# Matriz de pruebas DNS (DNS-01 a DNS-05) más validación de zonas y resolución inversa.
# Uso (en la VM): bash tests/dns.sh
set -uo pipefail
source "$(dirname "$0")/lib.sh"

NS="ns1.${DOMAIN}"

prueba DNS-00 "Validación de zonas con named-checkzone" \
    "named-checkzone ${DOMAIN} /etc/bind/zones/db.hospital.redes.test && named-checkzone 0.0.10.in-addr.arpa /etc/bind/zones/db.10.0.0" \
    "grep -c '^OK' | grep -qx 2"

prueba DNS-01 "Resolución del servidor DNS (ns1)" \
    "dig @${NS} ${NS} A" \
    "grep -qE '^ns1\.${D_RE}\.\s+[0-9]+\s+IN\s+A\s+${IP_RE}$'"

prueba DNS-02 "Resolución de ldap, www, mail y ftp" \
    "for n in ldap www mail ftp; do dig @${NS} +noall +answer \$n.${DOMAIN} A; done" \
    "grep -cE '\sIN\s+A\s+${IP_RE}$' | grep -qx 4"

prueba DNS-03 "Consulta SOA (respuesta autoritativa)" \
    "dig @${NS} ${DOMAIN} SOA" \
    "grep -qE 'flags:[^;]*\baa\b' && grep -qE '\sIN\s+SOA\s+ns1\.'"

prueba DNS-03b "Consulta NS de la zona" \
    "dig @${NS} ${DOMAIN} NS" \
    "grep -qE '\sIN\s+NS\s+ns1\.${D_RE}\.'"

prueba DNS-04 "Consulta MX (servidor de correo)" \
    "dig @${NS} ${DOMAIN} MX" \
    "grep -qE '\sIN\s+MX\s+10\s+mail\.${D_RE}\.'"

prueba DNS-05 "Nombre inexistente responde NXDOMAIN" \
    "dig @${NS} noexiste.${DOMAIN} A" \
    "grep -q 'status: NXDOMAIN' && grep -qE 'flags:[^;]*\baa\b'"

prueba DNS-06 "Resolución inversa (PTR) de ${SERVER_IP}" \
    "dig @${NS} -x ${SERVER_IP}" \
    "grep -qE '\sIN\s+PTR\s+srv\.${D_RE}\.'"
