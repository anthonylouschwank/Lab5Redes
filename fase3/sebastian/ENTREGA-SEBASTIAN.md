# Fase 3 — Entrega y traspaso de LDAP

**Responsable:** Sebastián Bustamante  
**Proyecto:** Hospital Privado Castillejos, CC3067 Redes  
**Casillas asignadas:** E2.1, E2.4 (LDAP), E5.5, E5.6, E5.7 y E8.2

## 1. Estado real de la entrega

### Implementado

- Instalador de OpenLDAP para Ubuntu Server 24.04.
- Instalación idempotente y no destructiva: no ejecuta `dpkg-reconfigure` sobre una instalación existente.
- Detección de una base LDAP incompatible, con parada segura y sin borrar datos.
- Base predeterminada `dc=hospital,dc=redes,dc=test`.
- Unidades organizativas `People` y `Groups`.
- Grupos `medicos`, `ti` y `laboratorio` como `posixGroup`.
- Seis identidades ficticias, dos por grupo.
- Cuenta de servicio `svc-intranet` para Apache.
- Generación local de hashes SSHA sin versionar contraseñas ni hashes.
- Carga idempotente de usuarios: las entradas existentes se omiten.
- Pruebas de consultas, grupos, bind válido y bind inválido.
- Contrato de integración para Isabella en `CONTRATO-APACHE.md`.

### Verificado en la VM local

- Ubuntu Server 24.04.5 LTS.
- OpenLDAP 2.6.10 instalado y activo.
- TCP/389 en escucha.
- `namingContexts: dc=hospital,dc=redes,dc=test`.
- Existencia de las OUs `People` y `Groups`.
- Sintaxis Bash correcta para todos los scripts de Fase 3.
- La VM conserva los usuarios del Lab 5. No se eliminan; las pruebas nuevas filtran exclusivamente los seis UID ficticios.
- Los seis usuarios ficticios y `svc-intranet` fueron generados y cargados.
- Los grupos contienen exclusivamente los `memberUid` ficticios definidos para Fase 3.
- `probar-ldap.sh` finalizó con `PASS`: consultas, bind válido y rechazo con `Invalid credentials (49)`.
- Se guardaron salidas locales sanitizadas para instalación, generación, carga y pruebas.

### Pendiente para el cierre grupal

- Tomar las capturas PNG requeridas para el informe a partir de las pruebas locales.
- Recibir de Anthony la confirmación definitiva del dominio y base LDAP.
- El despliegue y prueba en AWS corresponden exclusivamente a Majo.

No debe afirmarse que LDAP está probado en AWS hasta que Majo ejecute los scripts y entregue las salidas.

## 2. Archivos entregados

| Archivo | Propósito |
|---|---|
| `instalar-ldap.sh` | Instala y reconcilia la estructura LDAP sin purgar bases existentes. |
| `usuarios-ficticios.csv` | Define seis identidades ficticias y sus grupos. |
| `generar-usuarios.sh` | Genera `usuarios.ldif` con hashes SSHA en la instancia. |
| `cargar-usuarios.sh` | Agrega únicamente entradas inexistentes. |
| `probar-ldap.sh` | Ejecuta las pruebas E5.5, E5.6, E5.7 y parte de E8.2. |
| `fase3.env.example` | Documenta variables no secretas configurables. |
| `CONTRATO-APACHE.md` | Entrega a Isabella los DN, filtros y atributos exactos. |
| `README.md` | Explica reutilización del Lab 5, supuestos, ejecución y red. |
| `.gitignore` | Evita versionar el LDIF con hashes y las salidas locales. |

El archivo `usuarios.ldif` no forma parte del repositorio: se genera en la VM o EC2 de destino y queda ignorado por Git.

## 3. Usuarios y grupos ficticios

| UID | Grupo | GID | UID numérico |
|---|---|---:|---:|
| `medico01` | `medicos` | 5001 | 12001 |
| `medico02` | `medicos` | 5001 | 12002 |
| `ti01` | `ti` | 5002 | 12003 |
| `ti02` | `ti` | 5002 | 12004 |
| `laboratorio01` | `laboratorio` | 5003 | 12005 |
| `laboratorio02` | `laboratorio` | 5003 | 12006 |

