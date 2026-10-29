# Guion E10.5 (borrador) — Presentación ejecutiva y demo

Duración objetivo: **10 min** (6 de presentación + 4 de demo). Ajustar al tiempo que dé el curso.

## Presentación (6 min)

| # | Tema | Mensaje clave | Quién (propuesto) | Apoyo |
|---|---|---|---|---|
| 1 | Problema | El hospital maneja expedientes, citas y resultados a mano y sin control de acceso | Roberto | Fase 1 |
| 2 | Diseño | Una VPC con 5 subredes por rol (Médicos, Servidores, Visitantes, DMZ, TI) y solo una puerta de salida a Internet (la NAT) | Anthony | Diagrama E10.1 |
| 3 | Servicios | LDAP (una cuenta por persona y grupos por rol), intranet que valida contra LDAP, NTP interno, DHCP de AWS | Sebastián / Isabella | E4.1 |
| 4 | Seguridad | TI llega a todo y nadie llega a TI. Visitantes solo sale a Internet. La intranet no se ve desde Visitantes ni desde Internet. Hardening | Anthony / Leonardo | Matriz E4.2 |
| 5 | Resultados | **40 PASS / 0 FAIL** desde TI (10), Servidores (3), Médicos (10), Visitantes (13) e Internet (4); 6 OMITIDAS por no haber EC2 en la DMZ | Roberto | `evidencias/INDICE-EVIDENCIAS.md` |
| 6 | Costos y cierre | Costo real de las pruebas, todo detenido (Stop). Mejoras: HTTPS, NAT Gateway por zona de disponibilidad (alta disponibilidad), LDAPS | Majo | Bills |

## Demo en vivo (4 min) — orden sugerido

1. **SSH por el endpoint a TI** (no hay IP pública ni puerto 22 abierto a Internet).
2. Desde TI: `curl -u ti01 http://10.0.0.46/intranet/` → "Bienvenido(a)" (login LDAP). Con una contraseña incorrecta → 401. (O `INTRANET_URL=http://10.0.0.46 bash isabella/probar-web.sh`.)
3. En **Servidores** (tiene `ldap-utils`; TI no): `ldapwhoami -x -H ldap://10.0.0.46 -D uid=ti01,ou=People,dc=hospital,dc=redes,dc=test -W` → `dn:uid=ti01,…`. Con una contraseña incorrecta → `Invalid credentials (49)`. Desde **Médicos**: `timeout 5 bash -c 'echo > /dev/tcp/10.0.0.46/389'` → timeout (LDAP solo desde Servidores y TI).
4. Desde TI: `chronyc sources` → `^*` en `10.0.0.46`. En Servidores: `chronyc clients`.
5. **Visitantes:**
   - `curl https://example.com` → `200` (sale por la NAT).
   - `curl -m 5 http://10.0.0.46/` → timeout (bloqueado).
6. **Servidores → TI:** `ssh 10.0.0.117` → timeout (nadie llega a TI).
7. Cierre: mostrar el CSV o la matriz con los PASS y, en la consola, las instancias en **Stopped**.

**Plan B** si algo falla en vivo: mostrar las capturas de evidencia (`evidencias/E*.png`) y el CSV de la corrida previa (`evidencias/aws/<equipo>/resultados-*.csv`).

### Cómo conectarse durante la demo (PowerShell, clave en `ssh-agent`)

| Equipo | Instance ID | Túnel (una ventana por equipo) | IP |
|---|---|---|---|
| Servidores | `i-095520a21f761f97d` | `aws ec2-instance-connect open-tunnel --instance-id i-095520a21f761f97d --local-port 2222 --remote-port 22 --region us-east-1` | 10.0.0.46 |
| TI | `i-0bfd1235ccdec6e96` | `… --instance-id i-0bfd1235ccdec6e96 --local-port 2223 …` | 10.0.0.117 |
| Médicos | `i-080244876b92e25c6` | `… --instance-id i-080244876b92e25c6 --local-port 2224 …` | 10.0.0.28 |
| Visitantes | `i-0c8ad80ff90f5bdbd` | `… --instance-id i-0c8ad80ff90f5bdbd --local-port 2225 …` | 10.0.0.69 |

Después: `aws ec2-instance-connect send-ssh-public-key --region us-east-1 --instance-id <id> --availability-zone us-east-1a --instance-os-user ubuntu --ssh-public-key "file://$env:USERPROFILE\.ssh\hospital_fase3.pub"`, y en menos de 60 s: `ssh -i $env:USERPROFILE\.ssh\hospital_fase3 -p <puerto> -o IdentitiesOnly=yes -o HostKeyAlias=<id> ubuntu@127.0.0.1`.

Para repetir toda la matriz en vivo: `cd ~/fase3/leonardo && bash tests_fase3.sh <ti|servidores|medicos|visitantes>` (unos 30 s por origen).

## Preguntas probables

- **¿Por qué un NAT Gateway y no una NAT instance?** Es administrado por AWS (sin parches, iptables
  ni punto de falla propio) y se configuró en minutos. A cambio, cuesta más por hora y no se puede
  "detener": se elimina después de la demo. La NAT instance (más barata y con control por iptables)
  se evaluó y quedó documentada como alternativa.
- **¿Por qué no hay DHCP propio?** AWS no lo permite en una VPC. Se usa el DHCP option set y se demuestra lo que recibe cada EC2.
- **¿Quién bloquea a Visitantes?** La NACL (stateless) y, además, los SG de destino (defensa en profundidad).
- **¿Cómo administran sin abrir el 22 a Internet?** Con el EC2 Instance Connect Endpoint dentro de la subred TI.
