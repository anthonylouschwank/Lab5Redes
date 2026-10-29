# Fase 3 — Implementación de servicios y seguridad en la nube

> Sección para insertar en el informe de Fases 1 y 2 (`CC3067 — Proyecto Final Diseño de una red`), **después de la Fase 2 (pág. 47)**. Reemplaza el borrador de Fase 3 de las págs. 48–63, cuyas capturas pueden conservarse como "estado inicial". No modifica el texto de las Fases 1 y 2, salvo la corrección indicada en §9.

## 1. Introducción y objetivo

En la Fase 2 se construyó en AWS la segmentación de la red del Hospital Privado Castillejos: VPC `10.0.0.0/24`, cinco subredes, tablas de rutas, dos Security Groups, una NACL para Visitantes y acceso administrativo privado mediante EC2 Instance Connect Endpoint. En la Fase 3 se implementaron sobre esa infraestructura los servicios de administración de red (DHCP, NTP y LDAP), una intranet con autenticación centralizada y los controles de seguridad del caso: firewall, ACL, NAT, aislamiento de Visitantes, acceso unidireccional desde TI y hardening.

Siguiendo las observaciones del enunciado, se usaron servicios administrados de AWS donde existen (DHCP Options Set, NAT Gateway, Amazon Time Sync, Security Groups y NACL). LDAP, la intranet y el servidor NTP interno se consolidaron en una sola instancia para reducir costos.

## 2. Alcance: diseñado, implementado y probado

| Componente | Fase 1 (diseñado) | Fase 3 (implementado) | Probado en AWS |
|---|---|---|---|
| DHCP | DHCP Options Set con `hospital.internal` | DHCP de AWS con el Options Set por defecto (`ec2.internal`, AmazonProvidedDNS) | Sí, en las 4 EC2 |
| NTP | chrony interno sincronizado con Amazon Time Sync | chrony en 10.0.0.46 (upstream 169.254.169.123) que sirve a Médicos, Servidores, DMZ y TI. Visitantes usa Time Sync directamente | Sí |
| LDAP | LLDAP/OpenLDAP | OpenLDAP (`slapd`) en 10.0.0.46, base `dc=hospital,dc=redes,dc=test` | Sí |
| Servidor web interno | Flask + nginx con HTTPS | Apache 2.4 con autenticación LDAP por grupo (`/intranet/`, `/intranet/ti/`) en HTTP/80 | Sí |
| Firewall | Un SG por rol + ufw | SG-TI, SG-Servidores, SG-Medicos, SG-Visitantes + ufw en cada EC2 | Sí |
| ACL | NACL de Visitantes | Hospital-NACL-Visitantes con una excepción SSH para TI | Sí |
| NAT | NAT instance (Fase 1) / NAT Gateway (alternativa, pág. 12) | **NAT Gateway** `Hospital-NAT` en la DMZ (10.0.0.101) + Elastic IP | Sí |
| SSH | Solo desde TI/VPN | Solo a través de EC2 Instance Connect Endpoint (subred TI); clave pública temporal (60 s) | Sí |
| Hardening | ufw, SSH con llaves, sin servicios innecesarios | `hardening.sh` por rol en las 4 EC2 | Sí |
| DNS interno, VPN, web pública DMZ, RDS, aplicación clínica | Diseñados | **No implementados** (fuera del alcance de esta fase; ver §10) | — |

## 3. Infraestructura AWS utilizada

| Recurso | Identificación | Subred / IP | Función |
|---|---|---|---|
| Hospital-EC2-Servidores | t3.micro, Ubuntu 24.04 | Servidores · 10.0.0.46 | OpenLDAP, Apache (intranet), chrony servidor |
| Hospital-EC2-TI | t3.micro, Ubuntu 24.04 | TI · 10.0.0.117 | Administración y pruebas |
| Hospital-EC2-Medicos-Prueba | t3.micro, Ubuntu 24.04 (nueva) | Médicos · 10.0.0.28 | Equipo de prueba de Médicos |
| Hospital-EC2-Visitantes-Prueba | t3.micro, Ubuntu 24.04 (nueva) | Visitantes · 10.0.0.69 | Equipo de prueba de Visitantes |
| Hospital-NAT | NAT Gateway público + Elastic IP | DMZ · 10.0.0.101 | Salida a Internet de las subredes privadas |
| Hospital-IGW | Internet Gateway | — | Salida de la DMZ (`Hospital-RT-Publica`) |
| Hospital-EC2-Connect | EC2 Instance Connect Endpoint | TI · 10.0.0.122 | SSH administrativo sin IP pública |

