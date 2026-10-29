# Mensaje para pedir las secciones del informe

Para copiar y pegar en el chat del grupo (ajusta la hora límite). El reparto dice que cada quien aporta su sección: qué hizo, qué reutilizó del Lab 5, resultados y limitaciones.

---

Hola equipo. Estoy armando el informe de la Fase 3 sobre el DOCX de la Fase 2. La entrega es el 29/10 (hora por confirmar). **Necesito su sección antes de [HORA LÍMITE], aunque esté incompleta.** Márquenla con lo que de verdad está hecho:

- **Propuesto**: está escrito, nadie lo ha corrido en AWS.
- **Configurado**: está aplicado en AWS, sin prueba.
- **Probado**: lo corrieron y tienen la salida o la captura.

Por favor mándenme, en texto plano o Markdown (sin imágenes pegadas; las capturas van aparte con el nombre `E<casilla>_<descripcion>.png`):

1. Qué hicieron, en 5–10 líneas.
2. Qué reutilizaron del Lab 5 y qué cambiaron.
3. Resultado: estado (propuesto / configurado / probado) y el archivo de evidencia de cada afirmación.
4. Limitaciones: lo que no se probó o no funcionó. Sin adornos, eso también puntúa.
5. Archivos de configuración que deben ir como anexo (ruta en el repo).

Datos específicos:

- **Majo:** saldo de créditos antes y después, costo de lo creado, tabla de precios con fecha y fuente, y las capturas del índice `evidencias/INDICE-EVIDENCIAS.csv` que le tocan. **Capturen antes de cada cambio de SG/NACL/ruta.** Y por favor corran `dhcp-capturar.sh` en cada EC2 que enciendan.
- **Leonardo:** los `resultados-<origen>-<fecha>.csv` de cada EC2, y `hardening-antes/despues-<host>.txt`.
- **Sebastián:** salida de `probar-ldap.sh` (incluido el bind inválido) y dónde se probó (VM local o AWS).
- **Isabella:** salida de `probar-web.sh` (401 / 200 / 401) y si quedó HTTP o HTTPS.
- **Anthony:** diagrama, matriz de flujos y reglas finales, con "quién bloquea qué" y la cita de lo que la NACL no filtra.

Ojo: **nada de contraseñas, claves, ID de cuenta ni ARN** en lo que me manden.

---
