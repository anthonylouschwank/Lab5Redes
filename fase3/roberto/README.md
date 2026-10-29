# Fase 3 — Entrega de Roberto (pruebas, evidencias e informe)

Casillas del reparto: E1.4–E1.7, E2.3, E5.1, E5.2, E8 (matriz), E9, E10.2–E10.4, E10.6.
No tengo la lista detallada de qué pide cada casilla; lo que sigue sale del texto de la sección 4.6 del reparto. Si el checklist de la rúbrica define algo distinto, manda el checklist.

**Estado: preparado, nada probado en AWS.** Todo lo de aquí se corrió solo en un entorno de prueba (datos sintéticos). Los resultados reales dependen de que Majo ejecute en las EC2.

## Qué hay

| Carpeta | Para qué | Casilla |
|---|---|---|
| `matriz/` | `matriz-esperada.csv` (35 pruebas, tomadas de `tests_fase3.sh` de Leonardo) y `consolidar_matriz.py`, que junta los CSV de cada EC2 en `matriz-consolidada.md/.csv` | E8 |
| `dhcp/` | `dhcp-capturar.sh` (evidencia por EC2) y `DHCP-aws-administrado.md` (decisión, lectura del option set, texto para el informe) | E5.1, E5.2 |
| `evidencias/` | Convención de nombres, qué ocultar, `INDICE-EVIDENCIAS.csv` | E9 |
| `herramientas/` | `revisar-secretos.sh` (revisión final de texto) | E9.4, E10.6 |
| `informe/` | Estructura y control de requisitos, corrección de SG-Servidores, mensaje para pedir secciones | E10.2–E10.4 |

## Flujo recomendado

1. **Hoy:** manda `informe/SOLICITUD-SECCIONES.md` al grupo. Pide a Majo que corra `dhcp-capturar.sh` en cada EC2 que encienda.
2. **Cuando Leonardo/Majo tengan CSV:** copiarlos a `evidencias/csv/` y correr
   ```bash
   python3 -I fase3/roberto/matriz/consolidar_matriz.py            # resumen + matriz-consolidada.md/.csv
   python3 -I fase3/roberto/matriz/consolidar_matriz.py --estricto # además: código 1 si hay FAIL o PENDIENTE
   ```
   Las `PENDIENTE` no son éxitos: son pruebas sin ejecutar (p. ej. destino sin IP en `fase3.env`).
3. **Informe:** guardar copia intacta del DOCX de Fase 2, agregar capítulos según `informe/ESTRUCTURA-INFORME-FASE3.md`, aplicar `TEXTO-SG-SERVIDORES.md`.
4. **Antes de entregar:** `bash fase3/roberto/herramientas/revisar-secretos.sh` y revisión a ojo de capturas y DOCX.

## Pasos humanos que no puedo hacer por ti

Ver la lista completa en la respuesta del chat; resumen: conseguir el DOCX de Fase 2 y verificar la Imagen 12, leer el option set en la consola (o pedírselo a Majo), tomar y sanitizar capturas, correr `consolidar_matriz.py` con CSV reales, confirmar la hora de entrega, y la revisión final de secretos.
