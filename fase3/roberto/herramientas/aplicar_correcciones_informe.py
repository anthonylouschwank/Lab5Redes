#!/usr/bin/env python3
"""aplicar_correcciones_informe.py — Corrige el informe de Fase 2 y le agrega los capítulos de Fase 3.

Trabaja sobre un DOCX ya DESCOMPRIMIDO (unzip doc.docx -d paquete/). No modifica el original.

  python3 -I aplicar_correcciones_informe.py PAQUETE [--capturas DIR_TAPADAS] [--fecha 29/10/2026]

Hace, en este orden:
  1. Portada: "Fase 2" -> "Fase 3" y fecha.
  2. Imagen 12: el texto dice que SG-Servidores NO tenía reglas de salida (lo que muestra la captura).
  3. Imágenes 13 y 16-27: pie y descripción reescritos según lo que muestra cada captura
     (en Fase 2 estaban desfasados respecto a su imagen).
  4. Si se da --capturas: reemplaza las imágenes de word/media por las copias tapadas (mismo nombre).
  5. Agrega los capítulos de Fase 3 antes del final del documento (idempotente: si ya están, no repite).

Cada afirmación de Fase 3 lleva su estado: PROPUESTO / CONFIGURADO / PROBADO LOCALMENTE / PROBADO EN AWS.
Los marcadores [PENDIENTE: ...] son datos que solo existen cuando Majo corre los scripts en AWS: hay que
reemplazarlos o borrarlos antes de entregar (el script final avisa cuántos quedan).
"""
import argparse
import re
import shutil
import sys
from pathlib import Path
from xml.sax.saxutils import escape

# ---------------------------------------------------------------- textos corregidos de Fase 2
IMG12_PIE = "Imagen 12. Verificación de las reglas salientes de Servidores."
IMG12_TXT = ("Se revisaron las reglas de salida de Hospital-SG-Servidores. La captura muestra que el grupo no tenía "
             "reglas de salida (la lista de Outbound rules aparece vacía), de modo que no se había autorizado ninguna "
             "conexión iniciada desde Servidores hacia otros destinos. Como los grupos de seguridad son con estado, las "
             "respuestas al tráfico entrante permitido (ICMP y SSH desde TI) sí pueden salir; lo que no está permitido es "
             "que Servidores inicie conexiones, por ejemplo TCP 80/443 hacia Internet para instalar paquetes. En la "
             "Fase 3 se propone agregar esa salida (TCP 80 y 443); está propuesta y no se ha probado en AWS.")

