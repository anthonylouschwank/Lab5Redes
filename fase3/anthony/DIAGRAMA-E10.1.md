# Diagrama E10.1 — Hospital Privado Castillejos (Fase 3)

Estado al **28/10/2026**. Actualizar los colores a medida que Majo configure y Roberto pruebe:
- verde = **probado**
- azul = **configurado**
- gris punteado = **propuesto**

Para exportarlo: pegar el bloque en https://mermaid.live → PNG/SVG, o verlo en GitHub.

```mermaid
flowchart TB
    internet((Internet))
    usuario["Administrador<br/>(consola AWS / EC2 Instance Connect)"]

    subgraph vpc["VPC Hospital-Castillejos-VPC · 10.0.0.0/24 · us-east-1a"]
        igw["Internet Gateway"]

        subgraph dmz["DMZ 10.0.0.96/28 · RT-Publica: 0.0.0.0/0 → IGW"]
            nat["NAT instance · SG-NAT<br/>iptables MASQUERADE<br/>IP pública · src/dst check OFF"]
        end

        subgraph ti["TI 10.0.0.112/28 · SG-TI"]
            eice["EC2 Instance Connect Endpoint<br/>10.0.0.122"]
            ec2ti["Hospital-EC2-TI<br/>10.0.0.117"]
        end

        subgraph srv["Servidores 10.0.0.32/27 · SG-Servidores"]
            ec2srv["Hospital-EC2-Servidores 10.0.0.46<br/>OpenLDAP :389 · Apache intranet :80<br/>chrony NTP :123/udp"]
        end

        subgraph med["Médicos 10.0.0.0/27 · SG-Medicos"]
            ec2med["EC2 de prueba"]
        end

        subgraph vis["Visitantes 10.0.0.64/27 · SG-Visitantes · NACL: DENY 10.0.0.0/24 (salvo SSH desde TI)"]
            ec2vis["EC2 de prueba"]
        end

        aws["Servicios de AWS (no filtrados por SG/NACL)<br/>DHCP option set · Amazon DNS 10.0.0.2<br/>Amazon Time Sync 169.254.169.123"]
    end

    usuario -->|"SSH por el endpoint"| eice
    eice -->|"SSH 22"| ec2ti
    eice -->|"SSH 22"| ec2srv
    eice -->|"SSH 22"| ec2med
    eice -->|"SSH 22 (NACL regla 90)"| ec2vis
    eice -->|"SSH 22"| nat

    ec2med -->|"HTTP 80 · NTP 123"| ec2srv
    nat -->|"HTTP 80 · NTP 123"| ec2srv
    ec2ti -->|"HTTP 80 · LDAP 389 · NTP 123"| ec2srv
    ec2vis -.->|"BLOQUEADO (NACL + SG)"| ec2srv
    ec2srv -.->|"BLOQUEADO (SG-TI)"| ec2ti

    ec2srv -->|"NTP"| aws
    ec2vis -->|"NTP directo"| aws

    ec2med -->|"80/443 por la ruta privada"| nat
    ec2vis -->|"80/443"| nat
    ec2srv -->|"80/443 (apt)"| nat
    nat --> igw --> internet
    internet -.->|"BLOQUEADO (SG-NAT sin entrada)"| nat

    classDef probado fill:#d4edda,stroke:#28a745,color:#000
    classDef configurado fill:#d6e9f8,stroke:#1f6fb2,color:#000
    classDef propuesto fill:#f2f2f2,stroke:#888,stroke-dasharray:5 4,color:#000
    class eice,ec2ti,ec2srv configurado
    class nat,igw,ec2med,ec2vis propuesto
```

## Leyenda de estado (28/10)

| Elemento | Estado | Evidencia |
|---|---|---|
| VPC, 5 subredes, 2 tablas de rutas (solo local) | configurado | Capturas de Fase 2 |
| EC2 TI y Servidores, endpoint, SG-TI, SG-Servidores (22/ICMP), NACL Visitantes | configurado | Capturas de Fase 2 |
| SSH e ICMP TI → Servidores; TCP 22 Servidores → TI bloqueado | **probado** | Fase 2 |
| IGW, NAT instance, rutas `0.0.0.0/0`, SG-NAT/Medicos/Visitantes, reglas nuevas de SG-Servidores, NACL regla 90 | propuesto | REGLAS-E4.4 |
| LDAP, intranet, NTP en `10.0.0.46` | propuesto (probado en VM local, **no** en AWS) | `fase3/sebastian`, `fase3/leonardo` |
| DHCP de AWS | configurado (por defecto) | Roberto E5.1/E5.2 |

> Lo del Lab 5 (DNS propio, correo, FTP) corrió en VMs locales y **no** forma parte de AWS.
