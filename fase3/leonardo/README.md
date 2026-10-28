# Fase 3 — Scripts de Leonardo (NAT, NTP, hardening y pruebas)

Hospital Privado Castillejos · CC3067 Redes · AWS us-east-1 · VPC `10.0.0.0/24`

Los ejecuta **Majo** en las EC2. Todos son de Bash para **Ubuntu 24.04**: se pueden repetir sin
romper nada, respaldan antes de cambiar y terminan con `RESULTADO: OK` o `RESULTADO: FALLO`
(con código de salida distinto de 0). Cada corrida deja evidencia en
`evidencias-<host>-<fecha>.txt`, en la carpeta desde donde se ejecuta.

| Archivo | Qué hace | Dónde se corre |
|---|---|---|
| `nat-instance.sh` | Convierte una EC2 de la DMZ en NAT (forwarding + MASQUERADE + persistencia) | EC2 NAT (DMZ) |
| `chrony-servidor.sh` | Servidor NTP interno (chrony ← Amazon Time Sync, sirve a la VPC) | Servidores `10.0.0.46` |
| `chrony-cliente.sh` | Cliente NTP del servidor interno | TI, Médicos, DMZ, NAT… |
| `hardening.sh <rol>` | ufw + SSH endurecido + servicios, con **seguro anti-lockout** | Todas, **al final** |
| `tests_fase3.sh <origen>` | Matriz de pruebas → `resultados-<origen>-<fecha>.csv` (para Roberto) | Cada EC2 de origen |
| `fase3.env.example` | IPs, subredes y puertos (sin secretos) | Copiar como `fase3.env` |
| `lib.sh` | Funciones comunes (no se ejecuta sola) | Junto a los scripts |

`pruebas-locales/` es lo que usé para probar sin AWS. **No se entrega.**

## Qué necesita cada integrante de esta parte

| Quién | Qué hacer o saber |
|---|---|
| **Anthony** (red AWS) | Estas reglas las asumen los scripts; si no están, fallan con un mensaje que lo dice. **SG-Servidores, entrada:** UDP 123 desde la VPC (NTP), TCP 389 desde Servidores y TI, TCP 80 desde Médicos, Servidores, DMZ y TI (nunca Visitantes). **SG-Servidores, salida:** hoy no tiene ninguna; necesita TCP 80/443 para `apt` por la NAT (y quizá UDP 123 hacia 169.254.169.123, ver §3). **NAT:** decidir instance o Gateway (§8); si es instance, los pasos de consola están en §2. **NACL:** permitir los puertos efímeros de vuelta (1024-65535). Revisar y ajustar los valores de `fase3.env.example` (§8). |
| **Majo** (ejecuta) | Seguir §0 (copiar la carpeta y crear `fase3.env`) y el orden de §1. Responder las preguntas solo cuando aparezcan. Al terminar, **Stop** (nunca Terminate). |
| **Sebastián** (LDAP) | Orden en Servidores: `chrony-servidor.sh` → su LDAP → Apache → `hardening.sh servidores` → pruebas. El hardening abre 389 **solo** desde Servidores y TI, como dice su contrato (`LDAP_ALLOW_CIDRS`). Si cambia el puerto o usa LDAPS, hay que ajustar `LDAP_PORT` y `LDAP_ALLOW_CIDRS`. `tests_fase3.sh` usa su usuario ficticio `ti01` (contraseña por `read -s`, nunca en archivos). |
| **Isabella** (intranet) | El hardening abre `INTRANET_PORTS` (hoy 80) desde Médicos, Servidores, DMZ y TI, nunca Visitantes. Si usa HTTPS: `INTRANET_PORTS="80 443"`, `INTRANET_PORT=443`, `INTRANET_SCHEME=https`. Apache consulta LDAP por `127.0.0.1` (contrato de Sebastián), así que no pasa por ufw ni por el SG. |
| **Roberto** (matriz e informe) | CSV `resultados-<origen>-<fecha>.csv` con columnas `fecha,origen,destino,protocolo_puerto,esperado,obtenido,resultado` (§5). Las OMITIDAS no van al CSV; `--solo` agrega una fila nueva (vale la más reciente). Inventario de puertos: `hardening-antes-<host>.txt` y `hardening-despues-<host>.txt`. Evidencias: `evidencias-<host>-<fecha>.txt`. Lo probado y lo pendiente, en §6; la documentación consultada, en §7. El DHCP lo da AWS (DHCP option set): no hay script. |

