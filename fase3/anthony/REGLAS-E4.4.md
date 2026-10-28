# Reglas E4.4 — SG, NACL, rutas, NAT y firewall del SO

**Para Majo** (las aplica en la consola). Estado de todo lo que sigue: **propuesto**. Pasa a
**configurado** cuando Majo lo crea y a **probado** con el CSV de `tests_fase3.sh`.

Reglas de trabajo (sección 2 del reparto):
- **Antes de cada paso:** captura del estado previo (o exportar el SG a CSV) y del saldo.
- **Después de cada paso:** la **comprobación** que se indica. Como mínimo, que el endpoint
  siga abriendo SSH a **TI**. Si algo falla, se aplica la **reversión** de ese paso y se avisa a Anthony.
- Al terminar: **Stop** de las instancias (nunca Terminate). No borrar recursos sin acuerdo del grupo.

Nombres que se usan: **SG-TI**, **SG-Servidores** (ya existen) · **SG-NAT**, **SG-Medicos**,
**SG-Visitantes** (nuevos) · **Hospital-RT-Publica** (DMZ) · **Hospital-RT-Privada** (Médicos,
Servidores, Visitantes, TI) · NACL de **Visitantes**.

---

## Paso 0 — Estado inicial (solo lectura, capturas)

| Elemento | Valor actual (verificado el 28/10) |
|---|---|
| Rutas | Ambas tablas: **solo** `10.0.0.0/24 → local`. Sin IGW ni NAT |
| SG-TI | Entrada: SSH (22) desde SG-TI. Salida: todo IPv4 |
| SG-Servidores | Entrada: SSH (22) e ICMP desde SG-TI. **Salida: ninguna regla** |
| NACL Visitantes | Entrada y salida: `100 DENY 10.0.0.0/24` · `110 DENY 10.8.0.0/24` · `120 ALLOW 0.0.0.0/0` · `* DENY` |
| NACL del resto de subredes | La predeterminada de la VPC (todo permitido). **No se cambia** |
| Endpoint | `Hospital-EC2-Connect` en TI (`10.0.0.122`), SG-TI, *Preserve client IP* = No |

Capturas: `E4.4_estado_inicial_rutas.png`, `E4.4_estado_inicial_SG-Servidores.png`,
`E4.4_estado_inicial_NACL-Visitantes.png`.

---

## Paso 1 — Crear los SG nuevos (no afecta nada de lo que ya funciona)

**SG-NAT** (VPC Hospital-Castillejos-VPC):

| Dirección | Tipo | Protocolo | Puerto | Origen/Destino | Descripción |
|---|---|---|---|---|---|
| Entrada | HTTP | TCP | 80 | `10.0.0.0/24` | Tráfico de la VPC a reenviar a Internet (apt) |
| Entrada | HTTPS | TCP | 443 | `10.0.0.0/24` | Tráfico de la VPC a reenviar a Internet |
| Entrada | SSH | TCP | 22 | **SG-TI** | Administración por el endpoint |
| Salida | Todo | Todo | Todo | `0.0.0.0/0` | Predeterminada |

> **Nada** desde `0.0.0.0/0` en la entrada: la NAT tiene IP pública, pero no acepta conexiones
> iniciadas desde Internet. **Sin ICMP**: si no, VIS-10 (Visitantes no llega a la DMZ) fallaría.

**SG-Medicos** y **SG-Visitantes** (para las EC2 de prueba):

| Dirección | Tipo | Protocolo | Puerto | Origen/Destino | Descripción |
|---|---|---|---|---|---|
| Entrada | SSH | TCP | 22 | **SG-TI** | TI llega a todas las subredes / endpoint |
| Salida | Todo | Todo | Todo | `0.0.0.0/0` | Predeterminada |

- Reversión: borrar los SG nuevos, cuando ya no los use ninguna instancia.
- Comprobación: ninguna, porque todavía no se usan.

---

## Paso 2 — Completar SG-Servidores

**Entrada** (las dos primeras ya existen):

| Tipo | Protocolo | Puerto | Origen | Descripción |
|---|---|---|---|---|
| SSH | TCP | 22 | SG-TI | *(existe)* administración |
| Todo ICMP-IPv4 | ICMP | — | SG-TI | *(existe)* ping desde TI |
| HTTP | TCP | 80 | `10.0.0.0/27` | Intranet desde Médicos |
| HTTP | TCP | 80 | `10.0.0.32/27` | Intranet desde Servidores |
| HTTP | TCP | 80 | `10.0.0.96/28` | Intranet desde DMZ |
| HTTP | TCP | 80 | `10.0.0.112/28` | Intranet desde TI |
| LDAP | TCP | 389 | `10.0.0.32/27` | LDAP desde Servidores |
| LDAP | TCP | 389 | `10.0.0.112/28` | LDAP desde TI (pruebas) |
| NTP | UDP | 123 | `10.0.0.0/27` | NTP Médicos |
| NTP | UDP | 123 | `10.0.0.32/27` | NTP Servidores |
| NTP | UDP | 123 | `10.0.0.96/28` | NTP DMZ/NAT |
| NTP | UDP | 123 | `10.0.0.112/28` | NTP TI |

