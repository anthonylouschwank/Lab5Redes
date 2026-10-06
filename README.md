# Laboratorio 5 – Servicios de capa 7 en una red local

CC3067 Redes – Universidad del Valle de Guatemala – Ciclo 2, 2026

**Caso:** Hospital (Hospital Privado Castillejos) · **Zona DNS:** `hospital.redes.test` · **Base LDAP:** `dc=hospital,dc=redes,dc=test`

Implementación en una red local de DNS autoritativo (BIND9), directorio (OpenLDAP), web con login LDAP
(Apache), correo (Postfix + Dovecot + Thunderbird) y FTP (vsftpd), más una matriz de pruebas internas.
El laboratorio reutiliza el direccionamiento de la subred de servidores (`10.0.0.32/27`) y los grupos
LDAP (`medicos`, `ti`, `laboratorio`) del Proyecto 2 del grupo, sin la infraestructura de nube.

## Integrantes y roles

| Integrante          | uid LDAP    | Grupo LDAP    | Responsable de        |
|---------------------|-------------|---------------|-----------------------|
| Anthony Lou         | `anthony`   | `ti`          | Infraestructura (VM, red) y DNS |
| Sebastián Bustamante| `sebastian` | `ti`          | LDAP                  |
| Isabella Obando     | `isabella`  | `medicos`     | Web (Apache + LDAP)   |
| María José Girón    | `majo`      | `medicos`     | Correo (Postfix)      |
| Leonardo Mejía      | `leonardo`  | `medicos`     | Correo (Dovecot / Thunderbird) |
| Roberto Nájera      | `roberto`   | `laboratorio` | FTP y matriz de pruebas |

Las direcciones de correo siguen el formato `uid@hospital.redes.test`.

## Estructura del repositorio

| Carpeta     | Contenido |
|-------------|-----------|
| `infra/`    | Creación de la VM, configuración de red (netplan) y cliente Windows |
| `dns/`      | Configuración de BIND9 y archivo de zona |
| `ldap/`     | Instalación de OpenLDAP y archivos LDIF |
| `web/`      | VirtualHost de Apache y sitio con área protegida por LDAP |
| `mail/`     | Configuración de Postfix y Dovecot |
| `ftp/`      | Configuración de vsftpd y autenticación PAM/LDAP |
| `tests/`    | Scripts de la matriz de pruebas y evidencias |
| `docs/`     | Diagrama de red, tabla DNS y reporte final |
| `secrets/`  | Contraseñas del laboratorio (**ignoradas por git**, solo se versiona el ejemplo) |

`lab.env` contiene las variables comunes (dominio, IPs, DN base, usuarios) que usan todos los scripts.

## Uso rápido

En la VM Ubuntu, con el repositorio clonado:

```bash
cp secrets/credenciales.example.env secrets/credenciales.env   # y editar contraseñas
```

Cada carpeta de servicio incluye su script de instalación; se ejecutan en el orden
`dns → ldap → web → mail → ftp` y luego `tests/`.
