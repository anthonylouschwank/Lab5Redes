# Comandos usados en la implementación de Fase 3 (29/10/2026)

Scripts ejecutados desde Windows (PowerShell) hacia las EC2 por EC2 Instance Connect Endpoint. Las salidas están en `../evidencias/` y cada cambio, con su reversión, en `../CAMBIOS-Y-REVERSION.md`.

| Script | Dónde corre | Para qué | Evidencia |
|---|---|---|---|
| `rrun.ps1 <instance-id> <puerto> <script.sh>` | Windows | Autoriza la clave pública por 60 s y ejecuta un script bash en la EC2 por el túnel | — |
| `rscp.ps1 <instance-id> <puerto> <origen> <destino>` | Windows | Copia archivos a la EC2 por el túnel | — |
| `srv-inspect.sh` | Servidores (y clientes, solo lectura) | Puertos, ufw, sshd, slapd, vhost, chrony, lease DHCP, servicios | `E5_E7.4_servidores-inspeccion-antes.txt` |
| `srv-ntp-ldap.sh` | Servidores | `chrony-servidor.sh` + `SLAPD_SERVICES="ldap:/// ldapi:///"` | `E5.3_E5.5_servidores-chrony-slapd.txt` |
| `cli-ntp.sh` | TI, Médicos, Visitantes (con `NTP_SRV=` antepuesto) | Lease DHCP, puertos y `chrony-cliente.sh` | `E5.2_E5.4_<equipo>-dhcp-ntp.txt` |
| `post-hard.sh` | Las 4 EC2 | Verificación posterior a `hardening.sh` | `E7.5_<equipo>-despues-hardening.txt` |
| `tests.sh` | Las 4 EC2 (con `ORIGEN=` antepuesto) | `tests_fase3.sh <origen>` + pruebas complementarias | `E8_pruebas-desde-<equipo>.txt`, `aws/<equipo>/resultados-*.csv` |
| `export-conf.sh` | Las 4 EC2 | Copia de la configuración final sin secretos | `../config-final/<equipo>/` |
| `../hardening-interactivo.ps1` | Windows (terminal interactiva) | `hardening.sh` con confirmación de acceso desde una segunda sesión | `aws/<equipo>/hardening-*.txt` |

Túneles: `aws ec2-instance-connect open-tunnel --instance-id <id> --local-port <2222|2223|2224|2225> --remote-port 22 --region us-east-1` (Servidores, TI, Médicos, Visitantes).
