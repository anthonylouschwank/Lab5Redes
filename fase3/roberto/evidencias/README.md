# Evidencias de la Fase 3 — convención y control

Responsable: Roberto. Las evidencias respaldan el informe: cada afirmación de "funciona" debe apuntar a un archivo de aquí.

## Estructura

```
evidencias/
  INDICE-EVIDENCIAS.csv     qué evidencia se espera, de quién, y su estado (se actualiza a mano)
  crudas/                   capturas SIN sanitizar. NO se sube al repo (está en .gitignore)
  sanitizadas/              copias revisadas, sin ID de cuenta ni ARN. Esto es lo que va al repo/informe
  csv/                      resultados-<origen>-<fecha>.csv de tests_fase3.sh (Leonardo)
  texto/                    salidas de scripts: evidencias-<host>-<fecha>.txt, hardening-antes/despues-<host>.txt,
                            dhcp-<host>-<fecha>.txt, salidas de probar-ldap.sh y probar-web.sh
```

## Nombres

- Capturas: `E<casilla>_<descripcion>.png`, p. ej. `E5.4_chronyc_tracking.png`. Sin espacios ni tildes.
- Si hay varias tomas de la misma casilla: sufijo `_2`, `_3`. No se sobrescribe una captura vieja.
- Texto: se conserva el nombre que genera cada script (lleva host y fecha).

## Qué ocultar antes de mover algo de `crudas/` a `sanitizadas/` (E9.4)

1. ID de cuenta de AWS (12 dígitos): aparece arriba a la derecha en la consola, en ARN, en `OwnerId` y en la página de Facturación.
2. ARN completos y nombres de usuario IAM.
3. Claves, tokens, contraseñas, hashes de contraseña, contenido de `.pem`.
4. Correos personales y datos reales de personas (los usuarios LDAP son ficticios; si aparece uno real, tapar).
5. IP públicas de la NAT/IGW si el grupo decide no publicarlas (consultar con Anthony).

Cómo tapar: rectángulo opaco (no desenfoque; el desenfoque a veces se puede revertir). Después de tapar, guardar como PNG **nuevo** en `sanitizadas/` y abrirlo para comprobar que el dato ya no se ve.

## Revisión automática (solo texto)

```bash
bash fase3/roberto/herramientas/revisar-secretos.sh            # revisa todo fase3/
bash fase3/roberto/herramientas/revisar-secretos.sh fase3/roberto/evidencias/texto
```

No lee imágenes ni el DOCX. Las capturas y el informe se revisan a ojo.

## Reglas de honestidad (de las reglas del equipo)

- Cada evidencia se marca **propuesto / configurado / probado** en `INDICE-EVIDENCIAS.csv`. Una configuración visible no demuestra que funciona.
- Si una prueba falla, se guarda la evidencia del fallo y se explica en el informe. No se reemplaza por una captura de un intento posterior sin anotarlo.
- Nada que solo corrió en la VM local del Lab 5 se presenta como hecho en AWS.
