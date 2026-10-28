# Matriz de flujos E4.2 / E4.3 — Hospital Privado Castillejos

Subredes: **Médicos** `10.0.0.0/27` · **Servidores** `10.0.0.32/27` · **Visitantes** `10.0.0.64/27` ·
**DMZ** `10.0.0.96/28` · **TI** `10.0.0.112/28`.

Equipos: TI `10.0.0.117` y endpoint `10.0.0.122` · Servidores `10.0.0.46` · NAT Gateway `Hospital-NAT` (DMZ) · EC2 de prueba en
Médicos y en Visitantes.

La columna **Prueba** es el ID de `fase3/leonardo/tests_fase3.sh`. Cada fila es una prueba de su CSV.
**Lo aplica** indica qué capa permite o bloquea el flujo. Si hay varias, la primera es la principal y
las demás son defensa en profundidad.

Abreviaturas: SG = Security Group (stateful) · NACL = Network ACL (stateless) · ufw = firewall del SO
(`hardening.sh`) · Apache = `Require ip` / `Require ldap-group`.

## 1. Reglas del PDF → cómo se cumplen

| Regla del PDF | Cómo se cumple | Pruebas |
|---|---|---|
| SSH a las instancias | Solo por el EC2 Instance Connect Endpoint (SG-TI). Cada SG acepta 22 **desde SG-TI** | TI-01, TI-06, TI-07, TI-08 |
| Visitantes con Internet pero sin acceso a las demás subredes | NACL Visitantes: deniega `10.0.0.0/24` en ambos sentidos. Internet por la NAT (el destino es una IP pública, la NACL lo permite) | VIS-01…VIS-12 |
| TI llega a todas las subredes, ninguna llega a TI | SG-Medicos, SG-Visitantes, SG-DMZ (EC2 opcional) y SG-Servidores aceptan 22 desde SG-TI. **SG-TI** solo acepta 22 desde sí mismo (el endpoint). NACL Visitantes: excepción para TI | TI-06…TI-08 · SRV-01, MED-01/02, VIS-01/07, DMZ-01 |
| Intranet desde todas las subredes excepto Visitantes, y no desde Internet | SG-Servidores 80 desde Médicos, Servidores, DMZ y TI. Servidores sin IP pública ni ruta de entrada. ufw y `Require ip` repiten la lista | TI-02, SRV-02, MED-03, DMZ-02 · VIS-02 · EXT-02 |
| NAT | **NAT Gateway** `Hospital-NAT` en la DMZ (Elastic IP). IGW + `0.0.0.0/0 → IGW` en la tabla pública y `0.0.0.0/0 → NAT` en la privada | VIS-11, VIS-12 · `apt`/`curl` desde TI y Servidores |
| Cerrar puertos no usados (hardening) | Cada SG con lo mínimo. ufw `deny incoming` + puertos del rol. SSH sin contraseña ni root | `hardening-antes/después-<host>.txt` |
| DHCP, NTP, LDAP | DHCP de AWS. chrony en Servidores. OpenLDAP en Servidores | E5.1–E5.2 (Roberto), TI-04, MED-05, DMZ-03, SRV-03, VIS-13, TI-03 |

## 2. Matriz por origen

`→` = quien inicia la conexión. Las respuestas a una conexión permitida vuelven solas en los SG
(stateful). En la NACL de Visitantes hay que permitirlas a mano (stateless, ver §3).

### Desde TI (`10.0.0.112/28`)

