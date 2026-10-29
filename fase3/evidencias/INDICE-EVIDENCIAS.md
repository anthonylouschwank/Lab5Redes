# Índice de evidencias — Fase 3

**Validación:** **AWS** = ejecutado y verificado en la infraestructura AWS · **Local** = entorno local de un compañero (antecedente, no sustituye AWS) · **Informe** = captura ya incluida en el informe PDF.
Todas las salidas de texto son salidas de terminal, no capturas gráficas. En todos los archivos se ocultaron el ID de cuenta y la IP pública del NAT. Ningún archivo contiene contraseñas, hashes, claves ni tokens; se verificó por búsqueda de patrones el 29/10/2026.

| ID tarea | Archivo | Instancia / recurso | Fecha (UTC) | Comando o prueba | Resultado | Validación |
|---|---|---|---|---|---|---|
| E3.13–E3.14 | `E3.13_costos-cost-explorer.txt` | Cuenta (Cost Explorer) | 2026-10-29 | `aws ce get-cost-and-usage` por servicio y tipo | Uso US$7.75 cubierto por créditos; tarifas del NAT, EIP y EC2 | AWS |
| E4.5 | `E4.5_estado-previo-sg.json`, `-nacl.json`, `-rutas.json`, `-instancias.json` | VPC `vpc-07782d0d08628b4a5` | 2026-10-29 | `describe-security-groups/network-acls/route-tables/instances` | Estado anterior a los cambios (respaldo para reversión) | AWS |
| E4.6 | `E4.6_instancias-fase3.json` | 4 EC2 (TI, Servidores, Médicos-Prueba, Visitantes-Prueba) | 2026-10-29 | `describe-instances` | Todas *running*, t3.micro, **sin IP pública** | AWS |
| E3 / E7.1 | `E4.5_estado-previo-rutas.json` | Hospital-RT-Privada / Pública | 2026-10-29 | `describe-route-tables` | Privada: `0.0.0.0/0 → nat-055f…` (4 subredes); Pública: `0.0.0.0/0 → igw-0650…` (DMZ); todas *active* | AWS |
| E7.1 | `E7.1_nat-gateway.json` | `Hospital-NAT` | 2026-10-29 | `describe-nat-gateways` | *available*, public, DMZ, 10.0.0.101, EIP asociada | AWS |
| E5.1 | `E5.1_dhcp-options.json` | `dopt-0d28300b9723e6567` | 2026-10-29 | `describe-dhcp-options` | `domain-name=ec2.internal`, `AmazonProvidedDNS` | AWS |
| E5.2 | `E5_E7.4_servidores-inspeccion-antes.txt`, `E5.2_E5.4_{ti,medicos,visitantes}-dhcp-ntp.txt` | Las 4 EC2 | 2026-10-29 | Leases de `systemd-networkd`, `ip route`, `resolvectl` | IP, máscara, gateway (.33/.113/.1/.65), DNS 10.0.0.2 y dominio entregados por el DHCP de AWS | AWS |
| E5.3 / E5.4 | `E5.3_E5.5_servidores-chrony-slapd.txt`, `aws/servidores/evidencias-ip-10-0-0-46-*.txt` | Servidores | 2026-10-29 | `chrony-servidor.sh` | `^* 169.254.169.123`, Leap Normal, UDP 123 servido solo a Médicos, Servidores, DMZ y TI | AWS |
| E5.4 | `E5.2_E5.4_{ti,medicos}-dhcp-ntp.txt` | TI, Médicos | 2026-10-29 | `chrony-cliente.sh` | `^* 10.0.0.46` (NTP interno) | AWS |
| E5.4 | `E5.2_E5.4_visitantes-dhcp-ntp.txt` | Visitantes | 2026-10-29 | `chrony-cliente.sh` con `NTP_SERVER=169.254.169.123` | `^* 169.254.169.123` (sin depender de otras subredes) | AWS |
| E5.5 | `E5.3_E5.5_servidores-chrony-slapd.txt` | Servidores · slapd | 2026-10-29 | `SLAPD_SERVICES="ldap:/// ldapi:///"` + `ldapsearch` | slapd en 0.0.0.0:389; `namingContexts: dc=hospital,dc=redes,dc=test` | AWS |
| E5.5–E5.7 | (en Servidores) `~/fase3/sebastian/` salidas de `probar-ldap.sh` | Servidores | 2026-10-28 | `probar-ldap.sh` | 4/4 PASS: usuarios, grupos, bind válido, rechazo 49 | AWS (reportado por Majo) |
| E6.1–E6.2 | `aws/servidores/E6.2_Pruebas-Web-LDAP-AWS.txt` | Servidores · Apache | 2026-10-29 | `probar-web.sh` | 7/7 PASS (W-01…W-07) | AWS |
| E6 | `../isabella/evidencias/E6_probar-web_vm-local.txt` | VM local de Isabella | 2026-10-28 | `probar-web.sh` | Antecedente | Local |
| E7.2 | `E7.2_sg-servidores-ingress-agregado.json`, `E7.2_estado-posterior-sg.json` | SG-Servidores, SG-Medicos, SG-Visitantes | 2026-10-29 | `authorize-security-group-ingress` | 80/389/123 sin Visitantes; SG nuevos con 22 solo desde SG-TI | AWS |
| E7.2 | `E7.2_estado-posterior-nacl-visitantes.json` | `Hospital-NACL-Visitantes` | 2026-10-29 | `create-network-acl-entry` 90 entrada/salida | Excepción solo para TI; 100 DENY 10.0.0.0/24 intacta | AWS |
| E7.4 | `aws/<equipo>/hardening-antes-*.txt` | Las 4 EC2 | 2026-10-29 | `hardening.sh` (inventario antes) | Puertos en escucha antes del hardening | AWS |
| E7.4–E7.5 | `aws/<equipo>/hardening-despues-*.txt`, `aws/<equipo>/evidencias-*.txt`, `E7.5_<equipo>-despues-hardening.txt` | Las 4 EC2 | 2026-10-29 | `hardening.sh servidores/cliente/ti` + verificación | ufw *deny incoming* + puertos del rol; `PasswordAuthentication no`, `PermitRootLogin no`, `X11Forwarding no`; ModemManager deshabilitado; acceso por EICE confirmado; LDAP, Apache y NTP activos | AWS |
| E8.1–E8.10 | `aws/ti/resultados-ti-2026-10-29.csv`, `E8_pruebas-desde-ti.txt` | Origen TI | 2026-10-29 | `tests_fase3.sh ti` + complementarias | 10 PASS / 0 FAIL (TI-08 OMITIDA) | AWS |
| E8 | `aws/servidores/resultados-servidores-2026-10-29.csv`, `E8_pruebas-desde-servidores.txt` | Origen Servidores | 2026-10-29 | `tests_fase3.sh servidores` | 3 PASS / 0 FAIL | AWS |
| E8 | `aws/medicos/resultados-medicos-2026-10-29.csv`, `E8_pruebas-desde-medicos.txt` | Origen Médicos | 2026-10-29 | `tests_fase3.sh medicos` + MED-06…10 | 10 PASS / 0 FAIL | AWS |
| E8 | `aws/visitantes/resultados-visitantes-2026-10-29.csv`, `E8_pruebas-desde-visitantes.txt` | Origen Visitantes | 2026-10-29 | `tests_fase3.sh visitantes` + VIS-14/15 | 13 PASS / 0 FAIL (VIS-06/10 OMITIDAS) | AWS |
| E8.5 / E8.10 | `resultados-internet-EXT.csv` | Laptop en Internet → EIP del NAT; IP pública de las EC2 | 2026-10-29 | `Test-NetConnection` 22/80/443/389 · `describe-instances` | 4/4 bloqueadas; ninguna EC2 con IPv4 pública | AWS |
| E2 / LDAP | `../sebastian/ENTREGA-SEBASTIAN.md` y capturas del informe | VM local de Sebastián | 2026-10 | Scripts LDAP | Antecedente | Local |
| E3 / E5 | Informe PDF, págs. 48–63 | Consola AWS / TI | 2026-10-28 | Capturas de subredes, rutas, SG, NACL, IGW, NAT, DHCP y chrony | Estado previo a los cambios de hoy | Informe |

## Pruebas OMITIDAS (con justificación)
- **TI-08, VIS-06, VIS-10, DMZ-01…03:** no hay EC2 en la DMZ. En Fase 3 la DMZ solo aloja el NAT Gateway, un servicio administrado que no admite SSH ni ping. La web pública de Fase 1 queda fuera del alcance.
- **NAT-01…03:** se diseñaron para una NAT instance. Con NAT Gateway no hay instancia que probar.

## Resumen de la matriz
36 pruebas ejecutadas en AWS desde 4 orígenes, más 4 desde Internet: **40 PASS, 0 FAIL, 6 OMITIDAS justificadas**.

## Capturas gráficas pendientes (consola AWS, ocultando el ID de cuenta)
Ver la lista en [../checklist.md](../checklist.md), sección "Capturas pendientes".