Ninguna EC2 tiene dirección IPv4 pública. La única dirección pública es la Elastic IP del NAT Gateway, que no acepta conexiones iniciadas desde Internet.

**Rutas:**
- `Hospital-RT-Privada` (Médicos, Servidores, Visitantes, TI): `10.0.0.0/24 → local`, `0.0.0.0/0 → Hospital-NAT`.
- `Hospital-RT-Publica` (DMZ): `10.0.0.0/24 → local`, `0.0.0.0/0 → Hospital-IGW`.

*[Insertar: diagrama actualizado de `anthony/DIAGRAMA-E10.1.md`, exportado a PNG.]*

## 4. Administración de la red

### 4.1 DHCP
AWS asigna automáticamente la configuración IP de cada instancia a partir del DHCP Options Set de la VPC (`dopt-0d28300b9723e6567`: `domain-name = ec2.internal`, `domain-name-servers = AmazonProvidedDNS`). AWS administra la asignación de direcciones de la VPC y el enunciado permite usar los servicios de la plataforma, así que no se instaló un servidor DHCP propio. Ubuntu registra la concesión en `/run/systemd/netif/leases/`:

| Equipo | Dirección/máscara | Gateway | DNS | Dominio |
|---|---|---|---|---|
| Servidores | 10.0.0.46/27 | 10.0.0.33 | 10.0.0.2 | ec2.internal |
| TI | 10.0.0.117/28 | 10.0.0.113 | 10.0.0.2 | ec2.internal |
| Médicos | 10.0.0.28/27 | 10.0.0.1 | 10.0.0.2 | ec2.internal |
| Visitantes | 10.0.0.69/27 | 10.0.0.65 | 10.0.0.2 | ec2.internal |

Los gateways coinciden con los calculados en el subnetting de la Fase 1 (primera dirección utilizable de cada subred).

### 4.2 NTP
- **Servidor interno (10.0.0.46):** `chrony` sincroniza con Amazon Time Sync (`169.254.169.123`, estrato 3 → servidor en estrato 4). `chrony-servidor.sh` agrega `allow` solo para Médicos, Servidores, DMZ y TI, más `local stratum 10` como respaldo.
- **Clientes TI y Médicos:** `chrony-cliente.sh` los apunta a 10.0.0.46. `chronyc sources` muestra `^* 10.0.0.46` como fuente seleccionada.
- **Visitantes:** para no abrir ningún flujo hacia otras subredes, usa directamente Amazon Time Sync (`^* 169.254.169.123`). Ni los SG ni las NACL filtran ese servicio (ver fuentes).

### 4.3 LDAP
OpenLDAP (`slapd`) en 10.0.0.46, con base `dc=hospital,dc=redes,dc=test`, `ou=People` y `ou=Groups`:
- Grupos (posixGroup): `medicos` (5001), `ti` (5002), `laboratorio` (5003).
- Usuarios ficticios: `medico01`, `medico02`, `ti01`, `ti02`, `laboratorio01`, `laboratorio02`.
- Cuenta de servicio `svc-intranet`.
- Las contraseñas se generaron en la propia instancia y no forman parte del informe.

`slapd` escucha en todas las interfaces (`SLAPD_SERVICES="ldap:/// ldapi:///"`). TCP/389 solo se admite desde Servidores y TI (SG-Servidores y ufw).

Pruebas (`probar-ldap.sh`): consulta de usuarios y grupos, autenticación válida y rechazo de contraseña incorrecta (código 49). **4/4 PASS.**

*Corrección del borrador:* la tabla de usuarios `ti_prueba`/`medico_prueba`/`lab_prueba` se reemplaza por los usuarios anteriores. La matriz de permisos se mantiene: `/intranet/` para los tres grupos y `/intranet/ti/` solo para `ti`.

