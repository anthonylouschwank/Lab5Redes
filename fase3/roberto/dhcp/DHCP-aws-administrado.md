# DHCP en la Fase 3 (E5.1–E5.2) — Hospital Privado Castillejos

Estado de esta sección: **propuesto**. Nada de esto está probado en AWS hasta que Majo encienda una EC2 y se corra `dhcp-capturar.sh` (ver "Cómo se prueba").

## 1. Decisión: DHCP administrado por AWS

El PDF de Fase 3 pide implementar DHCP "para manejar la administración de direcciones IP". En una VPC, el servicio DHCP lo da AWS: las instancias obtienen su dirección y su configuración de red de los servidores DHCP de Amazon, y lo que esos servidores entregan se controla con un **DHCP option set** asociado a la VPC. La documentación de AWS lo dice así: "You can specify the network configurations that are provided by Amazon DHCP servers by using DHCP option sets" y las instancias "can communicate with Amazon DHCP servers as needed to retrieve their IP address lease or other network configuration information".

El grupo ya había asumido (reparto, §1) que AWS no permite correr un DHCP propio en la VPC para repartir direcciones. **Hay que buscar y citar la frase exacta de la documentación de AWS que lo respalda antes de afirmarlo en el informe**; en las páginas consultadas hoy no apareció una afirmación explícita. Hasta tenerla, en el informe se redacta como "AWS administra la asignación de direcciones; el servicio no se reemplaza con un servidor propio", sin atribuir la frase a AWS.

El PDF también dice que se puede "optar por utilizar dichos servicios" de la plataforma. Esta es esa opción: se usa el servicio de la plataforma y no se instala `isc-dhcp-server` ni similar.

## 2. Qué entrega el option set (según la documentación consultada)

| Opción | Valor en el option set por defecto | Fuente |
|---|---|---|
| `domain-name-servers` | `AmazonProvidedDNS` | Documentación de DHCP option sets de AWS |
| `domain-name` | Depende de la región (no confirmado en la página consultada) | **Leer en la consola** |
| `ntp-servers` | No se define; las instancias usan Amazon Time Sync Service | Documentación de DHCP option sets de AWS |
| Duración del lease | La documentación indica 140 s de lease preferido por defecto para IPv6 y que la renovación ocurre a la mitad del lease | Documentación de AWS |

Lo que tiene **esta** VPC (Hospital-Castillejos-VPC) no se sabe todavía: hay que leerlo (sección 3) y anotarlo en el informe tal cual aparezca, no el valor "por defecto" de la documentación.

## 3. Lectura del option set actual (E5.1) — solo lectura

Quien tenga la consola (Majo) o la AWS CLI configurada:

1. Consola: VPC → *Your VPCs* → seleccionar `Hospital-Castillejos-VPC` → pestaña *Details*: anotar el valor de **DHCP option set**. Luego VPC → *DHCP option sets* → abrir ese ID y capturar la pantalla (valores de *Domain name*, *Domain name servers*, *NTP servers*, *Lease time*). Nombre sugerido: `E5.1_dhcp_option_set.png`.
2. CLI (equivalente, solo lectura):
   ```bash
   aws ec2 describe-vpcs --filters Name=tag:Name,Values=Hospital-Castillejos-VPC \
       --query 'Vpcs[0].DhcpOptionsId' --output text --region us-east-1
   aws ec2 describe-dhcp-options --dhcp-options-ids <ID_DEL_COMANDO_ANTERIOR> --region us-east-1
   ```
   Antes de compartir la salida: ocultar el ID de cuenta (campo `OwnerId`) y cualquier ARN.

Si el grupo decide **un option set propio** (dominio interno o servidor NTP interno 10.0.0.46): un option set no se edita; se crea uno nuevo y se asocia a la VPC. Eso lo hace Majo, y el cambio solo lo ven las instancias cuando renuevan su lease o se reinician. Capturar el estado antes y después. Si se pone `10.0.0.46` como `ntp-servers`, avisar a Leonardo: sus scripts de chrony ya apuntan a 10.0.0.46 y no deben duplicarse fuentes sin querer.

## 4. Cómo se prueba (E5.2)

En **cada EC2 que se encienda** (TI, Servidores, la de Médicos, la de Visitantes, la NAT):

```bash
bash dhcp-capturar.sh evidencias-dhcp/
```

Deja `dhcp-<host>-<fecha>.txt` con IP asignada, ruta por defecto, DNS y dominio recibidos, el lease de systemd-networkd y los metadatos de la subred. Con eso se muestra, para cada instancia, que la configuración vino del DHCP de AWS y no de archivos escritos a mano (sección 7 del archivo muestra netplan: debe decir `dhcp4: true` o equivalente; si dice una IP fija, hay que explicarlo, no ocultarlo).

Criterio de aprobado para E5.2 (propuesto): la IP de la instancia está dentro de la subred esperada (Servidores 10.0.0.32/27, TI 10.0.0.112/28, etc.), la ruta por defecto apunta al router de la VPC y aparece el DNS del option set.

## 5. Texto sugerido para el informe (completar los `[…]` con lo observado)

> **DHCP.** El direccionamiento de las instancias lo administra el servicio DHCP de AWS mediante el DHCP option set asociado a la VPC [ID del option set, sin ID de cuenta]. El option set entrega [dominio], [servidores DNS] y [servidores NTP o "ninguno; las instancias usan Amazon Time Sync Service"]. Se verificó en [N] instancias (Imagen [X]) que la dirección, la puerta de enlace y el DNS provienen de ese servicio: [resumen de lo observado en `dhcp-<host>.txt`]. No se instaló un servidor DHCP propio: el servicio de la plataforma cubre el requisito de administración de direcciones y fue una de las opciones que contempla el enunciado. **Limitación:** [p. ej., "no se probó la renovación del lease" si no se hizo].

## 6. Documentación consultada (para la sección del informe)

- [DHCP option sets in Amazon VPC](https://docs.aws.amazon.com/vpc/latest/userguide/VPC_DHCP_Options.html) — AWS, consultada el 28/10/2026.
- [DHCP option set concepts](https://docs.aws.amazon.com/vpc/latest/userguide/DHCPOptionSetConcepts.html) — AWS (leída vía un espejo de la documentación, `docs.aws.eu`, el 28/10/2026; **volver a abrir la original y verificar los valores antes de citarlos**).
