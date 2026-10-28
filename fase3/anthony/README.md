# Fase 3 — Diseño, reglas y diagrama (Anthony)

Hospital Privado Castillejos · CC3067 Redes · AWS us-east-1 · VPC `10.0.0.0/24`

Casillas: E2.5, E2.6, E4.1, E4.2, E4.3, E4.4, E10.1, E10.5 (borrador).

| Archivo | Contenido | Para quién |
|---|---|---|
| `README.md` | Decisiones (E2.5/E2.6) y servicios por instancia (E4.1) | Todos |
| `MATRIZ-E4.2.md` | Matriz de flujos de las 5 subredes y quién bloquea qué (E4.2/E4.3) | Roberto, Leonardo |
| `REGLAS-E4.4.md` | Reglas concretas de SG, NACL, rutas, NAT y firewall del SO, con valor anterior y reversión | **Majo** (aplica), todos |
| `DIAGRAMA-E10.1.md` | Diagrama propuesto / configurado / probado | Informe y presentación |
| `GUION-E10.5.md` | Borrador de la presentación ejecutiva y orden de la demo | Todos |

**Estados** que se usan en todos los documentos:
- **propuesto**: diseñado, todavía no creado en AWS.
- **configurado**: existe en AWS o en la instancia, sin prueba que lo demuestre.
- **probado**: hay una prueba con evidencia (CSV de `tests_fase3.sh`, captura o salida).

Al 28/10 solo está **probado** lo de Fase 2: SSH e ICMP de TI a Servidores, y TCP/22 de Servidores a TI bloqueado.

---

## 1. Decisiones (E2.5)

| # | Decisión | Motivo | Impacto en los scripts |
|---|---|---|---|
| D1 | Dominio y base LDAP: **`hospital.redes.test`** / **`dc=hospital,dc=redes,dc=test`** | Es la base que se implementó y probó en el Lab 5, y la que ya usan Sebastián y Leonardo. Reemplaza al `hospital.internal` de Fase 1, que solo era un nombre propuesto para una zona DNS que no se creó. | Ninguno: coincide con `LDAP_BASE` y `LDAP_BASE_DN`. |
| D2 | **NAT instance** en la DMZ (no NAT Gateway) | Usa el `nat-instance.sh` de Leonardo, ya probado localmente. Sirve además como equipo de prueba de la DMZ y demuestra iptables. El costo final se confirma con la tabla de precios de Majo (pendiente). | `nat-instance.sh` sí se usa. `IP_NAT` = `IP_DMZ` = IP privada de la NAT. |
| D3 | Intranet por **HTTP (TCP 80)** | Es lo que asumen el *hardening*, los tests y la intranet. HTTPS con certificado autofirmado (Fase 1) queda como mejora documentada. | Ninguno: `INTRANET_PORTS=80`, `INTRANET_SCHEME=http`. |
| D4 | LDAP, NTP e intranet en la **misma EC2 Servidores `10.0.0.46`** | El PDF permite juntar servicios. Ahorra costo, y Apache consulta LDAP por `127.0.0.1` sin pasar por el SG. | — |
| D5 | **LDAP 389 solo desde Servidores y TI** | Contrato de Sebastián. Los clientes no consultan LDAP directamente: se autentican en la intranet. | `LDAP_ALLOW_CIDRS` igual; MED-04 y VIS-04 bloqueados. |
| D6 | **DHCP: el de AWS** (DHCP option set de la VPC, sin cambios) | AWS no permite un servidor DHCP propio en la VPC. Se documenta lo que recibe una EC2 (Roberto, E5.1/E5.2). Un option set propio (por ejemplo, entregar NTP `10.0.0.46`) es **opcional** y no es necesario para cumplir. | Ninguno. |
| D7 | **NTP**: chrony en Servidores (fuente Amazon Time Sync `169.254.169.123`). Los clientes de Médicos, TI, DMZ y NAT apuntan a `10.0.0.46`. **Visitantes usa Amazon Time Sync directo** | La regla "Visitantes no llega a otras subredes" le impide llegar a `10.0.0.46`. | Ya contemplado (VIS-13). |
| D8 | **SSH** a todas las instancias **solo por el EC2 Instance Connect Endpoint** (`10.0.0.122`, SG-TI) | Ninguna instancia acepta SSH desde Internet. La NAT tiene IP pública pero su SG no acepta nada iniciado desde Internet. | `SSH_ALLOW_CIDRS=10.0.0.112/28`. |
| D9 | **Internet** (por la NAT) solo **TCP 80/443** | Alcanza para `apt` y para la navegación de Visitantes. Cierra todo lo demás (*hardening*). | SG-NAT. Los tests usan 443. |

## 2. Dominio, base LDAP, grupos y usuarios (E2.6)