## 5. Servidor web interno (intranet)
Apache 2.4.58 en 10.0.0.46 (módulos `ldap`, `authnz_ldap`, `include`), VirtualHost `hospital-intranet.conf`, TCP/80:
- `/`: portal informativo sin autenticación (200).
- `/intranet/`: autenticación Basic contra LDAP; requiere pertenecer a `medicos`, `ti` o `laboratorio`.
- `/intranet/ti/`: solo el grupo `ti`.
- Restricción por origen en tres capas:
  1. SG-Servidores admite 80 desde Médicos, Servidores, DMZ y TI.
  2. ufw repite esa lista.
  3. Apache aplica `Require ip` con las mismas redes.
  Visitantes no aparece en ninguna.
- El bind de Apache a LDAP usa `svc-intranet`. Su contraseña está en un archivo incluido, privado de root (`/etc/apache2/hospital-intranet/`, modo 700).

Pruebas `probar-web.sh` (W-01…W-07): portal 200; intranet sin credenciales 401; `ti01` válido 200; contraseña incorrecta 401; usuario inexistente 401; panel TI con `ti01` 200; panel TI con `medico01` 401. **7/7 PASS.**

## 6. Seguridad

### 6.1 Security Groups (stateful)
| SG | Entrada | Salida |
|---|---|---|
| Hospital-SG-TI | TCP 22 desde SG-TI (endpoint) | Todo |
| Hospital-SG-Servidores | TCP 22 e ICMP desde SG-TI · TCP 80 desde 10.0.0.0/27, .32/27, .96/28, .112/28 · TCP 389 desde .32/27 y .112/28 · UDP 123 desde .0/27, .32/27, .96/28, .112/28 | TCP 80 y 443 → 0.0.0.0/0 |
| Hospital-SG-Medicos (nuevo) | TCP 22 desde SG-TI | Todo |
| Hospital-SG-Visitantes (nuevo) | TCP 22 desde SG-TI | Todo |

**"TI llega a todas, nadie llega a TI":** todos los SG aceptan SSH desde SG-TI, y SG-TI solo acepta SSH desde sí mismo (el endpoint). Las respuestas a lo que TI inicia vuelven porque los SG son stateful.

### 6.2 NACL de Visitantes (stateless)
| Regla | Entrada | Salida |
|---|---|---|
| 90 | ALLOW TCP 22 desde 10.0.0.112/28 (TI y endpoint) | ALLOW TCP 1024-65535 → 10.0.0.112/28 (respuestas SSH) |
| 100 | DENY todo desde 10.0.0.0/24 | DENY todo → 10.0.0.0/24 |
| 110 | DENY todo desde 10.8.0.0/24 (pool VPN previsto) | DENY todo → 10.8.0.0/24 |
| 120 | ALLOW todo desde 0.0.0.0/0 | ALLOW todo → 0.0.0.0/0 |
| * | DENY | DENY |

El tráfico de Visitantes a Internet lleva destino público, así que la regla 100 no lo afecta y la 120 lo permite. El NAT Gateway es solo el siguiente salto de la ruta. La salida 90 solo permite enviar paquetes a puertos altos de TI, y SG-TI los descarta.

### 6.3 NAT
Se usa el NAT Gateway administrado en lugar de la NAT instance de la Fase 1 (`nat-instance.sh` queda documentado como alternativa). Ventajas: no requiere administrar ni endurecer una EC2, no hay que desactivar *source/dest check* y no admite conexiones entrantes. Su costo es mayor (§8).

### 6.4 SSH
Todas las instancias se administran únicamente por EC2 Instance Connect Endpoint (subred TI, 10.0.0.122, *Preserve client IP = No*):
- La clave pública se autoriza por 60 s con `ec2-instance-connect send-ssh-public-key`.
- No hay SSH desde Internet ni IP pública.
- La CLI de administración dejó de usar la cuenta root: se creó el usuario IAM `fase3-admin`, sin access keys.

### 6.5 Hardening
Se ejecutó `hardening.sh` por rol (`servidores`, `cliente` para Médicos y Visitantes, y `ti` al final), con inventario antes y después y un rollback automático de 300 s que solo se canceló tras confirmar acceso por una segunda sesión:
- **ufw:** `deny incoming`, `allow outgoing`, `deny routed`, y solo los puertos del rol.
  - Servidores: 22 desde TI; 80 desde Médicos, Servidores, DMZ y TI; 389 desde Servidores y TI; 123/udp desde las mismas cuatro redes.
  - Resto: 22 desde TI.
