# Diagrama E10.1 — Hospital Privado Castillejos (Fase 3)

Estado al **28/10/2026**, según el informe en curso. Actualizar los colores a medida que Majo configure
y Roberto pruebe:
- verde = **probado**
- azul = **configurado**
- gris punteado = **propuesto**

Para exportarlo: pegar el bloque en https://mermaid.live → PNG/SVG, o verlo en GitHub.

```mermaid
flowchart TB
    internet((Internet))
    usuario["Administrador<br/>(consola AWS / EC2 Instance Connect)"]

    subgraph vpc["VPC Hospital-Castillejos-VPC · 10.0.0.0/24 · us-east-1a"]
        igw["Hospital-IGW<br/>Internet Gateway"]

        subgraph dmz["DMZ 10.0.0.96/28 · RT-Publica: 0.0.0.0/0 → IGW"]
            nat["Hospital-NAT<br/>NAT Gateway + Elastic IP"]
            ec2dmz["EC2 de prueba (opcional) · SG-DMZ"]
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

    ec2med -->|"HTTP 80 · NTP 123"| ec2srv
    ec2ti -->|"HTTP 80 · LDAP 389 · NTP 123"| ec2srv
    ec2dmz -.->|"HTTP 80 · NTP 123"| ec2srv
    ec2vis -.->|"BLOQUEADO (NACL + SG)"| ec2srv
    ec2srv -.->|"BLOQUEADO (SG-TI)"| ec2ti

    ec2ti -->|"DHCP · NTP"| aws
    ec2srv -->|"NTP"| aws
    ec2vis -->|"NTP directo"| aws

    ec2med -->|"0.0.0.0/0 (ruta privada)"| nat
    ec2vis -->|"80/443"| nat
    ec2srv -->|"80/443 (apt)"| nat
    nat --> igw --> internet
    internet -.->|"BLOQUEADO (sin conexiones entrantes)"| nat

    classDef probado fill:#d4edda,stroke:#28a745,color:#000
    classDef configurado fill:#d6e9f8,stroke:#1f6fb2,color:#000
    classDef propuesto fill:#f2f2f2,stroke:#888,stroke-dasharray:5 4,color:#000
    class eice,ec2ti,aws probado
    class ec2srv,nat,igw configurado
    class ec2med,ec2vis,ec2dmz propuesto
```

## Leyenda de estado (28/10)

| Elemento | Estado | Evidencia |
|---|---|---|
| VPC, 5 subredes, tablas de rutas, SG-TI, NACL Visitantes, endpoint | configurado | Capturas de Fase 2 y estado inicial de Fase 3 |
| SSH e ICMP TI → Servidores; TCP 22 Servidores → TI bloqueado | **probado** | Fase 2 |
| **DHCP de AWS** en TI (`10.0.0.117/28`, gateway `.113`, DNS `10.0.0.2`, `ec2.internal`) | **probado** | Informe Fase 3 (salida de `ip`, `resolvectl` y lease) |
| **chrony en TI con Amazon Time Sync** (`^*` 169.254.169.123) | **probado** | Informe Fase 3 (`chronyc tracking/sources`) |
| Hospital-IGW + `0.0.0.0/0 → IGW` (RT-Publica) | configurado | Informe Fase 3 |
| Hospital-NAT (NAT Gateway) + `0.0.0.0/0 → NAT` (RT-Privada) | configurado (falta la captura de `curl` desde TI y Servidores) | Informe Fase 3 |
| SG-Servidores salida 80/443 | configurado | Informe Fase 3 |
| slapd en `10.0.0.46` (a mano; solo `127.0.0.1`) | configurado parcialmente: pendientes los Pasos 2b/2c de REGLAS | Informe Fase 3 |
| Entradas de SG-Servidores (80/389/123), SG-Medicos/Visitantes/DMZ, NACL regla 90, EC2 de prueba | propuesto | REGLAS-E4.4 |
| Intranet y NTP servidor en `10.0.0.46` | propuesto en AWS (intranet probada en VM local, 9/9) | `fase3/isabella`, `fase3/leonardo` |

> Lo del Lab 5 (DNS propio, correo, FTP) corrió en VMs locales y **no** forma parte de AWS.