| Elemento | Valor |
|---|---|
| Dominio | `hospital.redes.test` |
| Base | `dc=hospital,dc=redes,dc=test` |
| Usuarios | `ou=People,dc=hospital,dc=redes,dc=test` |
| Grupos | `ou=Groups,dc=hospital,dc=redes,dc=test` (`posixGroup`, miembros por `memberUid`) |
| Administrador | `cn=admin,dc=hospital,dc=redes,dc=test` (solo se usa en la propia EC2) |
| Cuenta de servicio | `uid=svc-intranet,ou=People,…`: la usa Apache para buscar usuarios. No pertenece a ningún grupo, así que **no puede entrar a la intranet** |
| Servidor | `ldap://10.0.0.46` (otras instancias) · `ldap://127.0.0.1` (Apache en la misma EC2) |

Usuarios **ficticios** (de `fase3/sebastian/usuarios-ficticios.csv`). Las contraseñas se generan en la
instancia y no se versionan.

| uid | Nombre | Grupo | gidNumber | Permisos |
|---|---|---|---|---|
| `medico01` | Elena Rios | `medicos` | 5001 | Intranet |
| `medico02` | Daniel Soto | `medicos` | 5001 | Intranet |
| `ti01` | Alex Vega | `ti` | 5002 | Intranet. Usuario de prueba de `tests_fase3.sh` y `probar-ldap.sh` |
| `ti02` | Sam Reyes | `ti` | 5002 | Intranet |
| `laboratorio01` | Nora Diaz | `laboratorio` | 5003 | Intranet |
| `laboratorio02` | Ivan Mora | `laboratorio` | 5003 | Intranet |

Permisos por grupo:

| Recurso | `medicos` | `ti` | `laboratorio` | Sin grupo / inexistente |
|---|---|---|---|---|
| Intranet `http://10.0.0.46/` (Apache `Require ldap-group`) | ✅ | ✅ | ✅ | ❌ 401 |
| SSH a las instancias | ❌ (las cuentas LDAP no son cuentas del sistema; el SSH es solo para el administrador con clave, por el endpoint) | ❌ | ❌ | ❌ |
| Escritura en el directorio | ❌ (solo `cn=admin`, local) | ❌ | ❌ | ❌ |

> Los grupos `medicos`, `ti` y `laboratorio` son roles **de aplicación** (LDAP). Las subredes Médicos y TI
> son segmentos **de red**. Un usuario `ti01` entra a la intranet desde cualquier subred autorizada.

## 3. Servicios por instancia (E4.1)

| Servicio | Instancia (subred, IP) | Escucha | Lo usan | Depende de | Script |
|---|---|---|---|---|---|
| SSH (administración) | Todas | TCP 22 | Endpoint `10.0.0.122` (SG-TI) | SG de cada instancia: 22 desde SG-TI | AMI + `hardening.sh` |
| LDAP (OpenLDAP) | Servidores `10.0.0.46` | TCP 389 | Apache (local), pruebas desde TI y Servidores | — | `fase3/sebastian/` |
| Intranet (Apache + LDAP) | Servidores `10.0.0.46` | TCP 80 | Médicos, Servidores, DMZ, TI (**no** Visitantes) | LDAP en `127.0.0.1:389` | `fase3/isabella/` |
| NTP servidor (chrony) | Servidores `10.0.0.46` | UDP 123 | Médicos, Servidores, DMZ, TI, NAT | Amazon Time Sync `169.254.169.123` | `chrony-servidor.sh` |
| NTP cliente | TI, Médicos, DMZ/NAT · Visitantes → Time Sync | — | — | `10.0.0.46` UDP 123 | `chrony-cliente.sh` |
| NAT (iptables MASQUERADE) | NAT instance (DMZ `10.0.0.96/28`, IP pública) | reenvío TCP 80/443 | Todas las subredes privadas (`apt`, Visitantes navega) | Internet Gateway, rutas, *source/dest check* desactivado | `nat-instance.sh` |
| DHCP | AWS (DHCP option set de la VPC) | — | Todas | — | — (se documenta) |
| DNS | AWS (Amazon DNS `10.0.0.2`) | — | Todas (resolver nombres para `apt`) | — | — |
| Firewall del SO (ufw) | Todas | — | — | — | `hardening.sh <rol>` |

EC2 de prueba (las lanza Majo, se detienen al terminar): una en **Médicos** y una en **Visitantes**. La
NAT instance hace de equipo de la **DMZ**.

## 4. Valores para `fase3.env` (Leonardo y Sebastián)

Los valores por defecto de `fase3/leonardo/fase3.env.example` y `fase3/sebastian/fase3.env.example`
**se confirman sin cambios**. Majo completa, al lanzar las instancias, `IP_NAT` = `IP_DMZ` (IP privada
de la NAT), `IP_MEDICOS` e `IP_VISITANTES`.