- **SSH** (`sshd -T`): `PasswordAuthentication no`, `KbdInteractiveAuthentication no`, `PermitRootLogin no`, `X11Forwarding no`.
- **Servicios:** se deshabilitó `ModemManager`, innecesario en una EC2.
- **Puertos en escucha después del hardening:** 22 (sshd), 53 solo local (systemd-resolved), 68 (cliente DHCP), 323 solo local (chronyc); en Servidores además 80, 389 y 123. Cada puerto queda justificado y filtrado por ufw y SG.
- LDAP, Apache y NTP siguieron funcionando después del cambio.

## 7. Pruebas integradas
Se ejecutó `tests_fase3.sh` en cada EC2 de origen, más pruebas complementarias y pruebas desde Internet (laptop del equipo). Criterio: un flujo "permitido" debe conectar; uno "bloqueado" debe terminar en *timeout* (un *connection refused* contaría como fallo, porque indicaría que la red no lo bloqueó).

| Requisito del enunciado | Pruebas | Resultado |
|---|---|---|
| SSH a las instancias | TI-01, TI-06, TI-07, TI-11 + acceso por endpoint a las 4 EC2 | PASS |
| Visitantes con Internet | VIS-11 (TCP 443 a 1.1.1.1), VIS-12 (HTTPS example.com 200) | PASS |
| Visitantes sin acceso a otras subredes | VIS-01…05, VIS-07…09, VIS-14, VIS-15 (SSH, HTTP, LDAP, ICMP) | PASS (timeout) |
| TI → todas las subredes | TI-01…07, TI-11 | PASS |
| Ninguna subred → TI | SRV-01, MED-01, MED-02, VIS-01, VIS-07 | PASS (timeout) |
| Intranet desde todas menos Visitantes | TI-02, TI-10, SRV-02, MED-03, MED-08, MED-09 · VIS-02, VIS-14 bloqueadas | PASS |
| Intranet no accesible desde Internet | EXT: TCP 22/80/443/389 a la EIP del NAT = False; ninguna EC2 con IPv4 pública | PASS |
| NAT | TI-09, MED-10, VIS-11, VIS-12 | PASS |
| NTP | TI-04, MED-05 (`^* 10.0.0.46`), SRV-03, VIS-13 | PASS |
| LDAP solo desde Servidores y TI | TI-03 permitido · MED-04, VIS-04, VIS-15 bloqueados | PASS |
| Hardening | MED-06 (SSH Médicos → Servidores bloqueado), inventarios antes/después | PASS |

**Total: 40 PASS, 0 FAIL, 6 OMITIDAS** (TI-08, VIS-06, VIS-10, DMZ-01…03). Las omitidas se deben a que la DMZ no tiene EC2 propia: en esta fase solo aloja el NAT Gateway, que es un servicio administrado. Los CSV y salidas completas están en `fase3/evidencias/` (índice: `INDICE-EVIDENCIAS.md`).

*[Insertar capturas: SG-Servidores Inbound; NACL Visitantes Inbound/Outbound; NAT Available; EC2 sin IPv4 pública; salida de `tests_fase3.sh` desde Visitantes y TI.]*

## 8. Costos
- Cost Explorer al 29/10/2026: uso del mes **US$7.75**, cubierto por créditos promocionales (neto US$0).
- Tarifas de lista us-east-1 de los recursos de esta fase:
  - EC2 t3.micro US$0.0104/h (4 instancias durante la demo ≈ US$0.04/h).
  - NAT Gateway US$0.045/h + US$0.045/GB.
  - IPv4 pública US$0.005/h.
  - EBS gp3 US$0.08/GB-mes.
  - Instance Connect Endpoint, Time Sync, DHCP Options, SG y NACL no tienen costo.
- El NAT Gateway y su EIP siguen cobrándose aunque las EC2 estén detenidas (≈ US$36.50/mes si se dejan 24/7). Después de la evaluación, el grupo decidirá si se eliminan.

*[Insertar captura de Billing → Bills, con el ID de cuenta oculto.]*