Cuenta de servicio:

```text
uid=svc-intranet,ou=People,dc=hospital,dc=redes,dc=test
```

La contraseña de esta cuenta se genera en la instancia y se entrega a Isabella por un canal seguro. Nunca se agrega al repositorio, informe, capturas o chat grupal.

## 4. Ejecución local

Desde la raíz del repositorio:

```bash
cd ~/lab5
```

### 4.1 Instalar o reconciliar LDAP

La VM del Lab 5 conserva la contraseña administrativa en un archivo local ignorado por Git. Se puede consumir sin mostrarla:

```bash
(
    source secrets/credenciales.env
    export LDAP_ADMIN_PASSWORD="$LDAP_ADMIN_PASS"
    sudo --preserve-env=LDAP_ADMIN_PASSWORD \
        bash fase3/sebastian/instalar-ldap.sh
)
```

Resultado esperado al final:

```text
OK: OpenLDAP quedó activo sin reconfiguración destructiva.
```

También debe mostrar los grupos `medicos`, `ti` y `laboratorio`, y una línea de escucha en `:389`.

### 4.2 Generar usuarios

```bash
bash fase3/sebastian/generar-usuarios.sh
```

Solicita de forma oculta:

1. Una contraseña para los usuarios ficticios.
2. Una contraseña distinta para `svc-intranet`.

Resultado esperado:

```text
OK: se generó .../usuarios.ldif con permisos 600.
```

Verificar sin mostrar hashes:

```bash
ls -l fase3/sebastian/usuarios.ldif
git status --short
```

El archivo debe tener permisos `-rw-------` y no debe aparecer en `git status`.

### 4.3 Cargar usuarios

```bash
(
    source secrets/credenciales.env
    export LDAP_ADMIN_PASSWORD="$LDAP_ADMIN_PASS"
    bash fase3/sebastian/cargar-usuarios.sh
)
```

Primera ejecución esperada:

```text
OK: 7 entradas creadas; 0 ya existían.
```

Las siete entradas son seis personas ficticias y `svc-intranet`. En una segunda ejecución debe indicar que ya existen, sin duplicarlas ni cambiar sus contraseñas.

### 4.4 Ejecutar pruebas

```bash
bash fase3/sebastian/probar-ldap.sh
```

Cuando solicite la contraseña de `ti01`, usar la elegida para los usuarios ficticios.

Resultado final esperado:

```text
PASS: consultas, bind válido y bind inválido se comportaron como se esperaba.
```

La prueba inválida debe mostrar:

```text
ldap_bind: Invalid credentials (49)
```

Ese mensaje representa un resultado correcto: demuestra que una contraseña incorrecta fue rechazada.

## 5. Evidencias que debe producir Sebastián

Crear la carpeta local ignorada por Git:

```bash
mkdir -p fase3/sebastian/salidas
```

Guardar una ejecución completa:

```bash
bash fase3/sebastian/probar-ldap.sh 2>&1 |
  tee fase3/sebastian/salidas/E5.5-E5.7_pruebas_ldap.txt
```

Capturas sugeridas para el informe:

| Archivo | Contenido |
|---|---|
| `E5.5_ldapsearch_usuarios.png` | Los seis UID ficticios. |
| `E5.5_ldapsearch_grupos.png` | Los tres grupos y sus `memberUid`. |
| `E5.6_ldapwhoami_valido.png` | Bind de `ti01` aceptado. |
| `E5.7_ldapwhoami_invalido.png` | `Invalid credentials (49)`. |
| `E8.2_ldap_pruebas_PASS.png` | Resultado final `PASS`. |

Antes de compartirlas, revisar que no aparezcan contraseñas, hashes, ID de cuenta AWS, claves o tokens.

## 6. Datos que Sebastián debe enviar

### A Isabella — integración Apache

Enviar `CONTRATO-APACHE.md` y confirmar:

```text
Base DN: dc=hospital,dc=redes,dc=test
Usuarios: ou=People,dc=hospital,dc=redes,dc=test
Grupos: ou=Groups,dc=hospital,dc=redes,dc=test
Bind DN: uid=svc-intranet,ou=People,dc=hospital,dc=redes,dc=test
Atributo de login: uid
Atributo de grupo: memberUid
AuthLDAPGroupAttributeIsDN: off
```