| Prueba | Destino | Protocolo/puerto | Esperado | Lo aplica |
|---|---|---|---|---|
| TI-01 | Servidores | TCP 22 | permitido | SG-Servidores (22 desde SG-TI) · ufw servidores |
| TI-02 | Servidores | TCP 80 | permitido | SG-Servidores (80 desde `10.0.0.112/28`) · ufw · Apache `Require ip` |
| TI-03 | Servidores | TCP 389 | permitido | SG-Servidores (389 desde `10.0.0.112/28`) · ufw |
| TI-04 | Servidores | UDP 123 | permitido | SG-Servidores (123 desde `10.0.0.112/28`) · ufw · chrony `allow` |
| TI-05 | Servidores | ICMP | permitido | SG-Servidores (ICMP desde SG-TI, ya existe) |
| TI-06 | Médicos | TCP 22 | permitido | SG-Medicos (22 desde SG-TI) |
| TI-07 | Visitantes | TCP 22 | permitido | **NACL Visitantes regla 90** (entrada 22 desde TI) y 90 (salida efímeros a TI) · SG-Visitantes |
| TI-08 | DMZ (EC2 opcional) | TCP 22 | permitido | SG-DMZ (22 desde SG-TI). OMITIDA si no hay EC2 en la DMZ |
| — | Internet | TCP 80/443 | permitido | Ruta privada → NAT Gateway. Se ve con `apt update` / `curl https://example.com` |

### Desde Servidores (`10.0.0.32/27`)

| Prueba | Destino | Protocolo/puerto | Esperado | Lo aplica |
|---|---|---|---|---|
| SRV-01 | TI | TCP 22 | **bloqueado** | SG-Servidores (sin salida hacia TI) · **SG-TI** (solo acepta desde sí mismo) |
| SRV-02 | Servidores (sí mismo) | TCP 80 | permitido | SG-Servidores (80 desde `10.0.0.32/27`) |
| SRV-03 | Amazon Time Sync | UDP 123 | permitido | No lo filtran SG ni NACL (servicio de AWS, ver REGLAS §6) · regla de salida explícita por seguridad |
| — | Internet | TCP 80/443 | permitido | **SG-Servidores salida 80/443** (agregada el 28/10) · NAT Gateway |

### Desde Médicos (`10.0.0.0/27`)

| Prueba | Destino | Protocolo/puerto | Esperado | Lo aplica |
|---|---|---|---|---|
| MED-01 | TI | TCP 22 | **bloqueado** | SG-TI |
| MED-02 | TI | ICMP | **bloqueado** | SG-TI |
| MED-03 | Servidores | TCP 80 | permitido | SG-Servidores (80 desde `10.0.0.0/27`) · ufw · Apache |
| MED-04 | Servidores | TCP 389 | **bloqueado** | SG-Servidores (389 no incluye Médicos) · ufw |
| MED-05 | Servidores | UDP 123 | permitido | SG-Servidores (123 desde `10.0.0.0/27`) · ufw |
| — | Internet | TCP 80/443 | permitido | NAT |

### Desde Visitantes (`10.0.0.64/27`)

| Prueba | Destino | Protocolo/puerto | Esperado | Lo aplica |
|---|---|---|---|---|
| VIS-01 | TI | TCP 22 | **bloqueado** | **NACL Visitantes salida 100** (deniega `10.0.0.0/24`) · SG-TI |
| VIS-02 | Servidores | TCP 80 | **bloqueado** | NACL salida 100 · SG-Servidores (80 no incluye Visitantes) · ufw · Apache |
| VIS-03 | Servidores | TCP 22 | **bloqueado** | NACL salida 100 · SG-Servidores |
| VIS-04 | Servidores | TCP 389 | **bloqueado** | NACL salida 100 · SG-Servidores |
| VIS-05 | Médicos | TCP 22 | **bloqueado** | NACL salida 100 · SG-Medicos |
| VIS-06 | DMZ (EC2 opcional) | TCP 22 | **bloqueado** | NACL salida 100 · SG-DMZ (22 solo desde SG-TI). OMITIDA sin EC2 en la DMZ |
| VIS-07…10 | TI, Servidores, Médicos, DMZ | ICMP | **bloqueado** | NACL salida 100 · SG destino (SG-Medicos y SG-DMZ **no** aceptan ICMP). VIS-10 OMITIDA sin EC2 en la DMZ |
| VIS-11 | Internet `1.1.1.1` | TCP 443 | permitido | NACL salida 120 (destino público) · ruta → NAT Gateway |
| VIS-12 | Internet `example.com` | HTTPS | permitido | ídem |
| VIS-13 | Amazon Time Sync | UDP 123 | permitido | No lo filtra la NACL (servicio de AWS) |

### Desde la DMZ (`10.0.0.96/28`) — solo con la EC2 opcional de la DMZ