## 9. Correcciones a fases anteriores y al borrador
1. **Fase 2, pág. 32:** decía que SG-Servidores conservaba la salida predeterminada. La Imagen 12 muestra *"No security group rules found"*: no tenía reglas de salida. En la Fase 3 se agregaron TCP 80/443 de salida.
2. **Tabla de flujos del borrador (pág. 60):** la intranet usa **TCP/80**, no TCP/443 (ver §10).
3. **Usuarios de prueba (págs. 56–57):** se reemplazan por los de §4.3.
4. **NAT Gateway (pág. 62):** la captura lo muestra *Pending*; su estado actual es *Available*.
5. **slapd (pág. 63):** la captura muestra `127.0.0.1:389`; ahora escucha en todas las interfaces, filtrado por SG y ufw.
6. **IP de servicios:** la Fase 1 preveía 10.0.0.36/.37 para el servidor interno y los servicios de red; ambos se consolidaron en 10.0.0.46. El NAT está en 10.0.0.101, no en .102.

## 10. Limitaciones y trabajo pendiente
- **Sin cifrado en la intranet:** usa HTTP con autenticación Basic, así que las credenciales viajan sin cifrar dentro de la VPC. El diseño de Fase 1 prevé HTTPS con certificado interno o autofirmado. Queda para la fase final.
- **DMZ sin EC2:** la web pública, la VPN WireGuard/Client VPN, RDS y la aplicación clínica no se implementaron. Por eso no hay pruebas desde la DMZ.
- **Sin DNS interno:** se usa AmazonProvidedDNS y `/etc/hosts` (decisión E2.5). El dominio `ec2.internal` difiere del `hospital.internal` de Fase 1.
- **Pruebas LDAP:** la autenticación se probó en la propia instancia (`probar-ldap.sh`, `probar-web.sh`). Desde TI se probó la conectividad TCP/389, no un *bind* con credenciales.
- **Una sola zona de disponibilidad** (us-east-1a): sin alta disponibilidad.

## 11. Documentación consultada
- AWS. *Control subnet traffic with network access control lists.* Amazon VPC User Guide. https://docs.aws.amazon.com/vpc/latest/userguide/vpc-network-acls.html
- AWS. *Control traffic to your AWS resources using security groups.* Amazon VPC User Guide. https://docs.aws.amazon.com/vpc/latest/userguide/vpc-security-groups.html
- AWS. *NAT gateways.* Amazon VPC User Guide. https://docs.aws.amazon.com/vpc/latest/userguide/vpc-nat-gateway.html
- AWS. *DHCP option sets in Amazon VPC.* https://docs.aws.amazon.com/vpc/latest/userguide/VPC_DHCP_Options.html
- AWS. *Set the time for your Linux instance (Amazon Time Sync Service).* Amazon EC2 User Guide. https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/set-time.html
- AWS. *Connect to your instances using EC2 Instance Connect Endpoint.* https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/connect-with-ec2-instance-connect-endpoint.html
- AWS. *Amazon VPC pricing* (NAT Gateway, IPv4 pública). https://aws.amazon.com/vpc/pricing/
- Apache Software Foundation. *mod_authnz_ldap.* https://httpd.apache.org/docs/2.4/mod/mod_authnz_ldap.html
- OpenLDAP Project. *OpenLDAP Software 2.6 Administrator's Guide.* https://www.openldap.org/doc/admin26/
- chrony project. *chrony.conf(5) manual.* https://chrony-project.org/doc/4.5/chrony.conf.html
- Ubuntu. *Uncomplicated Firewall (ufw).* https://help.ubuntu.com/community/UFW
- Material reutilizado del Laboratorio 5 del curso (LDAP, Apache y pruebas) y scripts del equipo (`fase3/sebastian`, `isabella`, `leonardo`, `anthony`).

## Anexo — Archivos de configuración entregados
- `fase3/config-final/<equipo>/`: chrony (`fase3-servidor.conf` / `fase3-cliente.conf`), `apache-hospital-intranet.conf`, `slapd-default-SLAPD_SERVICES.txt`, `sshd-01-fase3-hardening.conf`, `ufw-<host>.txt`.
- `fase3/evidencias/*.json`: SG, NACL, rutas, NAT, DHCP Options e instancias, antes y después.
- `fase3/CAMBIOS-Y-REVERSION.md`: cada cambio realizado con su comando de reversión.
- Scripts: `fase3/sebastian/`, `fase3/isabella/`, `fase3/leonardo/` (con `fase3.env` de AWS).