**Visitantes (`10.0.0.64/27`) no aparece en ninguna regla.**

**Salida** (hoy no tiene ninguna):

| Tipo | Protocolo | Puerto | Destino | Descripción |
|---|---|---|---|---|
| HTTP | TCP | 80 | `0.0.0.0/0` | `apt` por la NAT |
| HTTPS | TCP | 443 | `0.0.0.0/0` | `apt` por la NAT |
| NTP | UDP | 123 | `169.254.169.123/32` | Amazon Time Sync (por seguridad; ver §6) |

> Las **respuestas** a conexiones entrantes permitidas (intranet, LDAP, NTP, SSH) no necesitan regla de
> salida: el SG es stateful. Sin salida hacia TI, Servidores tampoco puede iniciar nada hacia TI (SRV-01).

- Reversión: borrar las reglas nuevas, dejando solo SSH e ICMP de entrada.
- Comprobación: desde el endpoint, SSH a TI y luego a Servidores (`10.0.0.46`). Deben funcionar igual que antes.

---

## Paso 3 — Internet Gateway y ruta pública

1. Crear un **Internet Gateway** (`Hospital-IGW`) y **asociarlo** a la VPC.
2. En **Hospital-RT-Publica** (DMZ) agregar `0.0.0.0/0 → Hospital-IGW`.

- Reversión: quitar la ruta, desasociar el IGW y (con acuerdo del grupo) borrarlo.
- Comprobación: SSH a TI por el endpoint sigue funcionando. La ruta `local` no cambia.

---

## Paso 4 — NAT instance en la DMZ

1. Lanzar **Ubuntu 24.04** en la subred **DMZ** (`10.0.0.96/28`), con el tipo que salga más barato en
   la tabla de precios (t3.nano o t3.micro), **SG-NAT** y **IP pública**
   (*Auto-assign public IP: Enable*, o una Elastic IP).
   - Costo: la IPv4 pública se cobra por hora. Una **Elastic IP se sigue cobrando con la instancia
     detenida**; la IP automática se libera al hacer Stop.
2. Instancia → *Redes* → **Cambiar comprobación de origen/destino → Detener** (desactivar
   *source/dest check*).
3. Anotar su IP privada: es `IP_NAT` = `IP_DMZ` en `fase3.env`.
4. Por el endpoint, en la NAT: `sudo bash nat-instance.sh` → `RESULTADO: OK`, "La NAT tiene Internet (HTTP 200)".

- Reversión: `sudo bash nat-instance.sh --revertir` y Stop de la instancia.
- Comprobación: `nat-instance.sh` OK, y SSH a TI sigue funcionando.

---

## Paso 5 — Ruta privada hacia la NAT

En **Hospital-RT-Privada** agregar `0.0.0.0/0 →` **la instancia NAT** (o su interfaz de red).

- Reversión: quitar esa ruta.
- Comprobación:
  - En TI: `curl -sS -m 8 -o /dev/null -w '%{http_code}\n' https://example.com` → `200`.
  - En Servidores, lo mismo: `200` confirma la salida 443 del Paso 2.
  - Si falla: *source/dest check* sigue activo, falta la ruta, o SG-NAT no tiene 443 desde la VPC.

---

## Paso 6 — NACL de Visitantes: excepción para TI

**Entrada:**

| Regla | Tipo | Protocolo | Puertos | Origen | Acción |
|---|---|---|---|---|---|
| **90** | SSH | TCP | 22 | `10.0.0.112/28` | **ALLOW** *(nueva)* |
| 100 | Todo | Todo | Todo | `10.0.0.0/24` | DENY |
| 110 | Todo | Todo | Todo | `10.8.0.0/24` | DENY |
| 120 | Todo | Todo | Todo | `0.0.0.0/0` | ALLOW |
| * | Todo | Todo | Todo | `0.0.0.0/0` | DENY |

**Salida:**

| Regla | Tipo | Protocolo | Puertos | Destino | Acción |
|---|---|---|---|---|---|
| **90** | TCP personalizado | TCP | 1024-65535 | `10.0.0.112/28` | **ALLOW** *(nueva: respuestas del SSH a TI)* |
| 100 | Todo | Todo | Todo | `10.0.0.0/24` | DENY |
| 110 | Todo | Todo | Todo | `10.8.0.0/24` | DENY |
| 120 | Todo | Todo | Todo | `0.0.0.0/0` | ALLOW |
| * | Todo | Todo | Todo | `0.0.0.0/0` | DENY |

