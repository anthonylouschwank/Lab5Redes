# FTP: vsftpd en ftp.hospital.redes.test

- **Autenticación:** usuarios de OpenLDAP vía PAM (`pam_ldap`) y `nslcd`; solo los de `/etc/vsftpd.userlist`.
- **Sin acceso anónimo** (`anonymous_enable=NO`).
- **Chroot:** cada usuario queda encerrado en `/srv/ftp/<usuario>` (su home en este servidor, por el
  `map` de `nslcd.conf`). La raíz del chroot es de `root` (755) y el único lugar con escritura es
  `archivos/` (`<usuario>`, 700): ni por FTP ni desde el sistema otro usuario puede entrar.
- **Modo pasivo** con puertos `40000-40100`; el modo activo (`PORT`) está deshabilitado.
- **Logs:** `/var/log/vsftpd.log` (comandos, `OK/FAIL LOGIN`, `OK UPLOAD/DOWNLOAD`).

## Conexión de control vs. conexión de datos

FTP usa **dos conexiones TCP** distintas:

| | Conexión de control | Conexión de datos |
|---|---|---|
| Puerto del servidor | 21 | Uno del rango pasivo 40000-40100 (elegido por sesión/transferencia) |
| Quién la abre | El cliente, al conectarse | El cliente, después de que el servidor le indica el puerto con `227` |
| Duración | Toda la sesión | Solo lo que dura un listado o un archivo; luego se cierra |
| Qué transporta | Comandos y respuestas de texto: `USER`, `PASS`, `CWD`, `PASV`, `RETR`, `STOR`, `QUIT`… y códigos `230`, `150`, `226`, `550`… | El contenido: el listado de `LIST` o los bytes del archivo |

Ejemplo real (evidencia `tests/evidencias/FTP-09.txt`):

```
* Connected to ftp.hospital.redes.test (10.0.0.37) port 21     <- control
> PASV
< 227 Entering Passive Mode (10,0,0,37,156,91).                 <- 156*256 + 91 = 40027
* Connecting to 10.0.0.37 (10.0.0.37) port 40027                <- datos
> RETR LEEME.txt                                                 <- (por el control)
< 150 Opening BINARY mode data connection for LEEME.txt (111 bytes).
< 226 Transfer complete.                                         <- datos cerrada, control sigue abierta
```

En modo pasivo es el cliente quien abre ambas conexiones, por eso basta con permitir el 21 y el rango
40000-40100 en un firewall. Limitar el rango evita tener que abrir todos los puertos altos.

> FTP no cifra: usuario y contraseña viajan en texto plano por la conexión de control. En un despliegue
> real (como el del proyecto) se usaría FTPS o SFTP.
