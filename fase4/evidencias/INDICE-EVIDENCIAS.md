# Índice de evidencias — Fase 4

**Validación:** **AWS** = ejecutado y verificado en la infraestructura AWS · **Internet** = probado desde una laptop fuera de la VPC.
Todas las salidas son de terminal salvo `F4.4_grafana-dashboard.png`. En los JSON se reemplazó el ID de cuenta por `<ACCOUNT_ID>`. Ningún archivo contiene contraseñas, claves privadas (WireGuard, TLS), credenciales SNMP, tokens ni la IP pública de la casa del administrador (los `endpoint` de `wg show` se omitieron). Se verificó por búsqueda de patrones el 08/11/2026.
Registro de cambios y reversión: [../CAMBIOS-Y-REVERSION.md](../CAMBIOS-Y-REVERSION.md) (D0–D28).

| ID | Archivo | Instancia / recurso | Fecha (UTC) | Comando o prueba | Resultado | Validación |
|---|---|---|---|---|---|---|
| F4.0 | `F4.0_estado-previo-{sg,nacl,rutas,instancias}.json` | VPC `vpc-07782d0d08628b4a5` | 2026-11-08 | `describe-*` | Estado anterior a la Fase 4 (respaldo para reversión) | AWS |
| F4.1 | `F4.1_sg-dmz-ingress.json` | SG-DMZ `sg-08da64aa3bd55a2fe` | 2026-11-08 | `create-security-group` + `authorize-security-group-ingress` | 80/443/51820 desde 0.0.0.0/0; 22 y 161 solo desde SG-TI | AWS |
| F4.1 | `F4.1_ec2-dmz.json` | `Hospital-EC2-DMZ` `i-01df9ec0d0856322c` | 2026-11-08 | `describe-instances` | t3.micro, 10.0.0.100, EIP 3.227.168.73, IMDSv2, source/dest check desactivado | AWS |
| F4.1 | `F4.1_rutas-posterior.json` | `Hospital-RT-Privada` | 2026-11-08 | `create-route` | `10.8.0.0/24 → eni-07f145d036f56a549` *active* (retorno VPN sin NAT) | AWS |
| F4.1 | `F4.1_sg-{servidores,medicos,visitantes,ti}-ingress-agregado.json` | SG de las 4 subredes | 2026-11-08 | `authorize-security-group-ingress` | 22 desde 10.8.0.2/32 (TI, Srv, Méd); 80 desde 10.8.0.0/24 (Srv); 161 desde SG-TI (Srv, Méd, Vis) | AWS |
| F4.1 | `F4.1_nacl-visitantes-posterior.json` | NACL Visitantes | 2026-11-08 | `create-network-acl-entry` 91 | 91 entrada UDP 161 desde TI y salida 1024-65535 a TI; 100/110 DENY intactas | AWS |
| F4.1 | `F4.1_ssh-eice-inventario-antes-{dmz,servidores}.txt` | DMZ, Servidores | 2026-11-08 | SSH por EICE + inventario | Acceso OK tras los cambios de red; puertos antes de la Fase 4 | AWS |
| F4.2 | `F4.2_instalar-web.txt` | DMZ · nginx + app de citas | 2026-11-08 | `fase4/web/deploy/instalar.sh` | gunicorn 127.0.0.1:8000, nginx :80, acceso por IP → 444 | AWS |
| F4.2 | `F4.2_certbot-y-renovacion.txt` | DMZ · TLS | 2026-11-08 | `certbot --nginx --redirect` + `renew --dry-run` | Let's Encrypt (YE2) hasta 2027-02-06; renovación simulada OK; `certbot.timer` activo | AWS |
| F4.2 | `F4.2_pruebas-web-laptop.txt` | `hospital-castillejos.duckdns.org` | 2026-11-08 | `curl`, `Test-NetConnection` | http 301 → https 200 (certificado válido), HSTS y cabeceras; crear cita 201 y consultar 200; 22/389 bloqueados | Internet |
| F4.3 | `F4.3_vpn-configuracion.txt` | DMZ, Servidores, TI, Médicos | 2026-11-08 | `wg-dmz.sh`, `vpn-servidores.sh`, `vpn-ssh-cliente.sh` | wg0 activo con 2 peers; WG-FWD; Apache `Require ip` + 10.8.0.0/24 (configtest OK); ufw 22 desde 10.8.0.2 | AWS |
| F4.3 | `F4.3_pruebas-vpn-ti.txt` | Peer `hospital-ti` 10.8.0.2 | 2026-11-08 | `fase4/vpn/prueba-vpn.ps1 -Peer ti` + SSH real | 9/9 + SSH a TI/Srv/Méd con origen 10.8.0.2 (sin NAT) | Internet → AWS |
| F4.3 | `F4.3_pruebas-vpn-medico.txt` | Peer `hospital-medico` 10.8.0.10 | 2026-11-08 | `prueba-vpn.ps1 -Peer medico` | 9/9: intranet 200/401; SSH y Visitantes bloqueados (REJECT en la DMZ) | Internet → AWS |
| F4.4 | `F4.4_snmpd-5-equipos.txt` | Las 5 EC2 | 2026-11-08 | `snmpd-setup.sh` vía `distribuir-snmp.ps1` | snmpd activo, usuario `monitor` authPriv SHA/AES, 0 comunidades v1/v2c, ufw 161 desde TI | AWS |
| F4.4 | `F4.4_pruebas-snmp-desde-ti.csv` | TI → 5 EC2 | 2026-11-08 | `prueba-snmp-ti.sh` | 9/9: v3 responde en las 5; v2c `public`, clave incorrecta y noAuthNoPriv rechazados | AWS |
| F4.4 | `F4.4_sonda-snmp-alcance.csv` | TI, Médicos, Visitantes → 5 EC2 | 2026-11-08 | `sonda-snmp.sh` (descubrimiento SNMPv3 sin credenciales) | 13 PASS, 0 FAIL, 2 N/A (consulta a sí mismo por loopback) | AWS |
| F4.4 | `F4.4_monitoreo-ti-instalacion.txt` | TI | 2026-11-08 | `monitoreo-ti-a.sh`, `monitoreo-ti-b.sh`, `limpieza-disco-ti.sh` | Prometheus 2.45.3, snmp_exporter 0.25.0, Grafana 13.3.0 en 127.0.0.1 | AWS |
| F4.4 | `F4.4_prometheus-objetivos-y-metricas.txt` | TI · Prometheus | 2026-11-08 | `verificar-monitoreo.sh` | 7/7 objetivos `up`; uptime, memoria, disco, carga y tráfico de las 5 EC2 | AWS |
| F4.4 | `F4.4_grafana-dashboard.png` | TI · Grafana (túnel `-L 3000`) | 2026-11-08 | Captura del dashboard "Red Hospital" | Tráfico, carga, memoria, disco e interfaces de las 5 EC2 | AWS |
| F4.4 | `F4.4_ampliacion-disco-ti.txt` | TI · EBS `vol-065ca518d1554816a` | 2026-11-08 | `modify-volume` 8→12 GiB + `growpart` + `resize2fs` | Disco 88 % → 56 % sin reinicio | AWS |
| F4.5 | `F4.5_ufw-previo-dmz.txt` | DMZ | 2026-11-08 | `dmz-ufw-previo.sh` | Reglas 80/443/51820 y `route` por peer antes de activar ufw | AWS |
| F4.5 | `F4.5_hardening-{antes,despues}-ip-10-0-0-100*.txt`, `F4.5_evidencias-ip-10-0-0-100-2026-11-08.txt` | DMZ | 2026-11-08 | `hardening.sh cliente` (confirmado con `SI`) | Inventario de puertos antes/después sin cambios; acceso por EICE confirmado | AWS |
| F4.5 | `F4.5_post-hardening-dmz.txt` | DMZ | 2026-11-08 | `dmz-post-hardening.sh` + pruebas externas y VPN | `permitrootlogin no`; ufw deny incoming/routed; FORWARD DROP con WG-FWD primero; web 301/200; 22/389/8000/3000/9090 bloqueados; VPN TI 12/12 y médico 9/9 | AWS + Internet |
| F4.6 | `F4.6_chrony-cliente-dmz.txt` | DMZ | 2026-11-08 | `chrony-cliente.sh` | `^* 10.0.0.46`, Leap Normal | AWS |
| F4.6 | `F4.6_regresion-fase3-5-origenes.csv`, `.txt` | TI, Servidores, Médicos, Visitantes, DMZ | 2026-11-08 | `tests_fase3.sh <origen>` con `IP_DMZ=10.0.0.100` | **32 PASS / 0 FAIL / 0 OMITIDAS** (incluye TI-08, VIS-06, VIS-10, DMZ-01…03) | AWS |