# número de imagen -> (pie, descripción) según el contenido real de cada captura
CORRECCIONES = {
    13: ("Imagen 13. Reglas de entrada de Hospital-SG-TI.",
         "Se revisaron las reglas de entrada de Hospital-SG-TI. La captura muestra una regla TCP/22 (SSH) cuyo origen "
         "es el propio grupo de seguridad, que permite la conexión desde EC2 Instance Connect Endpoint sin abrir el "
         "puerto a 0.0.0.0/0."),
    16: ("Imagen 16. Reglas de salida del grupo de seguridad de la infraestructura original.",
         "Se verificaron las reglas de salida de HospitalCastillejosITGroup, el grupo usado para administrar la "
         "instancia de la VPC predeterminada. La captura muestra una regla de todo el tráfico hacia 0.0.0.0/0. "
         "Este grupo es independiente de la infraestructura hospitalaria."),
    17: ("Imagen 17. Reglas de entrada de Hospital-SG-TI al crearse.",
         "La captura muestra Hospital-SG-TI sin reglas de entrada (\"No security group rules found\"). Así se creó el "
         "grupo: sin conexiones entrantes hasta preparar el acceso administrativo privado."),
    18: ("Imagen 18. Reglas de salida de Hospital-SG-TI.",
         "Se comprobó que Hospital-SG-TI tiene una regla de salida de todo el tráfico hacia 0.0.0.0/0, que permite a "
         "la instancia de TI iniciar conexiones hacia los servidores internos."),
    19: ("Imagen 19. Creación de EC2 Instance Connect Endpoint.",
         "Se creó el endpoint Hospital-EC2-Connect dentro de la subred Hospital-TI. La captura lo muestra en estado "
         "Pending. Este recurso permite conexiones SSH administrativas hacia instancias privadas sin asignarles "
         "direcciones IPv4 públicas."),
    20: ("Imagen 20. Reglas de entrada de Hospital-NACL-Visitantes.",
         "Se editaron las reglas de entrada de la lista de control de acceso Hospital-NACL-Visitantes: la regla 100 "
         "deniega todo el tráfico desde 10.0.0.0/24 y la regla 110 lo deniega desde 10.8.0.0/24, rango previsto "
         "para la VPN."),
    21: ("Imagen 21. Asociación de Hospital-NACL-Visitantes con la subred de visitantes.",
         "La captura muestra que Hospital-NACL-Visitantes se asoció exclusivamente a la subred Hospital-Visitantes, "
         "con cuatro reglas de entrada y cuatro de salida. Es una capa adicional a nivel de subred."),
    22: ("Imagen 22. Reglas de entrada finales de Hospital-NACL-Visitantes.",
         "Las reglas de entrada quedaron así: 100 y 110 deniegan 10.0.0.0/24 y 10.8.0.0/24, la 120 permite el resto "
         "(0.0.0.0/0) y la regla por defecto (*) deniega. Las ACL se evalúan por número de regla, por lo que los "
         "bloqueos se aplican antes de la regla 120."),
    23: ("Imagen 23. Reglas de salida de Hospital-NACL-Visitantes.",
         "Las reglas de salida son equivalentes: 100 y 110 deniegan el tráfico hacia 10.0.0.0/24 y 10.8.0.0/24, la "
         "120 permite el resto y la regla por defecto (*) deniega. Impiden que Visitantes inicie conexiones hacia la "
         "red interna y hacia el rango de la VPN."),
    24: ("Imagen 24. Configuración de la instancia EC2 de TI.",
         "Se configuraron los parámetros de Hospital-EC2-TI: Ubuntu Server 24.04, t3.micro, 8 GiB, subred "
         "Hospital-TI, sin dirección IPv4 pública y con el grupo Hospital-SG-TI."),
    25: ("Imagen 25. Regla SSH de Hospital-SG-TI para administración privada.",
         "La captura muestra la regla de entrada TCP/22 de Hospital-SG-TI con el propio grupo como origen. Con ella "
         "se estableció la conexión SSH desde EC2 Instance Connect Endpoint sin habilitar 0.0.0.0/0."),
    26: ("Imagen 26. Conexión exitosa a la instancia Ubuntu de TI.",
         "Se estableció una sesión mediante EC2 Instance Connect Endpoint hacia Hospital-EC2-TI (IP privada "
         "10.0.0.117) con el usuario ubuntu. La terminal confirma Ubuntu Server 24.04 LTS y que el comando whoami "
         "responde ubuntu."),
    27: ("Imagen 27. Configuración de la instancia EC2 de Servidores.",
         "Se configuró Hospital-EC2-Servidores con Ubuntu Server 24.04, t3.micro, 8 GiB, subred Hospital-Servidores "
         "(10.0.0.32/27), grupo Hospital-SG-Servidores y sin dirección IPv4 pública, para mantener la comunicación "
         "dentro de la VPC."),
}
CORRECCIONES[28] = ("Imagen 28. Instancias EC2 de TI y Servidores en ejecución.",
    "La consola muestra Hospital-EC2-TI y Hospital-EC2-Servidores en estado Running (t3.micro, us-east-1a); "
    "Servidores, con IP privada 10.0.0.46, aún iniciaba sus verificaciones de estado. Se desplegó sin IPv4 pública.")
# Las Imágenes 29 a 35 ya coincidían con su contenido (se comprobó una por una).
# La Imagen 28 (y siguientes) las toma del DOCX completo: su pie y descripción no se tocan aquí.

# ---------------------------------------------------------------- capítulos de Fase 3
MARCA = "FASE3-CAPITULOS"   # comentario que evita duplicar al re-ejecutar

