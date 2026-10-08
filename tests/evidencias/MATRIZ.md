# Matriz de pruebas – resultados

Generado en `srv` el 2026-10-08 16:18:48 CST. Cada ID enlaza a su evidencia.

| ID | Resultado | Prueba | Fecha |
|---|---|---|---|
| [DNS-00](DNS-00.txt) | ✅ OK | Validación de zonas con named-checkzone | 2026-10-08 16:17:25 |
| [DNS-01](DNS-01.txt) | ✅ OK | Resolución del servidor DNS (ns1) | 2026-10-08 16:17:26 |
| [DNS-02](DNS-02.txt) | ✅ OK | Resolución de ldap, www, mail y ftp | 2026-10-08 16:17:27 |
| [DNS-03](DNS-03.txt) | ✅ OK | Consulta SOA (respuesta autoritativa) | 2026-10-08 16:17:27 |
| [DNS-03b](DNS-03b.txt) | ✅ OK | Consulta NS de la zona | 2026-10-08 16:17:27 |
| [DNS-04](DNS-04.txt) | ✅ OK | Consulta MX (servidor de correo) | 2026-10-08 16:17:28 |
| [DNS-05](DNS-05.txt) | ✅ OK | Nombre inexistente responde NXDOMAIN | 2026-10-08 16:17:28 |
| [DNS-06](DNS-06.txt) | ✅ OK | Resolución inversa (PTR) de 10.0.0.37 | 2026-10-08 16:17:29 |
| [FTP-01](FTP-01.txt) | ✅ OK | Resolución de ftp.hospital.redes.test | 2026-10-08 16:18:29 |
| [FTP-02](FTP-02.txt) | ✅ OK | Autenticación válida (anthony) | 2026-10-08 16:18:30 |
| [FTP-03](FTP-03.txt) | ✅ OK | Autenticación con contraseña incorrecta | 2026-10-08 16:18:33 |
| [FTP-04](FTP-04.txt) | ✅ OK | Acceso anónimo | 2026-10-08 16:18:35 |
| [FTP-05](FTP-05.txt) | ✅ OK | Listado del directorio autorizado | 2026-10-08 16:18:36 |
| [FTP-06](FTP-06.txt) | ✅ OK | Carga de archivo a archivos/ | 2026-10-08 16:18:36 |
| [FTP-07](FTP-07.txt) | ✅ OK | Descarga del archivo sin alteraciones | 2026-10-08 16:18:37 |
| [FTP-08](FTP-08.txt) | ✅ OK | Restricción de directorios (chroot y permisos) | 2026-10-08 16:18:38 |
| [FTP-09](FTP-09.txt) | ✅ OK | Conexión de control (21) vs. conexión de datos (pasivo 40000-40100) | 2026-10-08 16:18:39 |
| [FTP-10](FTP-10.txt) | ✅ OK | Log de vsftpd (logins, rechazos y transferencias) | 2026-10-08 16:18:39 |
| [INT-01](INT-01.txt) | ✅ OK | Uso exclusivo de nombres DNS (FQDN) en clientes y configuración | 2026-10-08 16:18:41 |
| [INT-02](INT-02.txt) | ✅ OK | Reinicio: servicios habilitados, activos y pruebas básicas | 2026-10-08 16:18:48 |
| [INT-03](INT-03.txt) | ✅ OK | Puertos en escucha (ss -lntup) | 2026-10-08 16:18:42 |
| [INT-04](INT-04.txt) | ✅ OK | Revisión de logs de cada servicio | 2026-10-08 16:18:45 |
| [LDAP-01](LDAP-01.txt) | ✅ OK | Consulta de usuarios en ou=People | 2026-10-08 16:17:29 |
| [LDAP-02](LDAP-02.txt) | ✅ OK | Bind con usuario y contraseña correctos | 2026-10-08 16:17:30 |
| [LDAP-03](LDAP-03.txt) | ✅ OK | Bind con contraseña incorrecta | 2026-10-08 16:17:30 |
| [LDAP-03b](LDAP-03b.txt) | ✅ OK | Bind con usuario inexistente | 2026-10-08 16:17:31 |
| [LDAP-04](LDAP-04.txt) | ✅ OK | Atributos uid, cn, sn y mail de un usuario | 2026-10-08 16:17:31 |
| [LDAP-05](LDAP-05.txt) | ✅ OK | Grupos por rol y sus miembros | 2026-10-08 16:17:31 |
| [LDAP-06](LDAP-06.txt) | ✅ OK | Registro de binds en el log de slapd | 2026-10-08 16:17:32 |
| [MAIL-01](MAIL-01.txt) | ✅ OK | Resolución de mail.hospital.redes.test y registro MX | 2026-10-08 16:17:58 |
| [MAIL-02](MAIL-02.txt) | ✅ OK | Servicios para Thunderbird: SMTP 587 y IMAP 143 con STARTTLS | 2026-10-08 16:17:59 |
| [MAIL-03](MAIL-03.txt) | ✅ OK | IMAP: autenticación válida (anthony) | 2026-10-08 16:18:01 |
| [MAIL-04](MAIL-04.txt) | ✅ OK | IMAP: contraseña incorrecta | 2026-10-08 16:18:07 |
| [MAIL-04b](MAIL-04b.txt) | ✅ OK | SMTP: contraseña incorrecta en submission (587) | 2026-10-08 16:18:16 |
| [MAIL-05](MAIL-05.txt) | ✅ OK | Envío interno isabella -> anthony (SMTP + entrega LMTP) | 2026-10-08 16:18:20 |
| [MAIL-05b](MAIL-05b.txt) | ✅ OK | Respuesta anthony -> isabella (intercambio entre usuarios) | 2026-10-08 16:18:23 |
| [MAIL-06](MAIL-06.txt) | ✅ OK | Recepción por IMAP en el buzón de anthony | 2026-10-08 16:18:25 |
| [MAIL-06b](MAIL-06b.txt) | ✅ OK | Recepción por IMAP en el buzón de isabella | 2026-10-08 16:18:26 |
| [MAIL-07](MAIL-07.txt) | ✅ OK | Destinatario inexistente | 2026-10-08 16:18:28 |
| [MAIL-08](MAIL-08.txt) | ✅ OK | Logs de Postfix y Dovecot de las pruebas | 2026-10-08 16:18:28 |
| [WEB-01](WEB-01.txt) | ✅ OK | Resolución de www.hospital.redes.test | 2026-10-08 16:17:33 |
| [WEB-02](WEB-02.txt) | ✅ OK | Acceso a la página principal | 2026-10-08 16:17:33 |
| [WEB-03](WEB-03.txt) | ✅ OK | Intranet con usuario LDAP válido (anthony) | 2026-10-08 16:17:34 |
| [WEB-03b](WEB-03b.txt) | ✅ OK | Intranet con otro usuario válido (isabella) | 2026-10-08 16:17:34 |
| [WEB-03c](WEB-03c.txt) | ✅ OK | Panel de TI con miembro del grupo ti (anthony) | 2026-10-08 16:17:35 |
| [WEB-03d](WEB-03d.txt) | ✅ OK | Panel de TI con usuario fuera del grupo ti (isabella) | 2026-10-08 16:17:36 |
| [WEB-04](WEB-04.txt) | ✅ OK | Intranet con contraseña incorrecta | 2026-10-08 16:17:38 |
| [WEB-04b](WEB-04b.txt) | ✅ OK | Intranet con usuario inexistente | 2026-10-08 16:17:40 |
| [WEB-05](WEB-05.txt) | ✅ OK | Dependencia de LDAP: autenticación con slapd detenido | 2026-10-08 16:17:56 |
| [WEB-06](WEB-06.txt) | ✅ OK | Log de acceso de Apache (códigos 200/401/500) | 2026-10-08 16:17:57 |

**Total:** 50 OK de 50 pruebas.
