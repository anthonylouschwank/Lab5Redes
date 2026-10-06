# Diagrama de red local

Red del laboratorio: **subred de servidores del proyecto, `10.0.0.32/27`** (Host-Only de VirtualBox).
La VM tiene una segunda interfaz NAT que solo se usa para descargar paquetes.

```mermaid
flowchart LR
    internet((Internet))

    subgraph host["Windows anfitrión"]
        cliente["<b>cliente.hospital.redes.test</b><br/>10.0.0.33<br/>Navegador · Thunderbird · Cliente FTP<br/>DNS: regla NRPT → 10.0.0.37"]
        nat["NAT de VirtualBox<br/>10.0.2.0/24"]
    end

    subgraph lab["Red Host-Only 10.0.0.32/27"]
        subgraph srv["VM srv · Ubuntu Server 24.04 · 10.0.0.37"]
            dns["BIND9<br/>ns1 · 53/udp,tcp"]
            ldap["OpenLDAP<br/>ldap · 389/tcp"]
            web["Apache<br/>www · 80/tcp"]
            mail["Postfix · Dovecot<br/>mail · 25, 587, 143/tcp"]
            ftp["vsftpd<br/>ftp · 21/tcp + 40000-40100/tcp"]
        end
    end

    cliente -- "DNS, HTTP, SMTP, IMAP, FTP" --> srv
    web -- "autenticación (bind)" --> ldap
    mail -- "usuarios y autenticación" --> ldap
    ftp -- "PAM / nslcd" --> ldap
    srv -- "enp0s3 (apt)" --> nat --> internet
```

| Equipo | Interfaz | Dirección | Función |
|---|---|---|---|
| VM `srv` | `enp0s8` | `10.0.0.37/27` (estática) | Todos los servicios del laboratorio |
| VM `srv` | `enp0s3` | DHCP (NAT) | Solo salida a Internet |
| Windows | Host-Only #2 | `10.0.0.33/27` | Cliente de pruebas |