| Prueba | Destino | Protocolo/puerto | Esperado | Lo aplica |
|---|---|---|---|---|
| DMZ-01 | TI | TCP 22 | **bloqueado** | SG-TI |
| DMZ-02 | Servidores | TCP 80 | permitido | SG-Servidores (80 desde `10.0.0.96/28`) · ufw · Apache |
| DMZ-03 | Servidores | UDP 123 | permitido | SG-Servidores (123 desde `10.0.0.96/28`) |
| NAT-01…03 | — | — | **OMITIDA** | Eran para una NAT instance. Con NAT Gateway no hay instancia que pruebe (`IP_NAT` vacío) |

Sin EC2 en la DMZ, DMZ-01…03 también quedan OMITIDAS. En el informe se explica que la DMZ solo
aloja el NAT Gateway (servicio de AWS) y que la web pública de Fase 1 queda fuera del alcance.

### Desde Internet

| Prueba | Destino | Protocolo/puerto | Esperado | Lo aplica |
|---|---|---|---|---|
| EXT-01 | Elastic IP del NAT Gateway | TCP 22, 80, ICMP | **bloqueado** | El NAT Gateway solo deja pasar respuestas a conexiones iniciadas desde dentro (no acepta conexiones entrantes) |
| EXT-02 | Intranet / Servidores | cualquiera | **bloqueado** | Servidores **sin IP pública**. La ruta pública solo sale. La NAT no reenvía conexiones nuevas desde fuera |

EXT-01 y EXT-02 no están en `tests_fase3.sh`. Roberto las corre **manualmente** desde una laptop con
Internet: `Test-NetConnection <Elastic IP del NAT Gateway> -Port 22` y `-Port 80`, que deben dar `TcpTestSucceeded : False`.
En la consola se capturan "IPv4 pública: —" de Servidores y la tabla de rutas privada.

## 3. Quién bloquea qué (E4.3)

- **SG-TI** hace cumplir "ninguna subred llega a TI": solo acepta SSH desde sí mismo (el endpoint).
  Las respuestas a lo que TI inicia vuelven porque el SG es stateful.
- **NACL de Visitantes** es la primera barrera de "Visitantes no llega a ninguna subred". Al ser
  stateless, deniega `10.0.0.0/24` en entrada y salida. Por eso hacen falta **dos excepciones para
  TI** (regla 90 de entrada TCP 22 y regla 90 de salida TCP 1024-65535): sin ellas, TI-07 y la
  administración de la EC2 de Visitantes por el endpoint fallan.
  - La excepción de salida deja que Visitantes **envíe** paquetes a puertos altos de TI. Igual no
    conecta: **SG-TI** los descarta (solo acepta 22 desde sí mismo).
- **El NAT Gateway no necesita excepción en la NACL.** El tráfico de Visitantes hacia Internet viaja con
  destino a la IP pública (por ejemplo `1.1.1.1`); la NAT es solo el siguiente salto de la ruta. La
  regla 100 (`10.0.0.0/24`) no lo afecta y la 120 lo permite. La respuesta vuelve con origen público
  y también entra por la 120. Lo comprueban **VIS-11/12**.
- **SG-Servidores** define quién usa cada servicio: 80 sin Visitantes, 389 solo Servidores y TI, 123
  sin Visitantes. **ufw** y **Apache `Require ip`** repiten la misma lista (defensa en profundidad).
- **Internet** no inicia nada: ninguna instancia tiene IP pública; la única es la Elastic IP del NAT Gateway, que no acepta
  conexiones entrantes.

## 4. Pruebas que conviene agregar (opcionales)

| ID sugerido | Origen → destino | Esperado | Motivo |
|---|---|---|---|
| MED-06 | Médicos → Servidores TCP 22 | bloqueado | SSH solo desde TI |
| MED-07 | Médicos → Visitantes TCP 22 | bloqueado | Visitantes aislada en ambos sentidos (NACL entrada 100) |
| TI-09 | TI → Internet HTTPS | permitido | La NAT da salida a TI (`apt`) |
| EXT-01/02 | Internet → NAT / intranet | bloqueado | Ver §2 |
