# Fase 3 — Intranet (Apache + LDAP) · Isabella

Hospital Privado Castillejos · CC3067 Redes · Casillas E2.2, E2.4 (parte web), E6.1, E6.2, E6.3.

**Estado:**
- **Probado en la VM local** (Ubuntu 24.04.5, junto al LDAP de Fase 3 de Sebastián), el 28/10/2026.
  9 de 9 pruebas PASS.
- En AWS: **propuesto**. Lo ejecuta Majo en la EC2 Servidores `10.0.0.46`.

## 1. Qué hace

Intranet del hospital en Apache, en la misma EC2 que el LDAP (`10.0.0.46`):
- **Portal** (`/`): sin login, pero **solo** desde las subredes autorizadas.
- **Intranet** (`/intranet/`): login con una cuenta del directorio LDAP de los grupos `medicos`, `ti`
  o `laboratorio`. Muestra el nombre, el correo y el cargo **leídos de LDAP**.
- **Panel de TI** (`/intranet/ti/`): solo el grupo `ti`. Ejemplo de permisos por rol.

Decisiones de Anthony (`fase3/anthony/README.md`):
- **HTTP, puerto 80** (D3). HTTPS queda como mejora.
- Base `dc=hospital,dc=redes,dc=test`.
- La intranet es accesible desde **Médicos, Servidores, DMZ y TI**; **nunca Visitantes ni Internet**.

## 2. Defensa en profundidad para "solo desde la red interna"

| Capa | Regla | Quién la aplica |
|---|---|---|
| Security Group | SG-Servidores: TCP 80 solo desde Médicos, Servidores, DMZ y TI | Anthony diseña / Majo aplica (REGLAS-E4.4 Paso 2) |
| Firewall del SO | ufw: 80 desde las mismas subredes | `hardening.sh servidores` (Leonardo) |
| **Apache** | `Require ip 10.0.0.0/27 10.0.0.32/27 10.0.0.96/28 10.0.0.112/28` (+ loopback para pruebas locales). Visitantes `10.0.0.64/27` recibe **403** | Este script |
| Red | Servidores sin IP pública ni ruta de entrada desde Internet | Diseño de la VPC |

## 3. Integración con LDAP (contrato de Sebastián)

| Dato | Valor |
|---|---|
| Servidor | `ldap://127.0.0.1` (misma EC2: no pasa por el SG) |
| Búsqueda de usuarios | `ou=People,dc=hospital,dc=redes,dc=test?uid,cn,mail,title?one?(objectClass=inetOrgPerson)` |
| Bind de Apache | `uid=svc-intranet,ou=People,dc=hospital,dc=redes,dc=test` |
| Grupos | `Require ldap-group cn=<grupo>,ou=Groups,…` con `AuthLDAPGroupAttribute memberUid` (UID, no DN) |

**Contraseña de `svc-intranet`:**
- Nunca está en el repo ni en la configuración de Apache.
- El instalador la pide con `read -s` (o la recibe por `LDAP_SERVICE_PASSWORD`) y la guarda en
  `/etc/apache2/hospital-intranet/ldap-bind.secret` (root, permisos 600).
- Apache la lee al arrancar con `AuthLDAPBindPassword "exec:/bin/cat …"`.
- Antes de tocar Apache, el instalador **comprueba el bind** con `ldapwhoami`.

`svc-intranet` es de tipo `account`, no `inetOrgPerson`: **no puede iniciar sesión en la intranet**.

## 4. Qué se reutilizó del Lab 5 y qué cambió

| Del Lab 5 (`web/`) | En la Fase 3 |
|---|---|
| `mod_authnz_ldap` con `AuthBasicProvider ldap` | Igual. Ahora con **bind de servicio** (contrato), no búsqueda anónima |
| Panel `/intranet/ti/` por grupo `ti`; `AuthLDAPURL` repetida en el subdirectorio (no se hereda) | Igual, más `Require ip` |
| Página que muestra `AUTHENTICATE_CN/MAIL/TITLE` (SSI) | Igual, más "Equipo de origen" (`REMOTE_ADDR`) |
| Caché LDAP desactivada y `LogLevel authnz_ldap:info` (cada rechazo queda en el log) | Igual |
| `estilo.css` | Igual |
| Textos con integrantes, carnés y servicios DNS/correo/FTP | **Quitados.** Solo servicios de Fase 3, datos ficticios |
| `web/instalar.sh` (sin validar antes de recargar) | `instalar-web.sh`: idempotente, respalda el VirtualHost, `apache2ctl configtest` **antes** de recargar y restaura si falla |
| `tests/web.sh` | `probar-web.sh`: independiente, sin archivos de secretos, con origen no autorizado opcional |

## 5. Archivos