## Resumen de pruebas de la Fase 4

| Bloque | PASS | FAIL | Notas |
|---|---|---|---|
| Web pública y TLS (Internet) | 14 | 0 | 2× http→301, https 200 + certificado, cabeceras, cita 201/200/404/400, privacidad, IP por http (444) y https (rechazo TLS), TCP 22 y 389 cerrados, `renew --dry-run` |
| VPN peer TI (tras hardening) | 12 | 0 | 9 de alcance + 3 SSH reales sin NAT |
| VPN peer médico (tras hardening) | 9 | 0 | Solo intranet |
| SNMP desde TI | 9 | 0 | v3 OK, v2c y credenciales inválidas rechazadas |
| SNMP alcance (TI/Médicos/Visitantes) | 13 | 0 | 2 N/A justificados |
| Prometheus | 7 | 0 | Objetivos `up` |
| Regresión Fase 3 (5 orígenes) | 32 | 0 | Sin omitidas |
| **Total** | **96** | **0** | 2 N/A justificados |

## Pendiente (lo hace el equipo)
- Captura superior del dashboard (paneles "Equipos respondiendo SNMP" y "Uptime") como `F4.4_grafana-dashboard-superior.png` (opcional).
- Capturas de consola AWS (ocultando el ID de cuenta): instancia DMZ con su EIP, SG-DMZ, ruta 10.8.0.0/24 en RT-Privada.
