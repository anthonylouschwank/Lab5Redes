# Corrección: salida de SG-Servidores en el informe

## El problema

El informe de Fase 2 dice que SG-Servidores conserva la salida predeterminada. Según el reparto (28/10, revisión del día) y la propia captura del informe (Imagen 12), **SG-Servidores no tiene reglas de salida**. Eso hay que corregirlo en el informe: describir lo observado y la configuración final, sin inventar historia.

No tengo el DOCX de Fase 2, así que no puedo citar la frase exacta ni confirmar la Imagen 12. **Roberto: abre la Imagen 12, comprueba que realmente muestra 0 reglas de salida y localiza el párrafo a reemplazar.** Si la captura dijera otra cosa, hay que volver a mirar el grupo en la consola antes de escribir nada.

## Texto de reemplazo (completar lo que está entre corchetes)

> **Grupo de seguridad SG-Servidores.** Reglas de entrada: SSH (TCP/22) e ICMP desde SG-TI. **Reglas de salida: ninguna** (Imagen 12 de este informe; verificado de nuevo en la consola el 28/10/2026). Un grupo de seguridad sin reglas de salida no permite tráfico que la instancia inicie hacia otros destinos; las respuestas a conexiones entrantes permitidas sí salen, porque los grupos de seguridad son con estado. Esto es coherente con los resultados de Fase 2: el ping y el SSH de TI hacia Servidores funcionan, y el intento de conexión TCP/22 de Servidores hacia TI quedó bloqueado. [Esta es la descripción del estado observado en Fase 2; no se afirma que fuera una decisión de diseño.]
>
> **Configuración final de Fase 3.** [Pegar aquí las reglas de salida que defina Anthony en E4.4 y aplique Majo, p. ej. HTTP/HTTPS hacia 0.0.0.0/0 o hacia la NAT para `apt`, con la captura posterior. Si al cierre siguiera sin reglas de salida, decirlo así.]

## Comprobaciones que lo respaldan

- La frase "las respuestas salen por ser con estado" es el comportamiento documentado de los grupos de seguridad de AWS; **citar la página de AWS** al incluirla en el informe (no la consulté hoy).
- La frase sobre qué tráfico no filtra AWS (DNS de Amazon, DHCP, Time Sync, metadatos) está asignada a Anthony (E4.4 punto 6). No la uses aquí hasta que él la confirme con cita.
