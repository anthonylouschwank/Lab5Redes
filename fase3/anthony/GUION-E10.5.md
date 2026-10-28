# Guion E10.5 (borrador) — Presentación ejecutiva y demo

Duración objetivo: **10 min** (6 de presentación + 4 de demo). Ajustar al tiempo que dé el curso.

## Presentación (6 min)

| # | Tema | Mensaje clave | Quién (propuesto) | Apoyo |
|---|---|---|---|---|
| 1 | Problema | El hospital maneja expedientes, citas y resultados a mano y sin control de acceso | Roberto | Fase 1 |
| 2 | Diseño | Una VPC con 5 subredes por rol (Médicos, Servidores, Visitantes, DMZ, TI) y solo una puerta de salida a Internet (la NAT) | Anthony | Diagrama E10.1 |
| 3 | Servicios | LDAP (una cuenta por persona y grupos por rol), intranet que valida contra LDAP, NTP interno, DHCP de AWS | Sebastián / Isabella | E4.1 |
| 4 | Seguridad | TI llega a todo y nadie llega a TI. Visitantes solo sale a Internet. La intranet no se ve desde Visitantes ni desde Internet. Hardening | Anthony / Leonardo | Matriz E4.2 |
| 5 | Resultados | N de N pruebas PASS, por origen | Roberto | CSV / matriz |
| 6 | Costos y cierre | Costo real de las pruebas, todo detenido (Stop). Mejoras: HTTPS, NAT Gateway para alta disponibilidad, LDAPS | Majo | Bills |

## Demo en vivo (4 min) — orden sugerido

1. **SSH por el endpoint a TI** (no hay IP pública ni puerto 22 abierto a Internet).
2. Desde TI: `curl -u ti01 http://10.0.0.46/` → página de la intranet (login LDAP). Con una contraseña incorrecta → 401.
3. Desde TI: `ldapwhoami` con `ti01` (bind válido) y con una contraseña incorrecta → `Invalid credentials (49)`.
4. Desde TI: `chronyc sources` → `^*` en `10.0.0.46`. En Servidores: `chronyc clients`.
5. **Visitantes:**
   - `curl https://example.com` → `200` (sale por la NAT).
   - `curl -m 5 http://10.0.0.46/` → timeout (bloqueado).
6. **Servidores → TI:** `ssh 10.0.0.117` → timeout (nadie llega a TI).
7. Cierre: mostrar el CSV o la matriz con los PASS y, en la consola, las instancias en **Stopped**.

**Plan B** si algo falla en vivo: mostrar las capturas de evidencia (`evidencias/E*.png`) y el CSV de la corrida previa.

## Preguntas probables

- **¿Por qué una NAT instance y no un NAT Gateway?** Costo para un piloto y control con iptables. El
  Gateway sería la opción en producción, por alta disponibilidad y menos mantenimiento.
- **¿Por qué no hay DHCP propio?** AWS no lo permite en una VPC. Se usa el DHCP option set y se demuestra lo que recibe cada EC2.
- **¿Quién bloquea a Visitantes?** La NACL (stateless) y, además, los SG de destino (defensa en profundidad).
- **¿Cómo administran sin abrir el 22 a Internet?** Con el EC2 Instance Connect Endpoint dentro de la subred TI.