La contraseña de `svc-intranet` se entrega aparte y solo cuando se genere en la instancia donde se desplegará LDAP.

### A Anthony — diseño y reglas

Solicitar confirmación de:

- Dominio: `hospital.redes.test`.
- Base: `dc=hospital,dc=redes,dc=test`.
- LDAP y Apache en la misma EC2 Servidores `10.0.0.46`.

Informar como propuesta de red:

- Servicio LDAP: TCP/389.
- Permitir desde Servidores `10.0.0.32/27` y TI `10.0.0.112/28` para integración/administración.
- Denegar Visitantes `10.0.0.64/27` e Internet.
- Si Apache comparte la EC2, usar `127.0.0.1:389` y no abrir LDAP para esa comunicación.

Anthony debe confirmar estos orígenes dentro de su matriz E4.2 y reglas E4.4.

### A Majo — despliegue AWS

Entregar toda la carpeta `fase3/sebastian/` y estas indicaciones:

1. Ejecutar después de que la EC2 Servidores tenga salida a Internet mediante NAT.
2. Generar las contraseñas en el momento; no copiar `secrets/credenciales.env` del Lab 5 a AWS.
3. Ejecutar los cuatro scripts en el orden documentado.
4. Guardar las salidas y capturas sanitizadas.
5. No ejecutar `ldap/instalar.sh` del Lab 5 porque usa reconfiguración destructiva.
6. No cambiar SG, NACL, rutas ni UFW desde estos scripts.

Para AWS, Majo debe introducir `LDAP_ADMIN_PASSWORD` directamente cuando el script lo solicite o proporcionarla mediante una variable temporal. No debe persistirla en disco.

### A Roberto — informe y evidencias

Entregar:

- Salida de `probar-ldap.sh`.
- Capturas E5.5, E5.6, E5.7 y E8.2.
- Este documento para describir qué se reutilizó y qué cambió.
- Aclaración de estado: `probado localmente` o `probado en AWS`, según la evidencia real.

## 7. Dependencias externas

| Dependencia | Responsable | Impacto |
|---|---|---|
| Confirmar dominio/base LDAP | Anthony | Debe cerrarse antes del despliegue definitivo. |
| NAT y salida para `apt` en AWS | Majo/Anthony | Sin salida no se pueden instalar paquetes. |
| Reglas SG/NACL | Anthony diseña, Majo aplica | Determinan quién alcanza TCP/389. |
| Integración Apache | Isabella | Consume el contrato LDAP y la cuenta de servicio. |
| Recolección de evidencia | Roberto | Incorpora resultados al informe. |

El desarrollo local puede completarse sin esperar estas dependencias. El despliegue final en AWS no.

## 8. Seguridad y operación

- No versionar `usuarios.ldif`, archivos `.secret` ni `salidas/` con datos sensibles.
- No mostrar contraseñas o hashes en capturas.
- No usar contraseñas personales.
- No publicar TCP/389 hacia Internet.
- LDAPS es opcional y no forma parte del alcance mínimo actual.
- El instalador no modifica SSH, UFW, Security Groups ni NACL.
- Si detecta una base diferente, se detiene en lugar de purgarla.
- Una reejecución conserva usuarios existentes y no rota contraseñas automáticamente.

## 9. Criterio para declarar la tarea terminada

La parte de Sebastián puede marcarse como completa cuando:

- [x] Los scripts y documentación existen en `fase3/sebastian/`.
- [x] La sintaxis Bash fue validada en Ubuntu 24.04.
- [x] OpenLDAP local escucha en TCP/389 y expone la base correcta.
- [x] Se generaron y cargaron los seis usuarios ficticios y `svc-intranet`.
- [x] `probar-ldap.sh` terminó con `PASS`.
- [x] Se guardaron evidencias de texto sanitizadas.
- [ ] Se tomaron las capturas PNG seleccionadas para el informe.
- [ ] Anthony confirmó dominio, base y orígenes autorizados.
- [ ] Isabella recibió el contrato de integración.
- [ ] Majo recibió scripts e instrucciones de despliegue.
- [ ] Roberto recibió resultados y evidencias.

