# Tabla de resolución de nombres DNS

Zona autoritativa: `hospital.redes.test` · Servidor: BIND9 en `ns1.hospital.redes.test` (10.0.0.37)

## Zona directa `hospital.redes.test`

| Nombre                        | Tipo | Valor                              | Servicio |
|-------------------------------|------|------------------------------------|----------|
| `hospital.redes.test`         | SOA  | `ns1.hospital.redes.test.` `admin.hospital.redes.test.` | Autoridad de la zona |
| `hospital.redes.test`         | NS   | `ns1.hospital.redes.test.`         | Servidor de nombres |
| `hospital.redes.test`         | MX   | `10 mail.hospital.redes.test.`     | Correo del dominio |
| `ns1.hospital.redes.test`     | A    | `10.0.0.37`                        | BIND9 |
| `ldap.hospital.redes.test`    | A    | `10.0.0.37`                        | OpenLDAP |
| `www.hospital.redes.test`     | A    | `10.0.0.37`                        | Apache |
| `mail.hospital.redes.test`    | A    | `10.0.0.37`                        | Postfix / Dovecot |
| `ftp.hospital.redes.test`     | A    | `10.0.0.37`                        | vsftpd |
| `srv.hospital.redes.test`     | A    | `10.0.0.37`                        | Nombre del equipo (hostname) |
| `cliente.hospital.redes.test` | A    | `10.0.0.33`                        | Windows anfitrión (cliente) |

## Zona inversa `0.0.10.in-addr.arpa`

| Nombre               | Tipo | Valor |
|----------------------|------|-------|
| `37.0.0.10.in-addr.arpa` | PTR | `srv.hospital.redes.test.` |
| `33.0.0.10.in-addr.arpa` | PTR | `cliente.hospital.redes.test.` |

Todos los servicios comparten la IP `10.0.0.37` porque corren en la misma VM; cada uno tiene su
propio nombre para que los clientes usen siempre el FQDN del servicio y no la IP.
