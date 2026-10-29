# Informe de Fase 3 — estructura y control de requisitos

Nota de partida: el informe se trabaja **sobre el DOCX de Fase 2** (PDF de Fase 3, §4). Ese DOCX no estaba entre los archivos que recibí, así que esta estructura es una propuesta para agregar a él; ajusta la numeración a la que ya tenga. Antes de editar, guarda una copia intacta en `informe/respaldo/Informe-Fase2-ORIGINAL.docx`.

## 1. Requisitos del PDF → dónde se cubren

| Requisito del PDF de Fase 3 | Sección del informe | Responsable del contenido | Estado hoy |
|---|---|---|---|
| DHCP | 5 | Roberto (con capturas de Majo) | propuesto: DHCP administrado por AWS; sin prueba aún |
| NTP | 6 | Leonardo | scripts preparados; sin prueba en AWS |
| LDAP | 7 | Sebastián | scripts preparados; probados solo en la VM local si Sebastián lo confirma |
| Servidor web interno, solo desde dentro de la red | 8 | Isabella | preparado; sin prueba en AWS |
| SSH a las instancias | 9 | Anthony / Majo | ping y SSH con clave TI → Servidores probados en Fase 2 |
| Visitantes con Internet, sin acceso a las demás subredes | 9 y 10 | Anthony / Majo | no hay Internet para Visitantes; la NACL nunca se probó con una EC2 |
| TI llega a todas las subredes, ninguna llega a TI | 9 y 10 | Anthony / Majo | Servidores → TI (TCP/22) bloqueado en Fase 2; el resto, sin probar |
| Intranet accesible desde todas las subredes excepto Visitantes y no desde Internet | 8 y 9 | Isabella / Anthony | sin implementar |
| NAT | 4 | Leonardo / Majo | sin implementar (decisión de NAT pendiente) |
| Hardening (cerrar puertos sin uso) | 11 | Leonardo | script preparado; sin ejecutar |
| Diagrama actualizado | 3 | Anthony | pendiente |
| Capturas, documentación consultada, archivos de configuración | Anexos | todos / Roberto | en curso |
| Presentación ejecutiva y demo en vivo | fuera del informe | Anthony | pendiente |

El PDF avisa que "depende del caso asignado, los casos de uso y reglas pueden ser distintos a los mostrados". Está en los pendientes del grupo confirmar si al Hospital le aplican todas.

Los estados de esta tabla salen del reparto del 28/10 14:00 y de los archivos de la carpeta; **actualízalos conforme Majo ejecute y se obtengan evidencias**. La columna manda: si algo dice "propuesto", el informe no puede decir "se implementó".

## 2. Capítulos propuestos

1. **Resumen ejecutivo y alcance.** Qué se pedía, qué quedó funcionando, qué no. Incluir la tabla de estado (propuesto / configurado / probado) al cierre del trabajo.
2. **Punto de partida (Fase 2).** Qué existía: VPC 10.0.0.0/24, cinco subredes, dos EC2, endpoint de conexión, SG y NACL. Con la **corrección sobre SG-Servidores** (ver `TEXTO-SG-SERVIDORES.md`). Dejar claro que lo del Lab 5 (DNS, correo, FTP, etc.) se hizo en una VM local, no en AWS.
3. **Diseño de la Fase 3.** Diagrama, tabla servicio → instancia → puertos → dependencias (Anthony, E4.1), decisiones (dominio y base LDAP, NAT, DHCP).
4. **Salida a Internet y NAT.** IGW, rutas, NAT instance o NAT Gateway, comparación de costos con fecha y fuente (Majo).
5. **DHCP.** `dhcp/DHCP-aws-administrado.md` ya trae el texto base.
6. **NTP.** chrony en 10.0.0.46 con Amazon Time Sync como fuente; clientes (Leonardo).
7. **LDAP.** Base, grupos, usuarios ficticios, qué se reutilizó del Lab 5 y qué se cambió (Sebastián).
8. **Intranet.** Apache + LDAP, restricción por IP, HTTP/HTTPS (Isabella).
9. **Firewall y ACL.** Matriz de flujos; para cada regla, **quién bloquea qué** (SG, NACL, firewall del SO); lo que la NACL no filtra por diseño de AWS (con cita) (Anthony).
10. **Pruebas.** `matriz/matriz-consolidada.md`: 35 pruebas esperadas, PASS/FAIL/PENDIENTE y archivo de evidencia. Explicar el criterio: un "bloqueado" que conecta o que responde "connection refused" cuenta como FAIL (el paquete llegó al equipo).
11. **Hardening.** Puertos antes/después por rol, `ufw`, SSH sin contraseña ni root (Leonardo).
12. **Costos.** Saldo de créditos antes y después, costo de lo creado, presupuesto (Majo).
13. **Limitaciones y trabajo pendiente.** Todo lo que quedó sin probar, escrito sin adornos.
14. **Documentación consultada.** Con URL y fecha de consulta.
15. **Anexos.** Archivos de configuración (rutas en el repo), índice de evidencias.

## 3. Reglas de redacción

- Cada afirmación de funcionamiento cita su evidencia (nombre de archivo o número de imagen).
- Distinguir en el texto **propuesto / configurado / probado**.
- No atribuir a AWS nada que solo corrió en la VM local.
- Sin contraseñas, claves, ID de cuenta ni ARN en texto ni en capturas.
- Si una prueba falló, se reporta el fallo y lo que se hizo; no se reemplaza por una captura posterior sin decirlo.