> **¿Y la NAT?** No necesita regla. Lo que Visitantes manda a Internet lleva **destino público** (por
> ejemplo `1.1.1.1`); la NAT es solo el siguiente salto de la ruta. La regla 100 no lo afecta y la
> 120 lo deja pasar, y la respuesta también entra por la 120. Lo comprueban VIS-11/12.
>
> La salida 90 deja que Visitantes **envíe** paquetes a puertos altos de TI, pero **SG-TI** los descarta.

- Reversión: borrar las reglas 90 de entrada y salida.
- Comprobación: después del Paso 7, SSH desde el endpoint a la EC2 de Visitantes.

---

## Paso 7 — EC2 de prueba en Médicos y Visitantes

Ubuntu 24.04, el tipo más barato de la tabla, **sin IP pública**:
- Médicos (`10.0.0.0/27`) con **SG-Medicos**.
- Visitantes (`10.0.0.64/27`) con **SG-Visitantes**.

Anotar sus IP en `fase3.env` (`IP_MEDICOS`, `IP_VISITANTES`).

- Comprobación: SSH por el endpoint a cada una (TI-06/TI-07). En Visitantes, `curl https://example.com` → `200`.

---

## Paso 8 — Servicios y firewall del SO (scripts)

Orden de `fase3/leonardo/README.md` §1:
1. NAT
2. `chrony-servidor.sh`
3. LDAP (Sebastián)
4. Apache (Isabella)
5. `chrony-cliente.sh` (Visitantes con `NTP_SERVER=169.254.169.123`)
6. `hardening.sh <rol>`: **TI al final**
7. `tests_fase3.sh <origen>` en cada EC2

Firewall del SO (ufw) que deja `hardening.sh`:

| Rol / instancia | Entrada permitida por ufw |
|---|---|
| `servidores` (`10.0.0.46`) | 22 desde `10.0.0.112/28` · 80 desde Médicos, Servidores, DMZ y TI · 389 desde Servidores y TI · 123/udp desde la VPC |
| `nat` | 22 desde `10.0.0.112/28` (el reenvío lo maneja la cadena `FASE3-NAT`) |
| `ti`, `cliente` (Médicos, Visitantes) | 22 desde `10.0.0.112/28` |
| Todos | `deny incoming`, `allow outgoing`. SSH sin contraseña ni root |

---

## Paso 9 — Cierre

1. CSV de cada `tests_fase3.sh` y archivos `hardening-*` → Roberto.
2. Pruebas manuales EXT-01/02 desde una laptop (ver MATRIZ §2).
3. **Stop** de NAT, Médicos, Visitantes, TI y Servidores. Captura del estado final y del costo.
   - Si se usó Elastic IP: avisar al grupo, porque sigue cobrando aunque la instancia esté detenida.

---

## 6. Tráfico que AWS no filtra (para el informe)

Según la guía de VPC (*Network ACLs* y *Security groups*), las **NACL y los SG no filtran** el
tráfico hacia y desde estos servicios de AWS:
- Amazon DNS (el resolver de la VPC, `10.0.0.2`)
- DHCP
- metadatos de la instancia (`169.254.169.254`)
- **Amazon Time Sync Service** (`169.254.169.123`)
- las direcciones reservadas del router de la VPC

Por eso Visitantes resuelve nombres y sincroniza la hora aunque su NACL deniegue `10.0.0.0/24`. La
regla de salida UDP 123 de SG-Servidores se deja por seguridad.

**Verificar el texto exacto antes de citarlo:**
- https://docs.aws.amazon.com/vpc/latest/userguide/vpc-network-acls.html
- https://docs.aws.amazon.com/vpc/latest/userguide/vpc-security-groups.html

## 7. Resumen de reversión (de atrás hacia adelante)

| Paso | Cómo revertir |
|---|---|
| 8 | `hardening.sh --revertir`, `chrony-*.sh --revertir`, `nat-instance.sh --revertir` |
| 7 | Stop de las EC2 de prueba |
| 6 | Borrar las reglas 90 (entrada y salida) de la NACL de Visitantes |
| 5 | Quitar `0.0.0.0/0` de Hospital-RT-Privada |
| 4 | Stop de la NAT (y, con acuerdo, liberar la Elastic IP) |
| 3 | Quitar `0.0.0.0/0` de Hospital-RT-Publica y desasociar el IGW |
| 2 | Dejar SG-Servidores solo con SSH e ICMP desde SG-TI |
| 1 | Borrar SG-NAT, SG-Medicos y SG-Visitantes (cuando no estén en uso) |