---

## 0. Preparación (una vez)

1. **Variables.** En la carpeta de los scripts:
   ```bash
   cp fase3.env.example fase3.env
   nano fase3.env    # IP_NAT/IP_DMZ, IP_MEDICOS, IP_VISITANTES y lo que Anthony cambie
   ```
   Sin `fase3.env`, los scripts usan el `.example` y lo avisan. Cualquier variable también se
   puede pasar por entorno: `sudo NTP_SERVER=10.0.0.50 bash chrony-cliente.sh`.
2. **Copiar la carpeta a cada EC2.** Las privadas no tienen Internet hasta que exista la NAT, así
   que no pueden hacer `git clone`. Desde tu PC, por el EC2 Instance Connect Endpoint:
   ```bash
   aws ec2-instance-connect send-ssh-public-key --instance-id <i-…> --instance-os-user ubuntu \
       --ssh-public-key file://~/.ssh/id_ed25519.pub          # la clave vale 60 s
   aws ec2-instance-connect open-tunnel --instance-id <i-…> --local-port 2222 &
   scp -P 2222 -r leonardo ubuntu@127.0.0.1:~/fase3
   ```
   (Revisa los parámetros en la documentación del CLI; ver "Documentación consultada".)
3. **Credenciales LDAP** para `tests_fase3.sh` (opcional, nunca se escriben en archivos):
   ```bash
   export LDAP_USER=ti01; read -rs LDAP_PASS; export LDAP_PASS   # usuario ficticio de Sebastián
   ```

**Reglas para todas las corridas**
- Antes de `hardening.sh`, ten **otra sesión** abierta o lista por el endpoint.
- Responde las preguntas **solo cuando aparezcan** (`? … [escribe SI y Enter]`). Lo que se teclee
  antes se descarta a propósito.
- Al terminar: **Stop** de las instancias (nunca Terminate).

---

## 1. Orden de ejecución

| # | Quién / dónde | Comando | Resultado esperado |
|---|---|---|---|
| 0 | Consola AWS (Anthony/Majo) | NAT en la DMZ: Elastic IP, **desactivar Source/dest check**, rutas (ver §2) | — |
| 1 | EC2 NAT | `sudo bash nat-instance.sh` | `RESULTADO: OK`, "La NAT tiene Internet (HTTP 200)" |
| 2 | Servidores | `sudo bash chrony-servidor.sh` | `^*` en 169.254.169.123, escucha UDP 123 |
| 3 | Servidores | LDAP (Sebastián) y Apache (Isabella) con sus scripts | — |
| 4 | TI, Médicos, DMZ, NAT | `sudo bash chrony-cliente.sh` | `^*` en 10.0.0.46 |
| 4b | Visitantes | `sudo NTP_SERVER=169.254.169.123 bash chrony-cliente.sh` | ver §3 (no puede usar 10.0.0.46) |
| 5 | Servidores | `sudo bash hardening.sh servidores` | confirmar acceso → `RESULTADO: OK` |
| 6 | EC2 NAT | `sudo bash hardening.sh nat` | NAT sigue funcionando |
| 7 | Médicos, Visitantes, DMZ | `sudo bash hardening.sh cliente` | — |
| 8 | TI | `sudo bash hardening.sh ti` | (el último: es por donde se administra) |
| 9 | Cada EC2 | `bash tests_fase3.sh <origen>` | CSV para Roberto; todo PASS |
| 10 | Consola | **Stop** de todas | — |

Para ver qué se va a probar antes de correrlo: `bash tests_fase3.sh --lista` (o `--lista ti`).

---

## 2. `nat-instance.sh` — EC2 NAT en la DMZ