IMG = "img"; H1 = "h1"; H2 = "h2"; P = "p"; T = "tabla"; PB = "salto"
FASE3 = [
    (PB, None),
    (H1, "Fase 3. Servicios, endurecimiento y pruebas"),
    (P, "Esta fase agrega a la red de la Fase 2 los servicios internos del hospital (directorio LDAP, intranet web, "
        "sincronización de hora), la salida controlada a Internet, el endurecimiento de las instancias y una matriz "
        "de pruebas. Cada afirmación lleva su estado: propuesto (diseñado, no aplicado), configurado (aplicado, sin "
        "prueba que lo demuestre), probado localmente (en una VM local equivalente a una EC2) o probado en AWS "
        "(con evidencia de una EC2). Una configuración visible en la consola no demuestra por sí sola que funcione."),
    (H2, "Estado por componente"),
    (T, [["Componente", "Responsable", "Estado"],
         ["Directorio OpenLDAP y usuarios ficticios", "Sebastián", "Probado localmente; en AWS [PENDIENTE: salida de probar-ldap.sh en la EC2]"],
         ["Intranet Apache con autenticación LDAP (HTTP 80)", "Isabella", "[PENDIENTE: confirmar estado con la sección de Isabella]"],
         ["Salida a Internet por NAT", "Leonardo / Majo", "Propuesto; probado solo en VM local [PENDIENTE: evidencia en AWS]"],
         ["NTP interno (chrony)", "Leonardo", "Propuesto; probado en VM local [PENDIENTE: evidencia en AWS]"],
         ["Endurecimiento (ufw por rol, SSH sin contraseña)", "Leonardo", "Propuesto; probado solo en VM local"],
         ["DHCP", "Roberto", "Administrado por AWS; sin script propio [PENDIENTE: captura del option set]"],
         ["Matriz de pruebas (35 pruebas)", "Leonardo / Roberto", "Matriz propuesta; resultados [PENDIENTE: CSV de cada EC2]"]]),
    (H2, "Flujos permitidos y denegados"),
    (P, "La intranet se publica por HTTP en el puerto 80, no por HTTPS 443, por lo que el tráfico no va cifrado. "
        "Los orígenes autorizados de la intranet los define la directiva Require ip de Apache [PENDIENTE: confirmar "
        "rangos con Isabella y Anthony]."),
    (T, [["Origen", "Destino", "Protocolo / puerto", "Decisión", "Estado"],
         ["TI (10.0.0.112/28)", "Servidores (10.0.0.46)", "ICMP; SSH TCP 22", "Permitir", "Probado en Fase 2: ping (Imagen 29) y SSH con clave (Imagen 33)"],
         ["TI", "Servidores", "HTTP TCP 80 (intranet)", "Permitir", "Propuesto"],
         ["Servidores y TI", "Servidores (LDAP)", "TCP 389", "Permitir; Apache en la misma EC2 usa 127.0.0.1", "Propuesto"],
         ["Todas las subredes internas", "Servidores (NTP)", "UDP 123", "Permitir, excepto Visitantes", "Propuesto"],
         ["Servidores", "TI", "SSH TCP 22", "Denegar", "Probado en Fase 2 (Imagen 34: ACCESO BLOQUEADO); se repite en la matriz"],
         ["Visitantes (10.0.0.64/27)", "Red interna 10.0.0.0/24 y 10.8.0.0/24", "Todo", "Denegar", "Configurado (NACL, Imágenes 20 a 23)"],
         ["Servidores", "Internet por NAT", "TCP 80 y 443 de salida", "Permitir", "Propuesto"],
         ["Internet", "Subredes internas", "Conexiones iniciadas desde fuera", "Denegar", "Propuesto"]]),
    (H2, "Usuarios y directorio LDAP"),
    (P, "El directorio usa la base dc=hospital,dc=redes,dc=test, con las unidades People y Groups y los grupos medicos, "
        "ti y laboratorio. Los usuarios son ficticios, dos por grupo: medico01 y medico02, ti01 y ti02, laboratorio01 "
        "y laboratorio02. La cuenta de servicio svc-intranet la usa Apache para consultar el directorio. Las contraseñas "
        "se generan en la instancia en el momento de la instalación y no se incluyen en el repositorio ni en este informe."),
    (P, "La instalación es idempotente y no usa reconfiguración destructiva. Estado: probado localmente; en la VM se "
        "verificó TCP 389 en escucha, la carga de las siete entradas, un bind válido de ti01 y el rechazo de una "
        "contraseña incorrecta con el error 49 (Invalid credentials), como muestran las Imágenes 36 y 37 (VM local, no AWS). "
        "No está probado en AWS hasta que se ejecuten los scripts en la EC2 de Servidores [PENDIENTE: salida y capturas "
        "de probar-ldap.sh en la EC2]."),
    (IMG, 0), (IMG, 1),
    (H2, "Salida a Internet por NAT"),
    (P, "Las instancias privadas no tienen IP pública; para instalar paquetes necesitan una salida controlada. El "
        "guion de Leonardo convierte una EC2 de la DMZ en NAT instance: reenvío de IP, MASQUERADE de la VPC y una "
        "cadena de FORWARD con política DROP, de modo que nada iniciado desde Internet entra. [PENDIENTE: el grupo debe "
        "confirmar qué NAT se usó en AWS, NAT instance o NAT Gateway, porque cada una tiene costo y configuración "
        "distintos; el texto de esta sección debe describir solo la que se desplegó.] Estado: probado en VM local; "
        "sin prueba en AWS. Una sola NAT es un punto único de falla y consume créditos mientras está encendida; debe "
        "eliminarse o detenerse al terminar la demostración."),
    (H2, "DHCP"),
    (P, "La VPC usa el servicio DHCP administrado por AWS mediante un conjunto de opciones DHCP (DHCP option set). "
        "Los conjuntos de opciones no se editan: para cambiarlos se crea uno nuevo y se asocia a la VPC. Se mantuvo el "
        "administrado por AWS porque ofrece a las instancias su dirección privada, la puerta de enlace y el DNS de la VPC "
        "(10.0.0.2) sin servidores adicionales que mantener. Estado: configurado por defecto; no se escribió un servidor "
        "DHCP propio. [PENDIENTE: captura del option set de la VPC y la salida de dhcp-capturar.sh en cada EC2.]"),
    (H2, "Sincronización de hora (NTP)"),
    (P, "El servidor de Servidores (10.0.0.46) sincroniza con Amazon Time Sync (169.254.169.123) y ofrece la hora a la "
        "VPC con chrony; los clientes usan 10.0.0.46. Visitantes no puede alcanzar ese servidor por las reglas de su NACL "
        "y usa Amazon Time Sync directamente, que es una dirección link-local. Que las NACL no filtren ese tráfico ni el "
        "DNS de la VPC está pendiente de confirmar en la documentación de AWS. Estado: probado en VM local con un NTP "
        "público en lugar de Amazon Time Sync; sin prueba en AWS."),
    (H2, "Endurecimiento de las instancias"),
    (P, "El script de endurecimiento aplica ufw con deny incoming y solo los puertos de cada rol, SSH sin contraseña y sin "
        "root, y registra el inventario de puertos antes y después con la justificación de cada puerto que queda. Incluye "
        "un seguro anti-lockout con retroceso automático si no se confirma el acceso por EC2 Instance Connect Endpoint. "
        "Estado: probado solo en VM local. Limitación: ufw permite ICMP echo por defecto, así que el bloqueo de ping desde "
        "Visitantes depende de su NACL y no del endurecimiento."),
    (H2, "Matriz de pruebas"),
    (P, "La matriz tiene 35 pruebas (TCP, HTTP, LDAP, NTP, ICMP e Internet), ejecutadas desde cada EC2 de origen con "
        "tests_fase3.sh, que distingue timeout (bloqueado por SG, NACL o firewall) de connection refused (el paquete "
        "llegó, pero no hay servicio). Los resultados se consolidan con consolidar_matriz.py. Una prueba sin ejecutar "
        "figura como PENDIENTE y no cuenta como éxito. [PENDIENTE: insertar aquí la tabla matriz-consolidada.md con los "
        "CSV reales de AWS.]"),
    (H2, "Limitaciones"),
    (P, "Nada de lo marcado como local se ha demostrado en AWS. Quedan sin probar Amazon Time Sync real, el source/dest "
        "check de la NAT, y las rutas, SG y NACL de la Fase 3. Un puerto bloqueado no demuestra aislamiento completo: "
        "la matriz prueba ICMP y varios puertos por destino, no todos. La VPC es solo IPv4. Las pruebas EXT de acceso "
        "desde Internet requieren ejecutarse manualmente desde fuera de la VPC."),
    (H2, "Documentación consultada"),
    (P, "[PENDIENTE: verificar y citar la documentación de AWS sobre DHCP option sets, filtrado de SG y NACL (DNS, DHCP, "
        "Time Sync) y NAT, con enlace y fecha de consulta.]"),
]

