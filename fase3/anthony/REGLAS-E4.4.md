# Reglas E4.4 — SG, NACL, rutas, NAT y firewall del SO

**Para Majo** (las aplica en la consola). **Actualizado el 28/10** con lo que ya está hecho según el
informe en curso: **NAT Gateway** (no NAT instance), IGW y rutas ya creados.

Estado de cada paso: ✅ **hecho** (visto en el informe) · ⏳ **pendiente**. Lo hecho pasa a
**probado** con el CSV de `tests_fase3.sh`.

Reglas de trabajo (sección 2 del reparto):
- **Antes de cada paso:** captura del estado previo y del saldo.
- **Después de cada paso:** la **comprobación** indicada. Como mínimo, que el endpoint siga
  abriendo SSH a **TI**. Si algo falla, aplicar la **reversión** de ese paso y avisar a Anthony.
- Al terminar: **Stop** de las instancias (nunca Terminate). El **NAT Gateway no se detiene**: se
  elimina al final, con acuerdo del grupo (Paso 9).

Nombres: **SG-TI**, **SG-Servidores** (existen) · **SG-Medicos**, **SG-Visitantes**, **SG-DMZ** (nuevos;
SG-DMZ solo si se lanza la EC2 opcional de la DMZ) · **Hospital-RT-Publica** (DMZ) ·
**Hospital-RT-Privada** (Médicos, Servidores, Visitantes, TI) · **Hospital-NACL-Visitantes** ·
**Hospital-IGW** · **Hospital-NAT**.

---

## Paso 0 — Estado inicial ✅