```bash
sudo bash nat-instance.sh              # aplicar (se puede repetir)
sudo bash nat-instance.sh --estado     # ver reglas, contadores y servicio
sudo bash nat-instance.sh --revertir   # quitar todo
```
**Qué deja:** `/etc/sysctl.d/60-fase3-nat.conf` (`ip_forward=1`), `/usr/local/sbin/fase3-nat-reglas`
y el servicio `fase3-nat` (vuelve a aplicar las reglas al arrancar, **sin** `iptables-persistent`).

**Reglas:**
- `MASQUERADE` de `NAT_SOURCE_CIDRS` hacia fuera de la VPC.
- Cadena `FASE3-NAT` al inicio de FORWARD: deja salir la VPC hacia Internet y volver solo las
  respuestas.
- Política de FORWARD en `DROP`: nada iniciado desde Internet entra, y la NAT no sirve de puente
  entre subredes.

**Decisión:** la NAT la gestiona esta cadena propia, no ufw. Si después se corre
`hardening.sh nat`, ufw solo filtra la entrada y `fase3-nat` se reinicia para quedar primero.

**En la consola (el script lo recuerda al final):**
1. EC2 NAT → *Redes* → **Cambiar comprobación de origen/destino → Desactivar**.
2. Elastic IP en la NAT. `Hospital-RT-Publica`: `0.0.0.0/0 → Internet Gateway`.
3. `Hospital-RT-Privada`: `0.0.0.0/0 →` la instancia/ENI NAT.
4. SG de la NAT: entrada solo desde `10.0.0.0/24` (+ SSH desde TI), **nada desde Internet**.
5. NACL: permitir la salida y los puertos efímeros `1024-65535` de vuelta.
6. **SG-Servidores no tiene reglas de salida:** para `apt` por la NAT necesita salida TCP 80/443 (Anthony).

**Prueba desde una privada:** `curl -sS -m 8 -o /dev/null -w '%{http_code}\n' https://example.com` → `200`.

| Mensaje | Significa |
|---|---|
| `No hay ruta por defecto` | La NAT no está en la DMZ con salida (IGW / ruta pública) |
| `La NAT no tiene salida a Internet` | Falta Elastic IP, IGW o la ruta `0.0.0.0/0 → IGW` |
| Privadas sin Internet aunque todo dé OK | Source/dest check activado, o falta la ruta en `Hospital-RT-Privada` |

---

## 3. NTP — `chrony-servidor.sh` y `chrony-cliente.sh`

```bash
sudo bash chrony-servidor.sh             # en Servidores (10.0.0.46). También --estado / --revertir
sudo bash chrony-cliente.sh              # en cada cliente. También --estado / --revertir
```
- **Primero inspeccionan** lo que ya hay. Las AMI de Ubuntu en AWS pueden traer chrony configurado
  contra Amazon Time Sync. Si `169.254.169.123` ya está declarado, el servidor **no lo duplica**.
- **Servidor:** `/etc/chrony/conf.d/fase3-servidor.conf` con
  `server 169.254.169.123 prefer iburst minpoll 4 maxpoll 4`, `allow 10.0.0.0/24` y
  `local stratum 10` (sigue dando hora si pierde Amazon Time Sync).
- **Cliente:** `/etc/chrony/conf.d/fase3-cliente.conf` con `server 10.0.0.46 iburst prefer`.
  Con `NTP_SOLO_INTERNO=si` (por defecto) comenta las demás fuentes (marca `#fase3# `, con
  respaldo previo), para que la demo muestre que usa el interno. `NTP_RESPALDO_AWS=si` agrega
  Amazon Time Sync como respaldo.
- **Si chrony no está instalado** y la EC2 no tiene Internet, el script se detiene en ~30 s y dice
  qué falta (NAT, ruta, SG de salida). No se queda colgado.
- **Puerto:** UDP 123 desde las subredes cliente hacia `10.0.0.46` en **SG-Servidores** (Anthony).