| Archivo | Para qué |
|---|---|
| `instalar-web.sh` | Instala o actualiza la intranet (idempotente) |
| `probar-web.sh` | Pruebas W-01…W-09 con tabla PASS/FAIL |
| `apache/hospital-intranet.conf.plantilla` | VirtualHost (el instalador reemplaza los `@MARCADORES@`) |
| `sitio/` | Portal, intranet y panel de TI |
| `fase3.env.example` | Variables no secretas (puerto, subredes, contrato LDAP) |
| `evidencias/E6_probar-web_vm-local.txt` | Salida real de las pruebas en la VM local |

## 6. Ejecución en la EC2 Servidores (Majo)

**Orden:** después de la NAT, `chrony-servidor.sh` y el LDAP de Sebastián. Antes de `hardening.sh servidores`.

```bash
cd ~/fase3                                  # donde se copió la carpeta del repo
sudo bash isabella/instalar-web.sh          # pide la contraseña de svc-intranet (la generada en esta EC2)
```
Debe terminar en `RESULTADO: OK` con "bind de la cuenta de servicio aceptado", portal `200` e intranet `401`.

**Pruebas** (contraseña del usuario ficticio por teclado):
```bash
bash isabella/probar-web.sh 2>&1 | tee E6_probar-web_aws-servidores.txt            # en Servidores
INTRANET_URL=http://10.0.0.46 bash isabella/probar-web.sh 2>&1 | tee E6_probar-web_aws-ti.txt   # desde TI
```
Desde Visitantes, la intranet **no debe ni responder** (la bloquean la NACL y el SG): eso lo prueba
VIS-02 de `tests_fase3.sh`. El 403 de Apache es la tercera capa y en AWS normalmente no se alcanza a ver.

**Si algo falla:**

| Mensaje | Causa |
|---|---|
| `el LDAP rechazó el bind de svc-intranet` | slapd apagado o contraseña equivocada. Repetir con `sudo --preserve-env=LDAP_SERVICE_PASSWORD bash instalar-web.sh` |
| `apt-get update no respondió` | Sin salida a Internet: NAT, ruta `0.0.0.0/0` o salida 80/443 de SG-Servidores |
| `configuración de Apache no es válida` | No se recargó nada; se restauró el respaldo. Ver la salida de `configtest` |
| La intranet da **500** | Apache no llega al LDAP: `systemctl status slapd` y `/var/log/apache2/hospital-intranet-error.log` |

## 7. Resultados (VM local, 28/10/2026)

Destino `http://127.0.0.1`, usuarios ficticios de Sebastián. "Visitantes" se simuló con una IP
temporal `10.0.0.70` en la VM (`curl --interface`).

| ID | Prueba | Esperado | Obtenido |
|---|---|---|---|
| W-01 | Portal desde origen autorizado | 200 | **200 PASS** |
| W-02 | `/intranet/` sin credenciales | 401 | **401 PASS** |
| W-03 | `/intranet/` con `ti01` válida | 200 | **200 PASS** |
| W-04 | `/intranet/` con contraseña inválida | 401 | **401 PASS** |
| W-05 | `/intranet/` con usuario inexistente | 401 | **401 PASS** |
| W-06 | `/intranet/ti/` con `ti01` (grupo ti) | 200 | **200 PASS** |
| W-07 | `/intranet/ti/` con `medico01` (sin grupo ti) | 401 | **401 PASS** |
| W-08 | Portal desde origen no autorizado (`10.0.0.70`, rango Visitantes) | 403 | **403 PASS** |
| W-09 | `/intranet/` con credencial válida desde `10.0.0.70` | 403 | **403 PASS** |

Evidencia: `evidencias/E6_probar-web_vm-local.txt`. El log de Apache registra cada rechazo con su
motivo: `Password Mismatch`, `user noexiste not found`, `authorization failure` para medico01 en
`/intranet/ti/`, y `client denied by server configuration` para `10.0.0.70`.

**Re-ejecutable:** una segunda corrida de `instalar-web.sh` sin contraseña conservó la existente,
volvió a validar el bind y no creó respaldos (no había cambios).

## 8. Limitaciones

- **HTTP sin cifrar.** La autenticación Basic viaja en texto plano dentro de la VPC. Mejora: HTTPS
  con certificado autofirmado generado en la instancia (lo proponía Fase 1).
- La autenticación Basic no tiene "cerrar sesión": hay que cerrar el navegador.
- `Require ip` usa la IP de origen. Dentro de la VPC no hay NAT entre subredes, así que se conserva.
- En la VM local, "Visitantes" se **simuló** con una IP en `lo`. La prueba real de Visitantes es
  VIS-02 en AWS.
- Si cambia la contraseña de `svc-intranet`, hay que volver a correr el instalador (Apache la lee al arrancar).
- Nada de esto está probado en AWS todavía.