Capturado en el informe:
- rutas solo locales;
- SG-Servidores con entrada SSH/ICMP desde SG-TI y **sin salida**;
- NACL Visitantes 100/110/120/*;
- endpoint en TI (`10.0.0.122`, *Preserve client IP* = No);
- 3 volúmenes EBS de 8 GiB.

Para el informe:
- **ocultar el ID de cuenta y los ARN** en esas capturas (E9.4);
- **corregir el texto de la Fase 2**: SG-Servidores **no tenía** reglas de salida (Imagen 12).

---

## Paso 1 — SG nuevos ⏳ (no afecta nada de lo que funciona)

**SG-Medicos** y **SG-Visitantes** (para las EC2 de prueba) y, si se lanza la EC2 opcional de la DMZ,
**SG-DMZ**:

| Dirección | Tipo | Protocolo | Puerto | Origen/Destino | Descripción |
|---|---|---|---|---|---|
| Entrada | SSH | TCP | 22 | **SG-TI** | TI llega a todas las subredes / endpoint |
| Salida | Todo | Todo | Todo | `0.0.0.0/0` | Predeterminada |

> **Sin ICMP** en la entrada: TI solo necesita SSH, y así VIS-07…10 quedan bloqueados también por el SG.
> El NAT Gateway **no usa** Security Group.

- Reversión: borrar estos SG cuando ya no los use ninguna instancia.

---

## Paso 2 — SG-Servidores

**Salida** ✅ (ya agregada): HTTPS TCP 443 → `0.0.0.0/0` y HTTP TCP 80 → `0.0.0.0/0` ("package downloads").
Opcional: UDP 123 → `169.254.169.123/32`. No hace falta, porque Time Sync no se filtra (ver §6).

**Entrada** ⏳ (agregar a las dos que ya existen):

| Tipo | Protocolo | Puerto | Origen | Descripción |
|---|---|---|---|---|
| SSH | TCP | 22 | SG-TI | *(existe)* administración |
| Todo ICMP-IPv4 | ICMP | — | SG-TI | *(existe)* ping desde TI |
| HTTP | TCP | 80 | `10.0.0.0/27` | Intranet desde Médicos |
| HTTP | TCP | 80 | `10.0.0.32/27` | Intranet desde Servidores |
| HTTP | TCP | 80 | `10.0.0.96/28` | Intranet desde DMZ |
| HTTP | TCP | 80 | `10.0.0.112/28` | Intranet desde TI |
| LDAP | TCP | 389 | `10.0.0.32/27` | LDAP desde Servidores |
| LDAP | TCP | 389 | `10.0.0.112/28` | LDAP desde TI (pruebas y administración) |
| NTP | UDP | 123 | `10.0.0.0/27` | NTP Médicos |
| NTP | UDP | 123 | `10.0.0.32/27` | NTP Servidores |
| NTP | UDP | 123 | `10.0.0.96/28` | NTP DMZ |
| NTP | UDP | 123 | `10.0.0.112/28` | NTP TI |

**Visitantes (`10.0.0.64/27`) no aparece en ninguna regla.** La intranet va por **HTTP 80**, no 443:
corregir la tabla de flujos del informe, que dice TCP/443.

- Reversión: dejar en la entrada solo SSH e ICMP desde SG-TI.
- Comprobación: SSH a TI y a Servidores por el endpoint, igual que antes.

### Paso 2b — slapd debe escuchar en todas las interfaces ⏳

En Servidores se editó `/etc/default/slapd` y slapd quedó escuchando **solo en `127.0.0.1:389`**.
Según D5, debe escuchar en todas las interfaces, y lo filtran el SG (arriba) y ufw (`hardening.sh`).
Si no, TI-03 falla.

```bash
grep -n '^SLAPD_SERVICES' /etc/default/slapd              # anotar el valor actual (para revertir)
sudo sed -i 's|^SLAPD_SERVICES=.*|SLAPD_SERVICES="ldap:/// ldapi:///"|' /etc/default/slapd
sudo systemctl restart slapd
sudo ss -lntp | grep ':389 '                               # 0.0.0.0:389
```
- Reversión: volver a poner el valor anotado y reiniciar slapd.

### Paso 2c — usar los scripts de Sebastián para el LDAP ⏳

La base y las OUs se crearon a mano. Hay que cargar **con los scripts de Sebastián**: los usuarios
`ti01`, `medico01`, `laboratorio01`…, los grupos con `memberUid` y **`svc-intranet`, que la intranet de
Isabella necesita**. Su instalador detecta la base existente y **no borra nada**. Orden y contraseñas:
`fase3/sebastian/README.md`.

En el informe, cambiar la tabla de usuarios `ti_prueba`/`medico_prueba`/`lab_prueba` por los de
Sebastián (`fase3/sebastian/usuarios-ficticios.csv`).

---

## Paso 3 — Internet Gateway y ruta pública ✅

`Hospital-IGW` asociado a la VPC. `Hospital-RT-Publica`: `0.0.0.0/0 → Hospital-IGW` (activa).

- Reversión: quitar la ruta y desasociar el IGW.

## Paso 4 — NAT Gateway ✅

`Hospital-NAT` (público, zonal, subred DMZ, Elastic IP), creado el 28/10 a las 14:59 CST.
Comprobar en la consola que su estado sea **Available**: en la captura del informe estaba *Pending*.

- Reversión / cierre: ver Paso 9.

## Paso 5 — Ruta privada hacia la NAT ✅

`Hospital-RT-Privada`: `0.0.0.0/0 → Hospital-NAT` (activa).

- Comprobación ⏳ (captura para el informe), en TI y en Servidores:
  `curl -sS -m 8 -o /dev/null -w '%{http_code}\n' https://example.com` → `200`.
  Si TI da 200 y Servidores no, falta la salida 443 en SG-Servidores.

---

## Paso 6 — NACL de Visitantes: excepción para TI ⏳

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

> **El NAT Gateway no necesita regla.** Lo que Visitantes manda a Internet lleva **destino público**
> (por ejemplo `1.1.1.1`); el NAT es solo el siguiente salto de la ruta. La regla 100 no lo afecta y
> la 120 lo permite, y la respuesta también entra por la 120. Lo comprueban VIS-11/12.
>
> La salida 90 deja que Visitantes **envíe** paquetes a puertos altos de TI, pero **SG-TI** los descarta.

- Reversión: borrar las reglas 90 de entrada y salida.

---

## Paso 7 — EC2 de prueba ⏳

Ubuntu 24.04, tipo t3.micro (o el más barato), **sin IP pública**:
- Médicos (`10.0.0.0/27`) con **SG-Medicos**.
- Visitantes (`10.0.0.64/27`) con **SG-Visitantes**.
- *(Opcional)* DMZ (`10.0.0.96/28`) con **SG-DMZ**. Sin ella, DMZ-01…03, TI-08, VIS-06 y VIS-10 quedan OMITIDAS.

Anotar las IP en `fase3.env`: `IP_MEDICOS`, `IP_VISITANTES` y, si existe, `IP_DMZ`. **`IP_NAT` vacío.**

- Comprobación: SSH por el endpoint a cada una (TI-06/TI-07). En Visitantes, `curl https://example.com` → `200`.

---

## Paso 8 — Servicios y firewall del SO (scripts) ⏳

Orden (de `fase3/leonardo/README.md` §1, **sin** `nat-instance.sh` ni `hardening.sh nat`):
1. `chrony-servidor.sh` en Servidores
2. LDAP con los scripts de Sebastián (Paso 2c)
3. Intranet: `isabella/instalar-web.sh`
4. `chrony-cliente.sh` en TI, Médicos y DMZ; Visitantes con `NTP_SERVER=169.254.169.123`
5. `hardening.sh servidores` / `cliente` / **`ti` al final**
6. `tests_fase3.sh <origen>` en cada EC2

| Rol / instancia | Entrada permitida por ufw |
|---|---|
| `servidores` (`10.0.0.46`) | 22 desde `10.0.0.112/28` · 80 desde Médicos, Servidores, DMZ y TI · 389 desde Servidores y TI · 123/udp desde la VPC |
| `ti`, `cliente` (Médicos, Visitantes, DMZ) | 22 desde `10.0.0.112/28` |
| Todos | `deny incoming`, `allow outgoing`. SSH sin contraseña ni root |

---

## Paso 9 — Cierre ⏳

1. CSV de cada `tests_fase3.sh` y archivos `hardening-*` → Roberto. Pruebas manuales EXT-01/02 (MATRIZ §2).
2. **Stop** de TI, Servidores y las EC2 de prueba. Captura del estado final.
3. **NAT Gateway:** se cobra por hora mientras exista, aunque todo lo demás esté detenido. **Después de la
   demo**, y con acuerdo del grupo:
   - eliminar `Hospital-NAT`;
   - liberar su **Elastic IP** (que también se cobra);
   - quitar la ruta `0.0.0.0/0` de `Hospital-RT-Privada`, que queda como *blackhole*.

   Si la demo es otro día: o se recrea, o se deja corriendo sabiendo el costo. Registrar el costo
   final (Bills).

---

## 6. Tráfico que AWS no filtra (para el informe)

Según la guía de VPC (*Network ACLs* y *Security groups*), las **NACL y los SG no filtran** el
tráfico hacia y desde estos servicios de AWS:
- Amazon DNS (el resolver de la VPC, `10.0.0.2`)
- DHCP
- metadatos de la instancia (`169.254.169.254`)
- **Amazon Time Sync Service** (`169.254.169.123`)
- las direcciones reservadas del router de la VPC

Por eso Visitantes resuelve nombres y sincroniza la hora aunque su NACL deniegue `10.0.0.0/24`.

**Verificar el texto exacto antes de citarlo:**
- https://docs.aws.amazon.com/vpc/latest/userguide/vpc-network-acls.html
- https://docs.aws.amazon.com/vpc/latest/userguide/vpc-security-groups.html
- NAT Gateway: https://docs.aws.amazon.com/vpc/latest/userguide/vpc-nat-gateway.html

## 7. Resumen de reversión (de atrás hacia adelante)

| Paso | Cómo revertir |
|---|---|
| 8 | `hardening.sh --revertir`, `chrony-*.sh --revertir` |
| 7 | Stop de las EC2 de prueba |
| 6 | Borrar las reglas 90 (entrada y salida) de la NACL de Visitantes |
| 5 | Quitar `0.0.0.0/0` de Hospital-RT-Privada |
| 4 | Eliminar `Hospital-NAT` y liberar su Elastic IP (con acuerdo del grupo) |
| 3 | Quitar `0.0.0.0/0` de Hospital-RT-Publica y desasociar el IGW |
| 2b | Volver a poner el `SLAPD_SERVICES` anotado y reiniciar slapd |
| 2 | Dejar SG-Servidores solo con SSH e ICMP de entrada y sin salida (estado de Fase 2) |
| 1 | Borrar SG-Medicos, SG-Visitantes y SG-DMZ (cuando no estén en uso) |