**Visitantes:** la regla 2 le impide llegar a otras subredes, así que **no puede** usar `10.0.0.46`.
Se configura directo contra Amazon Time Sync: `sudo NTP_SERVER=169.254.169.123 bash chrony-cliente.sh`.
Es link-local: no necesita NAT y, según la documentación de AWS, las NACL no filtran ese tráfico
(confirmar en §7).

**Cuando el cliente no sincroniza, el script dice cuál es el caso:**
- `0 paquetes recibidos`: no llega UDP 123. Causas, en orden: SG-Servidores, NACL (ida y vuelta
  efímera), `allow` del servidor, ufw del servidor.
- `responde pero aún no está seleccionado`: espera 1–2 min y repite con `--estado`.
- En el servidor, `sudo chronyc clients` muestra qué clientes consultan.

---

## 4. `hardening.sh <ti|servidores|nat|cliente>`

```bash
sudo bash hardening.sh servidores
sudo bash hardening.sh --revertir      # desactiva ufw y quita el drop-in de SSH
```

| Rol | Puertos de entrada que quedan (ufw) |
|---|---|
| `ti`, `cliente` | 22/tcp desde `SSH_ALLOW_CIDRS` (subred TI; el endpoint es `10.0.0.122`) |
| `servidores` | 22 + 389/tcp solo desde Servidores y TI (contrato de Sebastián) + 80/tcp desde Médicos, Servidores, DMZ y TI (**nunca Visitantes**) + 123/udp desde la VPC |
| `nat` | 22; el reenvío lo maneja `fase3-nat` |

Por defecto: `deny incoming`, `allow outgoing`, `deny routed`. Las reglas llevan el comentario
`fase3: …`. Las reglas previas que no son de la Fase 3 **se avisan, no se borran**.

**SSH:** `/etc/ssh/sshd_config.d/01-fase3-hardening.conf` con `PasswordAuthentication no`,
`PermitRootLogin no`, `X11Forwarding no` (y `KbdInteractiveAuthentication no`). Se llama **01-** y
no 99-: en sshd **gana el primer valor leído** y los drop-in se leen en orden alfabético, así que
un `99-` quedaría tapado por `50-cloud-init.conf`. Se valida con `sshd -t` antes de recargar, y
el script muestra los valores efectivos con `sshd -T`. No toca `ssh.socket` ni EC2 Instance Connect.

**Seguro anti-lockout (cómo usarlo):**
1. El script detecta desde dónde vienen las sesiones SSH abiertas. Si ninguna está en
   `SSH_ALLOW_CIDRS`, avisa y pregunta antes de seguir.
2. Programa `ufw-rollback.timer` con `systemd-run` (300 s): si no se cancela, desactiva ufw y
   renombra el drop-in de SSH a `.rollback`.
3. Aplica SSH y ufw, y pide: *abre otra sesión por el endpoint y escribe SI*.
4. **SI** → se cancela el rollback. Sin respuesta o con otra cosa → `[FALLO]` y en ≤ 5 min todo
   se revierte solo.

> Si ufw ya estaba activo antes, el rollback lo **desactiva** (queda más abierto que antes, pero no
> te deja fuera). Ver el temporizador: `systemctl list-timers ufw-rollback.timer`.

**Servicios:** deshabilita (con confirmación) los de `SERVICIOS_DESHABILITAR` que estén corriendo.
Los demás que no sean esperables para el rol solo se **listan**. Nunca toca `amazon-ssm-agent`,
`ssh`, `chrony` ni los de cloud-init.

**Evidencia para Roberto:** `hardening-antes-<host>.txt`, `hardening-despues-<host>.txt` (y sus
versiones `-completo` con `ss -tulnp`), las diferencias y una justificación de cada puerto que
sigue escuchando.

---

## 5. `tests_fase3.sh <origen>` — matriz de pruebas

