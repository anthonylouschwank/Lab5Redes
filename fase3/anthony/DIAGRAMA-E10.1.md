# Diagrama E10.1 — Hospital Privado Castillejos (Fase 3)

Estado al **29/10/2026**, según la configuración real de AWS y las pruebas de `tests_fase3.sh`
(40 PASS / 0 FAIL; ver `fase3/evidencias/INDICE-EVIDENCIAS.md`).
- verde = **probado en AWS**
- azul = **configurado** (sin prueba propia)
- flechas punteadas = tráfico **bloqueado**, comprobado con la prueba indicada

Para exportarlo: pegar el bloque en https://mermaid.live → PNG/SVG, o verlo en GitHub/Obsidian.

```mermaid
flowchart TB
    internet((Internet))
    usuario["Administrador<br/>(AWS CLI / EC2 Instance Connect)"]

    subgraph vpc["VPC Hospital-Castillejos-VPC · 10.0.0.0/24 · us-east-1a"]
        igw["Hospital-IGW<br/>Internet Gateway"]

        subgraph dmz["DMZ 10.0.0.96/28 · RT-Publica: 0.0.0.0/0 → IGW"]
            nat["Hospital-NAT · 10.0.0.101<br/>NAT Gateway público + Elastic IP"]
        end

        subgraph ti["TI 10.0.0.112/28 · SG-TI (entrada: solo 22 desde SG-TI)"]
            eice["EC2 Instance Connect Endpoint<br/>10.0.0.122"]
            ec2ti["Hospital-EC2-TI · 10.0.0.117<br/>ufw: 22 desde TI · NTP → .46"]
        end

        subgraph srv["Servidores 10.0.0.32/27 · SG-Servidores"]
            ec2srv["Hospital-EC2-Servidores · 10.0.0.46<br/>OpenLDAP :389 · Apache intranet :80 (LDAP)<br/>chrony NTP :123/udp · ufw por rol"]
        end

        subgraph med["Médicos 10.0.0.0/27 · SG-Medicos"]
            ec2med["Hospital-EC2-Medicos-Prueba · 10.0.0.28<br/>NTP → .46"]
        end

        subgraph vis["Visitantes 10.0.0.64/27 · SG-Visitantes · NACL: 90 SSH desde TI · 100 DENY 10.0.0.0/24"]
            ec2vis["Hospital-EC2-Visitantes-Prueba · 10.0.0.69<br/>NTP → Amazon Time Sync"]
        end

        aws["Servicios de AWS (no filtrados por SG/NACL)<br/>DHCP Options (ec2.internal) · Amazon DNS 10.0.0.2<br/>Amazon Time Sync 169.254.169.123"]
    end

    usuario -->|"SSH por el endpoint"| eice
    eice -->|"SSH 22"| ec2ti
    eice -->|"SSH 22"| ec2srv
    eice -->|"SSH 22"| ec2med
    eice -->|"SSH 22 (NACL regla 90)"| ec2vis

    ec2ti -->|"SSH 22 · ICMP · HTTP 80 · LDAP 389 · NTP 123 (TI-01…05)"| ec2srv
    ec2ti -->|"SSH 22 (TI-06)"| ec2med
    ec2ti -->|"SSH 22 (TI-07)"| ec2vis
    ec2med -->|"HTTP 80 · NTP 123 (MED-03, MED-05)"| ec2srv

    ec2med -.->|"BLOQUEADO 22/ICMP (MED-01/02)"| ec2ti
    ec2srv -.->|"BLOQUEADO 22 (SRV-01)"| ec2ti
    ec2vis -.->|"BLOQUEADO todo (VIS-01…09, 14, 15)"| ec2srv
    ec2med -.->|"BLOQUEADO LDAP 389 · SSH 22 (MED-04/06)"| ec2srv

    ec2srv -->|"NTP upstream"| aws
    ec2vis -->|"NTP (VIS-13)"| aws
    ec2ti -->|"DHCP · DNS"| aws

    ec2med -->|"0.0.0.0/0 (MED-10)"| nat
    ec2vis -->|"HTTPS (VIS-11/12)"| nat
    ec2ti -->|"HTTPS (TI-09)"| nat
    ec2srv -->|"80/443 (apt)"| nat
    nat --> igw --> internet
    internet -.->|"BLOQUEADO 22/80/443/389 (EXT)"| nat

    classDef probado fill:#d4edda,stroke:#28a745,color:#000
    classDef configurado fill:#d6e9f8,stroke:#1f6fb2,color:#000
    class eice,ec2ti,ec2srv,ec2med,ec2vis,nat,aws probado
    class igw configurado
```

## Leyenda de estado (29/10)

| Elemento | Estado | Evidencia |
|---|---|---|
| VPC, 5 subredes, rutas pública y privada, IGW, NAT Gateway | **probado** (salida HTTPS 200 desde TI, Médicos y Visitantes) | `E4.5_estado-previo-rutas.json`, `E7.1_nat-gateway.json`, CSV E8 |
| DHCP de AWS en las 4 EC2 | **probado** | `E5.2_*` |
| NTP: chrony en .46 con Time Sync; TI/Médicos → .46; Visitantes → Time Sync | **probado** | `E5.3_*`, `E5.2_E5.4_*`, TI-04, MED-05, VIS-13 |
| OpenLDAP en .46 (escucha en todas las interfaces; 389 solo Servidores/TI) | **probado** | `probar-ldap.sh` 4/4, TI-03, MED-04, VIS-04 |
| Intranet Apache + LDAP (`Require ip` + `ldap-group`) | **probado** | E6.2 7/7, TI-02, SRV-02, MED-03/08/09, VIS-02/14 |
| SG-Servidores, SG-Medicos, SG-Visitantes, NACL regla 90 | **probado** | `E7.2_*`, CSV E8 |
| Hardening (ufw por rol, SSH sin contraseña ni root) en las 4 EC2 | **probado** | `aws/<equipo>/hardening-*`, `E7.5_*` |
| DMZ con EC2 propia (web pública de Fase 1) | **no implementada** (fuera de alcance; DMZ-01…03 OMITIDAS) | — |

> Lo del Lab 5 (DNS propio, correo, FTP) corrió en VMs locales y **no** forma parte de AWS.
