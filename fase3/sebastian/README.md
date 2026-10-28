# Fase 3 — Entrega LDAP de Sebastián

## Alcance y estado

Estos archivos cubren E2.1, la parte LDAP de E2.4, E5.5, E5.6, E5.7 y E8.2. Se preparan y prueban primero en la VM local; **solo Majo despliega en AWS**.

Supuestos pendientes de confirmación por Anthony:

- Base: `dc=hospital,dc=redes,dc=test`.
- LDAP, chrony e intranet compartirán la EC2 Servidores `10.0.0.46`.
- Se usará LDAP sin TLS dentro de la VPC; LDAPS queda fuera del alcance mínimo.

No se afirma que estos archivos ya estén configurados o probados en AWS.

## Reutilización del Lab 5

| Elemento | Decisión para Fase 3 |
|---|---|
| Base DN y OUs de `ldap/base.ldif` | Se conservan, pero se generan desde variables. |
| Grupos `medicos`, `ti`, `laboratorio` | Se conservan como `posixGroup`. |
| `ldap/usuarios.csv` | Se reemplaza por identidades ficticias. |
| Hashes SSHA | Se conservan, pero se generan en la instancia y no se versionan. |
| Logs `stats` de `ldap/config.ldif` | Se conservan para evidencia. |
| Índice de correo | Se omite: correo no es requisito de Fase 3. |
| `ldap/instalar.sh` | No se reutiliza: ejecuta `dpkg-reconfigure` y puede purgar la base. |
| `ldap/usuarios.sh` | Se reemplaza: dependía de un archivo de secretos persistente. |

El nuevo instalador detecta una base existente. Si no coincide con la base solicitada, falla sin borrar ni reconfigurar datos.
Si la VM local conserva usuarios del Lab 5, estos tampoco se eliminan. La prueba de
Fase 3 filtra expresamente los seis UID ficticios para no confundir datos históricos
con la entrega nueva.

## Archivos

- `instalar-ldap.sh`: instala de forma no destructiva y crea OUs/grupos.
- `usuarios-ficticios.csv`: seis identidades ficticias, dos por grupo.
- `generar-usuarios.sh`: genera `usuarios.ldif` con hashes SSHA.
- `cargar-usuarios.sh`: agrega únicamente entradas inexistentes.
- `probar-ldap.sh`: prueba consultas, bind válido y bind inválido.
- `CONTRATO-APACHE.md`: datos exactos para Isabella.
- `ENTREGA-SEBASTIAN.md`: estado, ejecución, evidencias y traspaso al equipo.
- `fase3.env.example`: variables no secretas.

`usuarios.ldif` está ignorado por Git porque contiene hashes de contraseñas.

## Prueba local en Ubuntu 24.04

Desde la raíz del repositorio:

```bash
sudo bash fase3/sebastian/instalar-ldap.sh
bash fase3/sebastian/generar-usuarios.sh
bash fase3/sebastian/cargar-usuarios.sh
bash fase3/sebastian/probar-ldap.sh
```

Los scripts solicitan secretos con entrada oculta. Para automatización, se pueden exportar temporalmente:

```bash
export LDAP_ADMIN_PASSWORD='generada-en-el-momento'
export LDAP_DEMO_PASSWORD='generada-en-el-momento'
export LDAP_SERVICE_PASSWORD='generada-en-el-momento'
export LDAP_TEST_PASSWORD="${LDAP_DEMO_PASSWORD}"

sudo --preserve-env=LDAP_ADMIN_PASSWORD bash fase3/sebastian/instalar-ldap.sh
bash fase3/sebastian/generar-usuarios.sh
bash fase3/sebastian/cargar-usuarios.sh
bash fase3/sebastian/probar-ldap.sh

unset LDAP_ADMIN_PASSWORD LDAP_DEMO_PASSWORD LDAP_SERVICE_PASSWORD LDAP_TEST_PASSWORD
```

No escriba estos valores en scripts, archivos `.env`, capturas ni el historial del shell.

Para guardar evidencia sanitizada:

```bash
mkdir -p fase3/sebastian/salidas
bash fase3/sebastian/probar-ldap.sh 2>&1 |
  tee fase3/sebastian/salidas/E5.5-E5.7_pruebas_ldap.txt
```

## Red requerida para Anthony/Majo

Propuesta mínima, sujeta a la matriz final de Anthony:

- Servicio: TCP/389 en EC2 Servidores `10.0.0.46`.
- Permitir desde Servidores `10.0.0.32/27` y TI `10.0.0.112/28` para integración y pruebas.
- No permitir desde Visitantes `10.0.0.64/27` ni desde Internet.
- Si Apache comparte la EC2, debe consultar `127.0.0.1:389`.
- La restricción principal se aplica en el Security Group. El instalador no cambia UFW ni SSH para evitar pérdida de acceso.