# ---------------------------------------------------------------- utilidades XML
RPR = ('<w:rPr><w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman" w:eastAsia="Times New Roman" '
       'w:cs="Times New Roman"/>{fmt}<w:sz w:val="{sz}"/><w:szCs w:val="{sz}"/><w:lang w:val="es-ES"/></w:rPr>')


def run(texto, sz=24, negrita=False, cursiva=False):
    fmt = ("<w:b/><w:bCs/>" if negrita else "") + ("<w:i/><w:iCs/>" if cursiva else "")
    return f'<w:r>{RPR.format(fmt=fmt, sz=sz)}<w:t xml:space="preserve">{escape(texto)}</w:t></w:r>'


def parrafo(texto, sz=24, negrita=False, cursiva=False, jc="both", antes=240, despues=240):
    return (f'<w:p><w:pPr><w:spacing w:before="{antes}" w:after="{despues}"/><w:jc w:val="{jc}"/></w:pPr>'
            f'{run(texto, sz, negrita, cursiva)}</w:p>')


def tabla(filas):
    n = len(filas[0])
    ancho = 9026 // n
    b = ''.join(f'<w:{l} w:val="single" w:sz="4" w:space="0" w:color="808080"/>' for l in ("top", "left", "bottom", "right", "insideH", "insideV"))
    out = [f'<w:tbl><w:tblPr><w:tblW w:w="9026" w:type="dxa"/><w:tblBorders>{b}</w:tblBorders>'
           f'<w:tblLayout w:type="fixed"/><w:tblCellMar><w:left w:w="80" w:type="dxa"/><w:right w:w="80" w:type="dxa"/></w:tblCellMar></w:tblPr>'
           f'<w:tblGrid>{"".join(f"<w:gridCol w:w=\"{ancho}\"/>" for _ in range(n))}</w:tblGrid>']
    for i, fila in enumerate(filas):
        sombra = '<w:shd w:val="clear" w:color="auto" w:fill="D9E2F3"/>' if i == 0 else ''
        celdas = ''.join(
            f'<w:tc><w:tcPr><w:tcW w:w="{ancho}" w:type="dxa"/>{sombra}</w:tcPr>'
            f'<w:p><w:pPr><w:spacing w:before="40" w:after="40"/></w:pPr>{run(c, 20, negrita=(i == 0))}</w:p></w:tc>'
            for c in fila)
        out.append(f'<w:tr>{"<w:trPr><w:cantSplit/><w:tblHeader/></w:trPr>" if i == 0 else "<w:trPr><w:cantSplit/></w:trPr>"}{celdas}</w:tr>')
    out.append('</w:tbl><w:p/>')
    return ''.join(out)


