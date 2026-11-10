# Diagrama — Hospital Privado Castillejos (Fase 4)

Estado al **08/11/2026**, según la configuración real de AWS y las pruebas de la Fase 4
(ver `fase4/evidencias/INDICE-EVIDENCIAS.md`).
- verde = **probado en AWS** (Fase 3, sigue pasando la regresión) · naranja = **nuevo en Fase 4, probado** · azul = externo / AWS administrado
- flechas gruesas = tráfico de la VPN · punteadas = **bloqueado** (comprobado) o auxiliar (DNS, ACME)
- Rutas: RT-Privada (Médicos, Servidores, Visitantes, TI) → 0.0.0.0/0 NAT y **10.8.0.0/24 → ENI de la DMZ** (retorno de la VPN sin NAT). Todas las subredes privadas salen por el NAT; en el dibujo solo se muestra una flecha.

PNG exportados con mermaid-cli: `fase4/DIAGRAMA-F4.png` (horizontal, para diapositivas) y `fase4/DIAGRAMA-F4-vertical.png` (para el informe), desde `DIAGRAMA-F4.mmd` y `DIAGRAMA-F4-vertical.mmd`.

```mermaid
flowchart LR
    subgraph ext["Internet"]
        cliente["Paciente / cliente<br/>(navegador)"]
        casa["Trabajador remoto (WireGuard)<br/>hospital-ti 10.8.0.2<br/>hospital-medico 10.8.0.10"]
        duck["DuckDNS<br/>hospital-castillejos.duckdns.org<br/>→ 3.227.168.73"]
        le["Let's Encrypt<br/>(certbot)"]
    end

    subgraph vpc["VPC 10.0.0.0/24 · us-east-1a"]
        igw["Hospital-IGW"]

        subgraph dmz["DMZ 10.0.0.96/28 · RT-Pública → IGW"]
            ec2dmz["<b>Hospital-EC2-DMZ</b> 10.0.0.100<br/>EIP 3.227.168.73 · SG-DMZ<br/>nginx: 80 → 301 · 443 TLS + HSTS<br/>app de citas (Flask/gunicorn)<br/>WireGuard wg0 10.8.0.1/24 · UDP 51820<br/>reenvío por peer · ufw · snmpd v3"]
            nat["Hospital-NAT 10.0.0.101<br/>NAT Gateway"]
        end

        subgraph ti["TI 10.0.0.112/28"]
            eice["EC2 Instance Connect<br/>Endpoint 10.0.0.122"]
            ec2ti["<b>Hospital-EC2-TI</b> 10.0.0.117<br/>Prometheus + snmp_exporter<br/>+ Grafana (solo 127.0.0.1)"]
        end

        subgraph srv["Servidores 10.0.0.32/27"]
            ec2srv["<b>Hospital-EC2-Servidores</b> 10.0.0.46<br/>OpenLDAP · Apache intranet (LDAP)<br/>NTP · snmpd v3"]
        end

        subgraph vis["Visitantes 10.0.0.64/27"]
            ec2vis["<b>Visitantes-Prueba</b> 10.0.0.69<br/>snmpd v3<br/>NACL: niega 10.0.0.0/24 y 10.8.0.0/24"]
        end

        subgraph med["Médicos 10.0.0.0/27"]
            ec2med["<b>Médicos-Prueba</b> 10.0.0.28<br/>snmpd v3"]
        end
    end

    cliente -->|"HTTPS 443 · HTTP 80 → 301"| igw
    casa -->|"UDP 51820 (túnel cifrado)"| igw
    cliente -.->|DNS| duck
    le -.->|"reto HTTP-01"| igw
    igw --> ec2dmz

    ec2dmz ==>|"VPN TI y médico: intranet 80 · VPN TI: SSH 22 (también a TI y Médicos)"| ec2srv
    ec2dmz ==>|"VPN TI: SSH 22"| ec2ti
    ec2dmz -.->|"VPN: BLOQUEADO"| ec2vis

    ec2ti -->|"SNMPv3 authPriv UDP 161"| ec2srv
    ec2ti -->|SNMPv3| ec2med
    ec2ti -->|"SNMPv3 (NACL 91)"| ec2vis
    ec2ti -->|"SNMPv3 · SSH"| ec2dmz
    eice -->|"SSH 22 administración (5 EC2)"| ec2ti

    ec2med -->|"intranet 80 · NTP"| ec2srv
    ec2vis -.->|"BLOQUEADO todo lo interno"| ec2srv

    ec2srv -->|"salida 0.0.0.0/0"| nat
    nat --> igw

    classDef probado fill:#d4edda,stroke:#28a745,color:#000
    classDef nuevo fill:#ffe5cc,stroke:#e07b00,color:#000
    classDef externo fill:#d6e9f8,stroke:#1f6fb2,color:#000
    class eice,ec2srv,ec2med,ec2vis,nat probado
    class ec2dmz,ec2ti nuevo
    class cliente,casa,duck,le,igw externo
```

## Componentes nuevos de la Fase 4

| Componente | Dónde | Estado | Evidencia |
|---|---|---|---|
| DMZ con EC2 propia (`Hospital-EC2-DMZ`, EIP 3.227.168.73, SG-DMZ) | 10.0.0.100 | **probado** | `F4.1_*`, `F4.5_*` |
| Web pública de citas con dominio `hospital-castillejos.duckdns.org` | DMZ (nginx + Flask/gunicorn + SQLite) | **probado** (crear/consultar cita) | `F4.2_pruebas-web-laptop.txt` |
| TLS Let's Encrypt, solo HTTPS, HTTP → 301, HSTS, renovación automática | DMZ | **probado** (`renew --dry-run` OK) | `F4.2_certbot-y-renovacion.txt` |
| VPN WireGuard con reglas por peer, sin NAT (ruta 10.8.0.0/24 → ENI DMZ) | DMZ + RT-Privada | **probado** (TI 12/12, médico 9/9) | `F4.3_*`, `F4.5_post-hardening-dmz.txt` |
| SNMPv3 authPriv (sin v1/v2c) en las 5 EC2 | todas | **probado** (5/5; v2c y clave incorrecta rechazados) | `F4.4_pruebas-snmp-desde-ti.csv`, `F4.4_sonda-snmp-alcance.csv` |
| Prometheus + snmp_exporter + Grafana (extra 10 %), solo TI | TI 127.0.0.1 | **probado** (dashboard con 5 equipos) | `F4.4_grafana-dashboard.png` |
| Firewall adaptado (SG, NACL 91, ufw en las 5 EC2, hardening DMZ) | todas | **probado** (regresión 32/32) | `F4.6_regresion-fase3-5-origenes.csv` |

> El acceso a Grafana es solo para TI: túnel SSH `-L 3000` por el EC2 Instance Connect Endpoint o desde el peer VPN `hospital-ti`.