```bash
bash tests_fase3.sh --lista            # todas las pruebas, sin ejecutar
bash tests_fase3.sh ti                 # origen: ti|medicos|visitantes|servidores|dmz|nat
bash tests_fase3.sh visitantes --solo VIS-02   # repetir una sola tras corregir algo
```
- **CSV:** `resultados-<origen>-<fecha>.csv` con columnas
  `fecha,origen,destino,protocolo_puerto,esperado,obtenido,resultado` (`PASS`/`FAIL`). **Mismo
  formato acordado con Roberto.** Con `--solo` se agrega una fila nueva: la más reciente es la que vale.
- **Pruebas `OMITIDA`:** son las que tienen el destino sin IP en `fase3.env`. Se muestran en
  pantalla y **no van al CSV**.
- **Criterio:**
  - Un `permitido` que no conecta es FAIL.
  - Un `bloqueado` que conecta es FAIL.
  - Un `bloqueado` con *connection refused* también es FAIL: el paquete llegó, o sea que la red
    no lo bloqueó.
  - El campo `obtenido` distingue *timeout* (probable SG/NACL/firewall) de *refused* (llegó, sin servicio).
- **Sondas:**
  - TCP: `/dev/tcp` con `timeout 5`.
  - HTTP: `curl` (401 cuenta como alcanzable: la intranet pide login).
  - LDAP: `ldapwhoami` con `LDAP_USER`/`LDAP_PASS`, o búsqueda anónima de la base. Sin `ldap-utils`
    cae a TCP y lo anota.
  - NTP: `chronyc sources`, con `^*` en `10.0.0.46`.
  - ICMP: `ping -c 2`.
  - Internet: TCP `1.1.1.1:443` y `curl https://example.com`.
- **Aviso:** si la IP del equipo no está en la subred del origen indicado, lo avisa (¿origen equivocado?).
- **Limitación:** un solo puerto bloqueado no demuestra aislamiento completo. Por eso la matriz
  prueba ICMP y los puertos de servicio de cada destino.

IDs: `TI-01..08`, `SRV-01..03`, `MED-01..05`, `VIS-01..13`, `DMZ-01..03`, `NAT-01..03`
(ver `--lista`). Los destinos y puertos salen de `fase3.env`: si Anthony cambia la matriz, se
ajusta ahí y, para pruebas nuevas, en el arreglo `PRUEBAS` del script.

---

## 6. Qué quedó probado y qué no

Probado en **dos VM locales iguales a una EC2**: imagen cloud de Ubuntu 24.04 con cloud-init,
1 vCPU, 1 GB. La "Servidores" era `10.0.0.46` y la "TI/NAT" `10.0.0.117`, en una red interna
`10.0.0.0/24`. **Nada de esto se ha corrido en AWS.**

| Qué | Estado |
|---|---|
| `bash -n` y `shellcheck` en todos los scripts | ✅ Probado, 0 avisos |
| Idempotencia (2 corridas: "Sin cambios", sin reglas duplicadas) | ✅ Probado en los 4 scripts que cambian cosas |
| Detección de "sin Internet" al instalar paquetes (corta en ~30 s con mensaje útil) | ✅ Probado bloqueando IPv4+IPv6 |
| chrony servidor ↔ cliente entre dos máquinas, `^*`, `chronyc clients` | ✅ Probado (con un NTP público en lugar de 169.254.169.123) |
| Diagnóstico del cliente con UDP 123 bloqueado (`0 paquetes recibidos`) | ✅ Probado |
| Mensaje cuando 169.254.169.123 no responde + servicio con `local stratum 10` | ✅ Probado (fuera de AWS siempre falla) |
| NAT real: una máquina sin salida propia navega a través de la otra (HTTP 200, contadores) | ✅ Probado |
| NAT + ufw (`hardening.sh nat`): la cadena sigue primera y la NAT funciona | ✅ Probado |
| Persistencia tras reinicio (fase3-nat, ufw, ip_forward, chrony) | ✅ Probado |
| Anti-lockout: sin confirmar, las conexiones nuevas se bloquean y a los N s se recupera el acceso solo | ✅ Probado |
| Anti-lockout: cancelar si el origen no está permitido; confirmar con SI cancela el rollback | ✅ Probado |
| `sshd -T` efectivo (`passwordauthentication no`, etc.) con el drop-in 01- | ✅ Probado |
| `tests_fase3.sh`: TI→Servidores (SSH, HTTP, LDAP, NTP, ICMP) PASS; Servidores→TI SSH bloqueado PASS tras el hardening; Internet por NAT PASS | ✅ Probado |
| `--revertir` de NAT, hardening y cliente NTP | ✅ Probado |
| Amazon Time Sync real (169.254.169.123) | ⏳ **Pendiente de probar en AWS** |
| Source/dest check, rutas, SG y NACL reales | ⏳ **Pendiente de probar en AWS** |
| EC2 Instance Connect Endpoint como origen SSH (`10.0.0.122`) frente a ufw | ⏳ **Pendiente de probar en AWS** |
| Cómo viene chrony en la AMI de AWS (las VM locales traían systemd-timesyncd) | ⏳ **Pendiente de ver en AWS** (los scripts inspeccionan primero) |
| Pruebas desde Médicos, Visitantes y DMZ (no hay EC2 todavía) | ⏳ **Pendiente de probar en AWS** |
| Que las NACL no filtren 169.254.169.123 ni el DNS de la VPC (10.0.0.2) para Visitantes | ⏳ **Pendiente de confirmar** (documentación §7) |