LDAP_PIES = ["Imagen 36. Consulta de usuarios y grupos LDAP, probada en la VM local (no en AWS).",
             "Imagen 37. Bind válido de ti01, bind inválido (error 49) y resultado PASS, en la VM local (no en AWS)."]
LDAP_IMGS = []   # [(rId, ancho_px, alto_px)] se llena en main()


def dibujo(rid, w, h, n):
    cx = 4800600; cy = int(cx * h / w)
    return (f'<w:p><w:pPr><w:keepNext/><w:jc w:val="center"/></w:pPr><w:r><w:drawing><wp:inline distT="0" distB="0" distL="0" distR="0" '
            f'xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing"><wp:extent cx="{cx}" cy="{cy}"/>'
            f'<wp:docPr id="{9000 + n}" name="Captura LDAP {n}"/><a:graphic xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">'
            f'<a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture"><pic:pic xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">'
            f'<pic:nvPicPr><pic:cNvPr id="{9000 + n}" name="ldap{n}"/><pic:cNvPicPr/></pic:nvPicPr><pic:blipFill>'
            f'<a:blip r:embed="{rid}" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill>'
            f'<pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="{cx}" cy="{cy}"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr>'
            f'</pic:pic></a:graphicData></a:graphic></wp:inline></w:drawing></w:r></w:p>')