Problemas que encontraron las pruebas locales y ya están corregidos:
- El script de reglas de la NAT abortaba en la primera corrida (por `grep` sin coincidencias y `pipefail`).
- `tests_fase3.sh` se cortaba en silencio al leer `chronyc ntpdata` sin root. Ahora usa la columna Reach.
- La detección del origen SSH no funcionaba con `sudo`. Ahora usa `ss`.
- Las respuestas tecleadas antes de una pregunta podían contestarla. Ahora se descartan.

---

## 7. Documentación consultada

(Enlaces citados de memoria: verificar que sigan vigentes antes de ponerlos en el informe.)

- **Amazon Time Sync Service:** "Set the time for your Linux instance", EC2 User Guide —
  https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/set-time.html
- **NAT instances** (incluye desactivar Source/destination check), VPC User Guide —
  https://docs.aws.amazon.com/vpc/latest/userguide/VPC_NAT_Instance.html
- **Network ACLs** (tráfico que las NACL no filtran: Amazon DNS, Time Sync, metadata) —
  https://docs.aws.amazon.com/vpc/latest/userguide/vpc-network-acls.html
- **Security groups** — https://docs.aws.amazon.com/vpc/latest/userguide/vpc-security-groups.html
- **EC2 Instance Connect Endpoint** —
  https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/connect-using-eice.html
- **DHCP option sets** (AWS no permite un servidor DHCP propio en la VPC) —
  https://docs.aws.amazon.com/vpc/latest/userguide/VPC_DHCP_Options.html
- Ubuntu Server: chrony (`man chrony.conf`: `allow`, `local`, `confdir`), ufw (`man ufw`),
  `man sshd_config` ("for each keyword, the first obtained value will be used"),
  `man systemd-run` (`--on-active`).

---

## 8. Decisiones abiertas que pueden cambiar los scripts

| Pendiente | Qué cambia |
|---|---|
| NAT instance o NAT Gateway | Con Gateway, `nat-instance.sh` no se usa; el resto sigue igual |
| HTTP o HTTPS en la intranet | `INTRANET_PORTS="80 443"`, `INTRANET_PORT=443`, `INTRANET_SCHEME=https` |
| Base LDAP final (`hospital.redes.test` o `hospital.internal`) | `LDAP_BASE` en `fase3.env` (hoy igual que Sebastián) |
| Si Médicos/DMZ deben consultar LDAP | `LDAP_ALLOW_CIDRS` y `MED-04` (hoy bloqueado, como dice el contrato de Sebastián) |
| Qué subredes salen por la NAT | `NAT_SOURCE_CIDRS` (hoy, toda la VPC) |
| Si al caso Hospital le aplican todas las reglas del PDF | Ajustar `PRUEBAS` en `tests_fase3.sh` y las listas `*_ALLOW_CIDRS` |