def bloque_fase3():
    partes = [f'<!--{MARCA}-->']
    for tipo, c in FASE3:
        if tipo == PB:
            partes.append('<w:p><w:r><w:br w:type="page"/></w:r></w:p>')
        elif tipo == H1:
            partes.append(parrafo(c, 32, negrita=True, jc="left", antes=220, despues=100))
        elif tipo == H2:
            partes.append(parrafo(c, 28, negrita=True, cursiva=True, jc="left", antes=140, despues=100))
        elif tipo == P:
            partes.append(parrafo(c))
        elif tipo == T:
            partes.append(tabla(c))
        elif tipo == IMG:
            if c < len(LDAP_IMGS):
                rid, w, h = LDAP_IMGS[c]
                partes.append(dibujo(rid, w, h, c))
                partes.append(parrafo(LDAP_PIES[c], jc="center", antes=60, despues=200))
    return ''.join(partes)


def texto_de(p):
    return ''.join(re.findall(r'<w:t[^>]*>([^<]*)</w:t>', p))


def poner_texto_parrafo(p, nuevo):
    """Deja el formato del primer run y reemplaza todo el texto del párrafo (conserva dibujos)."""
    ts = list(re.finditer(r'<w:t(?: [^>]*)?>[^<]*</w:t>', p))
    if not ts:
        return p
    for k, m in reversed(list(enumerate(ts))):
        nuevo_t = f'<w:t xml:space="preserve">{escape(nuevo)}</w:t>' if k == 0 else '<w:t></w:t>'
        p = p[:m.start()] + nuevo_t + p[m.end():]
    return p


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("paquete", type=Path)
    ap.add_argument("--capturas", type=Path)
    ap.add_argument("--fecha", default="29/10/2026")
    ap.add_argument("--ldap-capturas", nargs="*", type=Path, default=[],
                    help="capturas de Sebastián (probar-ldap.sh en VM local) para insertar en el capítulo de LDAP")
    ap.add_argument("--quitar-rels-rotas", action="store_true",
                    help="borra relaciones a imágenes que no existen en el paquete (DOCX truncado). Con el DOCX completo no hace falta.")
    a = ap.parse_args()

    doc = a.paquete / "word" / "document.xml"
    x = doc.read_text(encoding="utf8")
    parrafos = re.findall(r'<w:p[ >].*?</w:p>', x, flags=re.S)
    informe = []

    def buscar(prefijo):
        for i, p in enumerate(parrafos):
            if texto_de(p).startswith(prefijo):
                return i
        return None

    # 1. portada
    i = buscar("Proyecto 2 Fase")
    if i is None:
        informe.append("AVISO: no encontré la línea de portada 'Proyecto 2 Fase'")
    else:
        nuevo = parrafos[i]
        ts = list(re.finditer(r'<w:t(?: [^>]*)?>[^<]*</w:t>', nuevo))
        if len(ts) >= 2 and texto_de(nuevo).rstrip().endswith("2"):
            m = ts[-1]
            nuevo = nuevo[:m.start()] + '<w:t>3</w:t>' + nuevo[m.end():]
        parrafos_nuevos = {i: nuevo}
        informe.append("portada: Fase 2 -> Fase 3")
    cambios = {parrafos[i]: parrafos_nuevos[i]} if i is not None else {}
    j = buscar("15/10/2026")
    if j is not None:
        cambios[parrafos[j]] = poner_texto_parrafo(parrafos[j], a.fecha)
        informe.append(f"fecha de portada -> {a.fecha}")

    # 2. Imagen 12 (descripción = párrafo siguiente al pie)
    k = buscar("Imagen 12.")
    if k is None:
        informe.append("AVISO: no encontré el pie de la Imagen 12")
    else:
        cambios[parrafos[k]] = poner_texto_parrafo(parrafos[k], IMG12_PIE)
        cambios[parrafos[k + 1]] = poner_texto_parrafo(parrafos[k + 1], IMG12_TXT)
        informe.append("Imagen 12: texto corregido (SG-Servidores sin reglas de salida)")

    # 3. imágenes 13, 16-27
    for n, (pie, desc) in CORRECCIONES.items():
        k = buscar(f"Imagen {n}.")
        if k is None:
            informe.append(f"AVISO: no encontré el pie de la Imagen {n}")
            continue
        cambios[parrafos[k]] = poner_texto_parrafo(parrafos[k], pie)
        sig = parrafos[k + 1]
        if texto_de(sig).startswith("Imagen ") or not texto_de(sig):
            informe.append(f"AVISO: después del pie de la Imagen {n} no hay descripción; no la toqué")
        else:
            cambios[sig] = poner_texto_parrafo(sig, desc)
        informe.append(f"Imagen {n}: pie y descripción corregidos")

    for viejo, nuevo in cambios.items():
        if x.count(viejo) != 1:
            sys.exit("ERROR: un párrafo no es único; no se escribe nada.")
        x = x.replace(viejo, nuevo)

    # capturas de LDAP: se copian al paquete y se registran en las relaciones
    if a.ldap_capturas and MARCA not in x:
        from PIL import Image
        media = a.paquete / "media" if (a.paquete / "media").is_dir() else a.paquete / "word" / "media"
        prefijo = "/media/" if media.parent == a.paquete else "media/"
        rels = a.paquete / "word" / "_rels" / "document.xml.rels"
        r = rels.read_text(encoding="utf8")
        for n, f in enumerate(a.ldap_capturas):
            im = Image.open(f)
            ext = "png" if im.format == "PNG" else "jpg"
            nombre = f"ldap_local_{n + 1}.{ext}"
            im.convert("RGB").save(media / nombre)
            rid = f"rIdLdapLocal{n + 1}"
            r = r.replace("</Relationships>", f'<Relationship Id="{rid}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="{prefijo}{nombre}"/></Relationships>')
            LDAP_IMGS.append((rid, im.width, im.height))
        rels.write_text(r, encoding="utf8")
        informe.append(f"capturas de LDAP agregadas: {len(LDAP_IMGS)}")

    # 5. capítulos de Fase 3
    if MARCA in x:
        informe.append("capítulos de Fase 3: ya estaban; no se repiten")
    else:
        cut = x.rfind("<w:sectPr")
        x = x[:cut] + bloque_fase3() + x[cut:]
        informe.append("capítulos de Fase 3 agregados")
    doc.write_text(x, encoding="utf8")

    # 4. imágenes tapadas
    if a.capturas:
        n_img = 0
        carpetas = [a.paquete / "media", a.paquete / "word" / "media"]   # según el Target de las relaciones
        for f in sorted(a.capturas.iterdir()):
            for c in carpetas:
                if (c / f.name).exists():
                    shutil.copyfile(f, c / f.name)
                    n_img += 1
        informe.append(f"imágenes tapadas copiadas: {n_img}")

    if a.quitar_rels_rotas:
        rels = a.paquete / "word" / "_rels" / "document.xml.rels"
        r = rels.read_text(encoding="utf8")
        quitadas = 0
        for m in list(re.finditer(r'<Relationship [^>]*?Target="(/?media/[^"]+)"[^>]*?/>', r)):
            t = m.group(1).lstrip("/")
            if not ((a.paquete / t).exists() or (a.paquete / "word" / t).exists()):
                rid = re.search(r'Id="([^"]+)"', m.group(0)).group(1)
                r = r.replace(m.group(0), "")
                quitadas += 1
                # el dibujo que la usaba se cambia por un aviso visible (no se deja un hueco silencioso)
                x = re.sub(r'<w:drawing>(?:(?!</w:drawing>).)*?r:embed="' + re.escape(rid) + r'".*?</w:drawing>',
                           f'<w:t xml:space="preserve">[IMAGEN FALTANTE: el DOCX recibido estaba truncado ({t})]</w:t>',
                           x, flags=re.S)
        rels.write_text(r, encoding="utf8")
        doc.write_text(x, encoding="utf8")
        informe.append(f"relaciones rotas quitadas: {quitadas}")

    pend = len(re.findall(r'\[PENDIENTE', x))
    informe.append(f"marcadores [PENDIENTE] que aún hay que resolver antes de entregar: {pend}")
    print("\n".join(informe))


if __name__ == "__main__":
    main()
