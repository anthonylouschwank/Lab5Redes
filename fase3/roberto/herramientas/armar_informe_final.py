#!/usr/bin/env python3
"""armar_informe_final.py — Arma el informe final (Fases 1, 2 y 3) a partir del DOCX del grupo ya DESCOMPRIMIDO.

  python3 -I armar_informe_final.py PAQUETE --capturas DIR_TAPADAS --evidencias DIR_EVIDENCIAS \
          --diagrama diagrama.png [--ldap-capturas a.jpg b.jpg] [--fecha 29/10/2026]

1. Fase 2: corrige la Imagen 12 y los pies/descripciones desfasados (aplicar_correcciones_informe.py).
2. Portada: fecha.
3. Quita el borrador de Fase 3 (desde el título "Fase 3" hasta el final) y escribe la Fase 3 definitiva con el texto del
   grupo (fase3/INFORME-FASE3.md), pies de imagen según el contenido real de cada captura y la matriz de pruebas
   tomada de los CSV de AWS (Anexo A).
4. Reemplaza las imágenes por las copias tapadas y borra las imágenes que ya nadie usa.
No toca el DOCX original. Después: (cd PAQUETE && zip -Xqr ../salida.docx '[Content_Types].xml' _rels docProps word media)
"""
import argparse
import csv
import importlib.util
import re
import shutil
import sys
from pathlib import Path
from xml.sax.saxutils import escape

from PIL import Image

AQUI = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("fix2", AQUI / "aplicar_correcciones_informe.py")
fix2 = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fix2)
run, parrafo, texto_de, poner_texto_parrafo = fix2.run, fix2.parrafo, fix2.texto_de, fix2.poner_texto_parrafo

# ------------------------------------------------------------------ bloques de XML
def tabla(filas, anchos=None, sz=18):
    n = len(filas[0])
    anchos = anchos or [9026 // n] * n
    b = ''.join(f'<w:{l} w:val="single" w:sz="4" w:space="0" w:color="808080"/>' for l in ("top", "left", "bottom", "right", "insideH", "insideV"))
    grid = ''.join(f'<w:gridCol w:w="{a}"/>' for a in anchos)
    out = [f'<w:tbl><w:tblPr><w:tblW w:w="{sum(anchos)}" w:type="dxa"/><w:tblBorders>{b}</w:tblBorders><w:tblLayout w:type="fixed"/>'
           f'<w:tblCellMar><w:left w:w="70" w:type="dxa"/><w:right w:w="70" w:type="dxa"/></w:tblCellMar></w:tblPr><w:tblGrid>{grid}</w:tblGrid>']
    for i, fila in enumerate(filas):
        sombra = '<w:shd w:val="clear" w:color="auto" w:fill="D9E2F3"/>' if i == 0 else ''
        celdas = ''.join(
            f'<w:tc><w:tcPr><w:tcW w:w="{anchos[k]}" w:type="dxa"/>{sombra}</w:tcPr>'
            f'<w:p><w:pPr><w:spacing w:before="30" w:after="30"/></w:pPr>{run(str(c), sz, negrita=(i == 0))}</w:p></w:tc>'
            for k, c in enumerate(fila))
        trpr = '<w:trPr><w:cantSplit/>' + ('<w:tblHeader/>' if i == 0 else '') + '</w:trPr>'
        out.append(f'<w:tr>{trpr}{celdas}</w:tr>')
    out.append('</w:tbl><w:p><w:pPr><w:spacing w:before="0" w:after="120"/></w:pPr></w:p>')
    return ''.join(out)


def figura(rid, w, h, n, ancho_in=6.0, alto_max_in=5.6):
    cx = int(ancho_in * 914400)
    cy = int(cx * h / w)
    if cy > alto_max_in * 914400:
        cy = int(alto_max_in * 914400)
        cx = int(cy * w / h)
    return (f'<w:p><w:pPr><w:keepNext/><w:spacing w:before="160" w:after="40"/><w:jc w:val="center"/></w:pPr><w:r><w:drawing>'
            f'<wp:inline distT="0" distB="0" distL="0" distR="0" xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing">'
            f'<wp:extent cx="{cx}" cy="{cy}"/><wp:docPr id="{9100 + n}" name="Figura {n}"/>'
            f'<a:graphic xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">'
            f'<pic:pic xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture"><pic:nvPicPr><pic:cNvPr id="{9100 + n}" name="fig{n}"/><pic:cNvPicPr/></pic:nvPicPr>'
            f'<pic:blipFill><a:blip r:embed="{rid}" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill>'
            f'<pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="{cx}" cy="{cy}"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr>'
            f'</pic:pic></a:graphicData></a:graphic></wp:inline></w:drawing></w:r></w:p>')


def H1(t): return parrafo(t, 32, negrita=True, jc="left", antes=300, despues=120)
def H2(t): return parrafo(t, 28, negrita=True, cursiva=True, jc="left", antes=200, despues=100)
def H3(t): return parrafo(t, 24, negrita=True, jc="left", antes=160, despues=80)
def P(t): return parrafo(t, 24, antes=80, despues=120)
def VI(t): return re.sub(r'(<w:spacing[^>]*/>)', r'\1<w:ind w:left="500" w:hanging="260"/>', parrafo("•  " + t, 24, jc="left", antes=20, despues=40), count=1)
def PIE(t): return parrafo(t, 22, jc="center", antes=40, despues=200)

# ------------------------------------------------------------------ contenido de Fase 3
# ("fig", media, pie, [fuente]) · ("img-ext", clave, pie)
def contenido(m):
    """m: dict con datos leídos de los CSV."""
    c = []
    a = c.append
    a(("h2", "1. Introducción y objetivo"))
    a(("p", "En la Fase 2 se construyó en AWS la segmentación de la red del Hospital Privado Castillejos: VPC 10.0.0.0/24, cinco "
            "subredes, tablas de rutas, dos Security Groups, una NACL para Visitantes y acceso administrativo privado mediante "
            "EC2 Instance Connect Endpoint. En la Fase 3 se implementaron sobre esa infraestructura los servicios de administración "
            "de red (DHCP, NTP y LDAP), una intranet con autenticación centralizada y los controles de seguridad del caso: firewall, "
            "ACL, NAT, aislamiento de Visitantes, acceso unidireccional desde TI y hardening."))
    a(("p", "Siguiendo las observaciones del enunciado, se usaron servicios administrados de AWS donde existen (DHCP Options Set, NAT "
            "Gateway, Amazon Time Sync, Security Groups y NACL). LDAP, la intranet y el servidor NTP interno se consolidaron en una "
            "sola instancia para reducir costos. En todo el capítulo se distingue lo diseñado, lo implementado y lo probado, y se "
            "indica dónde se ejecutó cada prueba."))
    a(("h2", "2. Alcance: diseñado, implementado y probado"))
    a(("tabla", [["Componente", "Fase 1 (diseñado)", "Fase 3 (implementado)", "Probado en AWS"],
                 ["DHCP", "DHCP Options Set con hospital.internal", "DHCP de AWS con el Options Set por defecto (ec2.internal, AmazonProvidedDNS)", "Sí, en las 4 EC2"],
                 ["NTP", "chrony interno sincronizado con Amazon Time Sync", "chrony en 10.0.0.46 (upstream 169.254.169.123) que sirve a Médicos, Servidores, DMZ y TI. Visitantes usa Time Sync directamente", "Sí"],
                 ["LDAP", "LLDAP / OpenLDAP", "OpenLDAP (slapd) en 10.0.0.46, base dc=hospital,dc=redes,dc=test", "Sí, en la propia instancia (bind desde TI no probado)"],
                 ["Servidor web interno", "Flask + nginx con HTTPS", "Apache 2.4 con autenticación LDAP por grupo (/intranet/, /intranet/ti/) en HTTP/80", "Sí; pruebas de autenticación desde la propia instancia"],
                 ["Firewall", "Un SG por rol + ufw", "SG-TI, SG-Servidores, SG-Medicos, SG-Visitantes + ufw en cada EC2", "Sí"],
                 ["ACL", "NACL de Visitantes", "Hospital-NACL-Visitantes con una excepción SSH para TI", "Sí"],
                 ["NAT", "NAT instance (Fase 1) / NAT Gateway (alternativa)", "NAT Gateway Hospital-NAT en la DMZ (10.0.0.101) + Elastic IP", "Sí"],
                 ["SSH", "Solo desde TI/VPN", "Solo a través de EC2 Instance Connect Endpoint (subred TI); clave pública temporal (60 s)", "Sí"],
                 ["Hardening", "ufw, SSH con llaves, sin servicios innecesarios", "hardening.sh por rol en las 4 EC2", "Sí"],
                 ["DNS interno, VPN, web pública en la DMZ, RDS, aplicación clínica", "Diseñados", "No implementados (fuera del alcance de esta fase; ver §10)", "—"]],
           [1500, 2000, 3626, 1900]))
    a(("h2", "3. Infraestructura AWS utilizada"))
    a(("tabla", [["Recurso", "Identificación", "Subred / IP", "Función"],
                 ["Hospital-EC2-Servidores", "t3.micro, Ubuntu 24.04", "Servidores · 10.0.0.46", "OpenLDAP, Apache (intranet), chrony servidor"],
                 ["Hospital-EC2-TI", "t3.micro, Ubuntu 24.04", "TI · 10.0.0.117", "Administración y pruebas"],
                 ["Hospital-EC2-Medicos-Prueba", "t3.micro, Ubuntu 24.04 (nueva)", "Médicos · 10.0.0.28", "Equipo de prueba de Médicos"],
                 ["Hospital-EC2-Visitantes-Prueba", "t3.micro, Ubuntu 24.04 (nueva)", "Visitantes · 10.0.0.69", "Equipo de prueba de Visitantes"],
                 ["Hospital-NAT", "NAT Gateway público + Elastic IP", "DMZ · 10.0.0.101", "Salida a Internet de las subredes privadas"],
                 ["Hospital-IGW", "Internet Gateway", "—", "Salida de la DMZ (Hospital-RT-Publica)"],
                 ["Hospital-EC2-Connect", "EC2 Instance Connect Endpoint", "TI · 10.0.0.122", "SSH administrativo sin IP pública"]],
           [2300, 2400, 1900, 2426]))
    a(("p", "Ninguna EC2 tiene dirección IPv4 pública. La única dirección pública es la Elastic IP del NAT Gateway, que no acepta "
            "conexiones iniciadas desde Internet."))
    a(("vi", "Hospital-RT-Privada (Médicos, Servidores, Visitantes, TI): 10.0.0.0/24 → local, 0.0.0.0/0 → Hospital-NAT."))
    a(("vi", "Hospital-RT-Publica (DMZ): 10.0.0.0/24 → local, 0.0.0.0/0 → Hospital-IGW."))
    a(("fig-ext", "diagrama", "Imagen {n}. Diagrama de la red al 29/10/2026. Verde: probado en AWS; azul: configurado; flechas punteadas: tráfico bloqueado y comprobado."))
    a(("fig", "image38", "Imagen {n}. VPC Hospital-Castillejos-VPC (10.0.0.0/24) y su conjunto de opciones DHCP."))
    a(("fig", "image3d", "Imagen {n}. Internet Gateway Hospital-IGW asociado a la VPC del hospital."))
    a(("fig", "image3e", "Imagen {n}. Ruta 0.0.0.0/0 → Internet Gateway en Hospital-RT-Publica (DMZ)."))
    a(("fig", "image3f", "Imagen {n}. Creación del NAT Gateway Hospital-NAT en la subred DMZ (estado Pending al momento de la captura)."))
    a(("fig", "image4d", "Imagen {n}. Hospital-NAT en estado Available, subred Hospital-DMZ, IP privada 10.0.0.101 (IP pública oculta)."))
    a(("fig", "image40", "Imagen {n}. Ruta 0.0.0.0/0 → Hospital-NAT en Hospital-RT-Privada."))
    a(("fig", "image4c", "Imagen {n}. Las cuatro EC2 de la Fase 3 en ejecución, sin dirección IPv4 pública (SRV1 detenida pertenece al proyecto anterior)."))
    a(("h2", "4. Administración de la red"))
    a(("h3", "4.1 DHCP"))
    a(("p", "AWS asigna automáticamente la configuración IP de cada instancia a partir del DHCP Options Set de la VPC "
            "(dopt-0d28300b9723e6567: domain-name = ec2.internal, domain-name-servers = AmazonProvidedDNS). AWS administra la asignación "
            "de direcciones de la VPC y el enunciado permite usar los servicios de la plataforma, así que no se instaló un servidor DHCP "
            "propio. Ubuntu registra la concesión en /run/systemd/netif/leases/:"))
    a(("tabla", [["Equipo", "Dirección/máscara", "Gateway", "DNS", "Dominio"],
                 ["Servidores", "10.0.0.46/27", "10.0.0.33", "10.0.0.2", "ec2.internal"],
                 ["TI", "10.0.0.117/28", "10.0.0.113", "10.0.0.2", "ec2.internal"],
                 ["Médicos", "10.0.0.28/27", "10.0.0.1", "10.0.0.2", "ec2.internal"],
                 ["Visitantes", "10.0.0.69/27", "10.0.0.65", "10.0.0.2", "ec2.internal"]], [1800, 2000, 1700, 1500, 2026]))
    a(("p", "Los gateways coinciden con los calculados en el subnetting de la Fase 1 (primera dirección utilizable de cada subred)."))
    a(("fig", "image39", "Imagen {n}. DHCP option set de la VPC: domain-name ec2.internal y AmazonProvidedDNS."))
    a(("fig", "image3a", "Imagen {n}. Hospital-EC2-TI: dirección 10.0.0.117/28, gateway 10.0.0.113, DNS 10.0.0.2 y dominio ec2.internal, tomados de la concesión DHCP de Ubuntu."))
    a(("h3", "4.2 NTP"))
    a(("vi", "Servidor interno (10.0.0.46): chrony sincroniza con Amazon Time Sync (169.254.169.123, estrato 3, por lo que el servidor queda en estrato 4). chrony-servidor.sh agrega allow solo para Médicos, Servidores, DMZ y TI, más local stratum 10 como respaldo."))
    a(("vi", "Clientes TI y Médicos: chrony-cliente.sh los apunta a 10.0.0.46. chronyc sources muestra ^* 10.0.0.46 como fuente seleccionada."))
    a(("vi", "Visitantes: para no abrir ningún flujo hacia otras subredes, usa directamente Amazon Time Sync (^* 169.254.169.123). Que los SG y las NACL no filtren ese servicio es lo que indica la documentación de AWS consultada (ver §11); la prueba VIS-13 lo confirma en la práctica."))
    a(("fig", "image3b", "Imagen {n}. Hospital-EC2-TI sincronizada con Amazon Time Sync (Reference ID 169.254.169.123, Leap status Normal). Captura previa a apuntar TI al servidor interno."))
    a(("fig", "image3c", "Imagen {n}. Configuración de chrony en TI: fuente 169.254.169.123 en /etc/chrony/conf.d/00-cpc.conf."))
    a(("h3", "4.3 LDAP"))
    a(("p", "OpenLDAP (slapd) en 10.0.0.46, con base dc=hospital,dc=redes,dc=test, ou=People y ou=Groups. Grupos (posixGroup): medicos (5001), ti (5002) y laboratorio (5003). Usuarios ficticios: medico01, medico02, ti01, ti02, laboratorio01 y laboratorio02, más la cuenta de servicio svc-intranet. Las contraseñas se generaron en la propia instancia y no forman parte de este informe."))
    a(("p", "slapd escucha en todas las interfaces (SLAPD_SERVICES=\"ldap:/// ldapi:///\"). TCP/389 solo se admite desde Servidores y TI (SG-Servidores y ufw). Antes de ese cambio escuchaba solo en 127.0.0.1, como muestra la primera captura."))
    a(("fig", "image42", "Imagen {n}. Servidores: slapd escuchando en 127.0.0.1:389 y creación de las unidades People y Groups (estado inicial)."))
    a(("fig", "image46", "Imagen {n}. instalar-ldap.sh en Hospital-EC2-Servidores: base verificada, grupos medicos, ti y laboratorio, y OpenLDAP activo sin reconfiguración destructiva."))
    a(("fig", "image48", "Imagen {n}. cargar-usuarios.sh en Hospital-EC2-Servidores: 7 entradas creadas y consulta de los seis usuarios ficticios."))
    a(("p", "Pruebas de probar-ldap.sh (consulta de usuarios y grupos, autenticación válida y rechazo de una contraseña incorrecta con el código 49): 4/4 PASS. Las capturas siguientes son de la ejecución en la VM local de Sebastián (equivalente a una EC2, no es AWS); la ejecución en la EC2 la reportó Majo y consta en el índice de evidencias."))
    a(("ldap", 0, "Imagen {n}. probar-ldap.sh en la VM local: usuarios y grupos (no es AWS)."))
    a(("ldap", 1, "Imagen {n}. probar-ldap.sh en la VM local: bind válido, bind inválido (error 49) y PASS (no es AWS)."))
    a(("h2", "5. Servidor web interno (intranet)"))
    a(("p", "Apache 2.4.58 en 10.0.0.46 (módulos ldap, authnz_ldap, include), VirtualHost hospital-intranet.conf, TCP/80:"))
    a(("vi", "/: portal informativo sin autenticación (200)."))
    a(("vi", "/intranet/: autenticación Basic contra LDAP; requiere pertenecer a medicos, ti o laboratorio."))
    a(("vi", "/intranet/ti/: solo el grupo ti."))
    a(("vi", "Restricción por origen en tres capas: SG-Servidores admite 80 desde Médicos, Servidores, DMZ y TI; ufw repite esa lista; Apache aplica Require ip con las mismas redes. Visitantes no aparece en ninguna."))
    a(("vi", "El bind de Apache a LDAP usa svc-intranet. Su contraseña está en un archivo incluido, privado de root (/etc/apache2/hospital-intranet/, modo 700)."))
    a(("p", "La intranet se publica por HTTP en el puerto 80, no por HTTPS 443: las credenciales de la autenticación Basic viajan sin cifrar dentro de la VPC (ver §10). Permisos por usuario:"))
    a(("tabla", [["Identidad", "Grupo", "/intranet/", "/intranet/ti/", "Estado de la prueba"],
                 ["ti01, ti02", "ti", "Permitido", "Permitido", "ti01 probado (W-03, W-06)"],
                 ["medico01, medico02", "medicos", "Permitido", "Denegado", "medico01 probado (W-07)"],
                 ["laboratorio01, laboratorio02", "laboratorio", "Permitido", "Denegado", "Por pertenencia al grupo; no se probó individualmente"],
                 ["Sin credenciales o contraseña incorrecta", "—", "Denegado", "Denegado", "Probado (W-02, W-04, W-05)"]],
           [2300, 1300, 1300, 1400, 2726]))
    a(("p", "Pruebas probar-web.sh (W-01…W-07) ejecutadas en Hospital-EC2-Servidores contra http://127.0.0.1 el 29/10/2026: portal 200; intranet sin credenciales 401; ti01 válido 200; contraseña incorrecta 401; usuario inexistente 401; panel TI con ti01 200; panel TI con medico01 401. 7/7 PASS. Desde otras subredes se comprobó el acceso HTTP al puerto 80 (200 en la intranet pública y 401 sin credenciales en /intranet/, ver Anexo A), pero no se repitió la autenticación con credenciales desde otra EC2."))
    a(("h2", "6. Seguridad"))
    a(("h3", "6.1 Flujos permitidos y bloqueados"))
    a(("tabla", [["Origen", "Destino", "Protocolo / puerto", "Política"],
                 ["Endpoint Hospital-EC2-Connect", "TI, Servidores, Médicos y Visitantes", "TCP/22 (SSH)", "Permitir administración; SG-TI y los demás SG aceptan 22 desde SG-TI"],
                 ["TI", "Médicos, Servidores y Visitantes", "TCP/22; ICMP hacia Servidores", "Permitir administración y comprobar conectividad"],
                 ["Médicos, Servidores y Visitantes", "TI", "Conexiones nuevas, cualquier protocolo", "Bloquear (SG-TI solo acepta 22 desde sí mismo)"],
                 ["TI, Médicos, DMZ y Servidores", "Intranet en 10.0.0.46", "TCP/80 (HTTP)", "Permitir; exigir autenticación en /intranet/"],
                 ["Servidores y TI", "LDAP en 10.0.0.46", "TCP/389", "Permitir; Apache usa 127.0.0.1"],
                 ["Visitantes", "Las otras cuatro subredes", "Conexiones nuevas, cualquier protocolo", "Bloquear (NACL regla 100 y SG)"],
                 ["Visitantes", "Internet mediante NAT", "TCP/80 y TCP/443", "Permitir navegación"],
                 ["TI y Servidores", "Internet mediante NAT", "TCP/80 y TCP/443", "Permitir descarga de paquetes"],
                 ["Instancias del proyecto", "DNS de AWS (10.0.0.2) y Amazon Time Sync (169.254.169.123)", "UDP/TCP 53 · UDP/123", "Servicios de AWS no filtrados por SG ni NACL (ver §11)"],
                 ["Internet", "Instancias privadas e intranet", "Conexiones nuevas", "Bloquear"],
                 ["Destino de una conexión autorizada", "Equipo que la inició", "Tráfico de respuesta", "Permitir retorno (SG con estado; en la NACL, a mano)"]],
           [2100, 2400, 2000, 2526]))
    a(("h3", "6.2 Security Groups (con estado)"))
    a(("tabla", [["SG", "Entrada", "Salida"],
                 ["Hospital-SG-TI", "TCP 22 desde SG-TI (endpoint)", "Todo"],
                 ["Hospital-SG-Servidores", "TCP 22 e ICMP desde SG-TI · TCP 80 desde 10.0.0.0/27, .32/27, .96/28, .112/28 · TCP 389 desde .32/27 y .112/28 · UDP 123 desde .0/27, .32/27, .96/28, .112/28", "TCP 80 y 443 → 0.0.0.0/0"],
                 ["Hospital-SG-Medicos (nuevo)", "TCP 22 desde SG-TI", "Todo"],
                 ["Hospital-SG-Visitantes (nuevo)", "TCP 22 desde SG-TI", "Todo"]], [2300, 4726, 2000]))
    a(("p", "\"TI llega a todas, nadie llega a TI\": todos los SG aceptan SSH desde SG-TI, y SG-TI solo acepta SSH desde sí mismo (el endpoint). Las respuestas a lo que TI inicia vuelven porque los SG son con estado."))
    a(("fig", "image2d", "Imagen {n}. Estado anterior: Hospital-SG-Servidores sin reglas de salida (\"No security group rules found\")."))
    a(("fig", "image41", "Imagen {n}. Hospital-SG-Servidores con reglas de salida TCP 80 (HTTP) y TCP 443 (HTTPS) hacia 0.0.0.0/0, agregadas en la Fase 3."))
    a(("fig", "image4a", "Imagen {n}. Reglas de entrada de Hospital-SG-Servidores: HTTP 80, LDAP 389, UDP 123, SSH 22 e ICMP."))
    a(("fig", "image49", "Imagen {n}. Reglas de entrada de Hospital-SG-Medicos: SSH 22 solo desde Hospital-SG-TI."))
    a(("fig", "image4f", "Imagen {n}. Reglas de entrada de Hospital-SG-Visitantes: SSH 22 solo desde Hospital-SG-TI."))
    a(("h3", "6.3 NACL de Visitantes (sin estado)"))
    a(("tabla", [["Regla", "Entrada", "Salida"],
                 ["90", "ALLOW TCP 22 desde 10.0.0.112/28 (TI y endpoint)", "ALLOW TCP 1024-65535 → 10.0.0.112/28 (respuestas SSH)"],
                 ["100", "DENY todo desde 10.0.0.0/24", "DENY todo → 10.0.0.0/24"],
                 ["110", "DENY todo desde 10.8.0.0/24 (pool VPN previsto)", "DENY todo → 10.8.0.0/24"],
                 ["120", "ALLOW todo desde 0.0.0.0/0", "ALLOW todo → 0.0.0.0/0"],
                 ["*", "DENY", "DENY"]], [1000, 4000, 4026]))
    a(("p", "El tráfico de Visitantes a Internet lleva destino público, así que la regla 100 no lo afecta y la 120 lo permite. El NAT Gateway es solo el siguiente salto de la ruta. La salida 90 solo permite enviar paquetes a puertos altos de TI, y SG-TI los descarta."))
    a(("fig", "image4e", "Imagen {n}. Hospital-NACL-Visitantes: cinco reglas de salida (90 Allow hacia TI, 100 y 110 Deny, 120 Allow y * Deny)."))
    a(("h3", "6.4 NAT"))
    a(("p", "Se usa el NAT Gateway administrado en lugar de la NAT instance de la Fase 1 (nat-instance.sh queda documentado como alternativa y no se desplegó). Ventajas: no requiere administrar ni endurecer una EC2, no hay que desactivar el source/dest check y no admite conexiones entrantes. Su costo es mayor (§8)."))
    a(("h3", "6.5 SSH"))
    a(("p", "Todas las instancias se administran únicamente por EC2 Instance Connect Endpoint (subred TI, 10.0.0.122, Preserve client IP = No):"))
    a(("vi", "La clave pública se autoriza por 60 s con ec2-instance-connect send-ssh-public-key."))
    a(("vi", "No hay SSH desde Internet ni IP pública."))
    a(("vi", "La CLI de administración dejó de usar la cuenta root: se creó el usuario IAM fase3-admin, sin access keys."))
    a(("fig", "image34", "Imagen {n}. EC2 Instance Connect Endpoint Hospital-EC2-Connect en estado Available."))
    a(("fig", "image35", "Imagen {n}. El endpoint usa el grupo de seguridad Hospital-SG-TI."))
    a(("fig", "image36", "Imagen {n}. El endpoint está en la subred Hospital-TI (10.0.0.122)."))
    a(("h3", "6.6 Hardening"))
    a(("p", "Se ejecutó hardening.sh por rol (servidores, cliente para Médicos y Visitantes, y ti al final), con inventario antes y después y un rollback automático de 300 s que solo se canceló tras confirmar acceso por una segunda sesión:"))
    a(("vi", "ufw: deny incoming, allow outgoing, deny routed, y solo los puertos del rol. En Servidores: 22 desde TI; 80 desde Médicos, Servidores, DMZ y TI; 389 desde Servidores y TI; 123/udp desde las mismas cuatro redes. En el resto: 22 desde TI."))
    a(("vi", "SSH (sshd -T): PasswordAuthentication no, KbdInteractiveAuthentication no, PermitRootLogin no, X11Forwarding no."))
    a(("vi", "Servicios: se deshabilitó ModemManager, innecesario en una EC2."))
    a(("vi", "Puertos en escucha después del hardening: 22 (sshd), 53 solo local (systemd-resolved), 68 (cliente DHCP), 323 solo local (chronyc); en Servidores además 80, 389 y 123. Cada puerto queda justificado y filtrado por ufw y SG."))
    a(("vi", "LDAP, Apache y NTP siguieron funcionando después del cambio (salida de verificación en fase3/evidencias/E7.5_*)."))
    a(("h2", "7. Pruebas integradas"))
    a(("p", "Se ejecutó tests_fase3.sh en cada EC2 de origen, más pruebas complementarias y pruebas desde Internet (laptop del equipo). Criterio: un flujo permitido debe conectar; uno bloqueado debe terminar en timeout (un connection refused contaría como fallo, porque indicaría que la red no lo bloqueó). El detalle de cada prueba está en el Anexo A."))
    a(("tabla", [["Requisito del enunciado", "Pruebas", "Resultado"],
                 ["SSH a las instancias", "TI-01, TI-06, TI-07, TI-11 + acceso por endpoint a las 4 EC2", "PASS"],
                 ["Visitantes con Internet", "VIS-11 (TCP 443 a 1.1.1.1), VIS-12 (HTTPS example.com 200)", "PASS"],
                 ["Visitantes sin acceso a otras subredes", "VIS-01…05, VIS-07…09, VIS-14, VIS-15 (SSH, HTTP, LDAP, ICMP)", "PASS (timeout)"],
                 ["TI → todas las subredes", "TI-01…07, TI-11", "PASS"],
                 ["Ninguna subred → TI", "SRV-01, MED-01, MED-02, VIS-01, VIS-07", "PASS (timeout)"],
                 ["Intranet desde todas menos Visitantes", "TI-02, TI-10, SRV-02, MED-03, MED-08, MED-09 · VIS-02, VIS-14 bloqueadas", "PASS"],
                 ["Intranet no accesible desde Internet", "EXT: TCP 22/80/443/389 a la EIP del NAT = False; ninguna EC2 con IPv4 pública", "PASS"],
                 ["NAT", "TI-09, MED-10, VIS-11, VIS-12", "PASS"],
                 ["NTP", "TI-04, MED-05 (^* 10.0.0.46), SRV-03, VIS-13", "PASS"],
                 ["LDAP solo desde Servidores y TI", "TI-03 permitido · MED-04, VIS-04, VIS-15 bloqueados", "PASS"],
                 ["Hardening", "MED-06 (SSH Médicos → Servidores bloqueado), inventarios antes/después", "PASS"]],
           [2800, 4626, 1600]))
    a(("p", f"Total: {m['pass_total']} PASS, {m['fail_total']} FAIL ({m['aws']} pruebas en AWS desde 4 orígenes y {m['ext']} desde Internet) y 6 omitidas (TI-08, VIS-06, VIS-10, DMZ-01…03). "
            "Las omitidas se deben a que la DMZ no tiene EC2 propia: en esta fase solo aloja el NAT Gateway, que es un servicio administrado. "
            "Los CSV y las salidas completas están en fase3/evidencias/ (índice: INDICE-EVIDENCIAS.md). Los CSV no incluyen el identificador de cada prueba; "
            "el Anexo A las identifica por origen, destino y protocolo."))
    a(("h2", "8. Costos"))
    a(("vi", "Cost Explorer (consulta del 29/10/2026 ~05:25 UTC): uso del mes US$7.75, cubierto por créditos promocionales (neto US$0). Cost Explorer tiene un retraso de hasta 24 h, por lo que el NAT Gateway y las EC2 lanzadas el 29/10 pueden no estar reflejados por completo."))
    a(("vi", "La página Billing and Cost Management mostró después US$8.48 de costo a la fecha, con la cuenta sin cobro por créditos (Imagen siguiente)."))
    a(("vi", "Tarifas de lista us-east-1: EC2 t3.micro US$0.0104/h (4 instancias durante la demo ≈ US$0.04/h); NAT Gateway US$0.045/h + US$0.045/GB; IPv4 pública US$0.005/h; EBS gp3 US$0.08/GB-mes. Instance Connect Endpoint, Time Sync, DHCP Options, SG y NACL no tienen costo."))
    a(("vi", "El NAT Gateway y su EIP siguen cobrándose aunque las EC2 estén detenidas (≈ US$36.50/mes si se dejan 24/7). Después de la evaluación, el grupo decidirá si se eliminan."))
    a(("fig", "image4b", "Imagen {n}. Billing and Cost Management: costo del mes a la fecha US$8.48; la cuenta no recibe cobro mientras haya créditos."))
    a(("h2", "9. Correcciones a fases anteriores"))
    a(("vi", "Fase 2, Imagen 12: el texto decía que SG-Servidores conservaba la salida predeterminada. La captura muestra \"No security group rules found\": no tenía reglas de salida. Se corrigió el texto y en la Fase 3 se agregaron TCP 80/443 de salida."))
    a(("vi", "Fase 2, Imágenes 13 y 16 a 28: los pies de imagen y sus descripciones estaban desfasados respecto a cada captura; se reescribieron según el contenido real."))
    a(("vi", "IP de servicios: la Fase 1 preveía 10.0.0.36 y 10.0.0.37 para el servidor interno y los servicios de red; ambos se consolidaron en 10.0.0.46. El NAT está en 10.0.0.101."))
    a(("vi", "La intranet usa TCP/80, no TCP/443, y los usuarios de prueba son los del directorio LDAP (ti01, medico01, laboratorio01…)."))
    a(("h2", "10. Limitaciones y trabajo pendiente"))
    a(("vi", "Sin cifrado en la intranet: usa HTTP con autenticación Basic, así que las credenciales viajan sin cifrar dentro de la VPC. El diseño de Fase 1 prevé HTTPS con certificado interno o autofirmado. Queda para la fase final."))
    a(("vi", "DMZ sin EC2: la web pública, la VPN WireGuard/Client VPN, RDS y la aplicación clínica no se implementaron. Por eso no hay pruebas desde la DMZ."))
    a(("vi", "Sin DNS interno: se usa AmazonProvidedDNS y /etc/hosts. El dominio ec2.internal difiere del hospital.internal de la Fase 1."))
    a(("vi", "Pruebas LDAP y web: la autenticación se probó en la propia instancia (probar-ldap.sh, probar-web.sh contra 127.0.0.1). Desde TI se probó la conectividad TCP/389, no un bind con credenciales. Las pruebas LDAP de la matriz usan solo TCP (faltaba ldap-utils)."))
    a(("vi", "Un puerto bloqueado no demuestra aislamiento completo: la matriz prueba ICMP y varios puertos por destino, no todos."))
    a(("vi", "Una sola zona de disponibilidad (us-east-1a): sin alta disponibilidad. El NAT Gateway único es un punto único de falla."))
    a(("vi", "Las pruebas desde Internet se hicieron desde una laptop del equipo contra la IP del NAT; no prueban todos los puertos ni todos los orígenes."))
    a(("h2", "11. Documentación consultada"))
    for t in ["AWS. Control subnet traffic with network access control lists. Amazon VPC User Guide. https://docs.aws.amazon.com/vpc/latest/userguide/vpc-network-acls.html",
              "AWS. Control traffic to your AWS resources using security groups. Amazon VPC User Guide. https://docs.aws.amazon.com/vpc/latest/userguide/vpc-security-groups.html",
              "AWS. NAT gateways. Amazon VPC User Guide. https://docs.aws.amazon.com/vpc/latest/userguide/vpc-nat-gateway.html",
              "AWS. DHCP option sets in Amazon VPC. https://docs.aws.amazon.com/vpc/latest/userguide/VPC_DHCP_Options.html",
              "AWS. Set the time for your Linux instance (Amazon Time Sync Service). Amazon EC2 User Guide. https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/set-time.html",
              "AWS. Connect to your instances using EC2 Instance Connect Endpoint. https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/connect-with-ec2-instance-connect-endpoint.html",
              "AWS. Amazon VPC pricing (NAT Gateway, IPv4 pública). https://aws.amazon.com/vpc/pricing/",
              "Apache Software Foundation. mod_authnz_ldap. https://httpd.apache.org/docs/2.4/mod/mod_authnz_ldap.html",
              "OpenLDAP Project. OpenLDAP Software 2.6 Administrator's Guide. https://www.openldap.org/doc/admin26/",
              "chrony project. chrony.conf(5) manual. https://chrony-project.org/doc/4.5/chrony.conf.html",
              "Ubuntu. Uncomplicated Firewall (ufw). https://help.ubuntu.com/community/UFW",
              "Material reutilizado del Laboratorio 5 del curso (LDAP, Apache y pruebas) y scripts del equipo (fase3/sebastian, isabella, leonardo, anthony)."]:
        a(("vi", t))
    a(("h2", "Anexo A. Resultados de la matriz de pruebas (CSV de AWS, 29/10/2026)"))
    a(("p", "Cada fila es una línea de los resultados-<origen>-2026-10-29.csv generados por tests_fase3.sh en la EC2 de origen, y de resultados-internet-EXT.csv para las pruebas desde la laptop. Fechas y horas en UTC (EXT: hora local de la laptop)."))
    a(("matriz", None))
    a(("h2", "Anexo B. Archivos de configuración entregados"))
    for t in ["fase3/config-final/<equipo>/: chrony (fase3-servidor.conf / fase3-cliente.conf), apache-hospital-intranet.conf, slapd-default-SLAPD_SERVICES.txt, sshd-01-fase3-hardening.conf, ufw-<host>.txt.",
              "fase3/evidencias/*.json: SG, NACL, rutas, NAT, DHCP Options e instancias, antes y después.",
              "fase3/CAMBIOS-Y-REVERSION.md: cada cambio realizado con su comando de reversión.",
              "Scripts: fase3/sebastian/, fase3/isabella/, fase3/leonardo/ (con fase3.env de AWS)."]:
        a(("vi", t))
    return c


def leer_matriz(evid: Path):
    filas, total_pass, total_fail, aws = [], 0, 0, 0
    for orig in ("ti", "servidores", "medicos", "visitantes"):
        f = evid / "aws" / orig / f"resultados-{orig}-2026-10-29.csv"
        with f.open(encoding="utf-8-sig", newline="") as fh:
            for r in csv.DictReader(fh):
                filas.append([r["origen"], r["destino"], r["protocolo_puerto"], r["esperado"], r["obtenido"], r["resultado"]])
                aws += 1
    ext = 0
    with (evid / "resultados-internet-EXT.csv").open(encoding="utf-8-sig", newline="") as fh:
        for line in fh:
            if line.startswith("20"):
                p = next(csv.reader([line]))
                filas.append(["Internet (laptop)", p[2], p[3], p[4], p[5], p[6]])
                ext += 1
    for r in filas:
        if r[5] == "PASS":
            total_pass += 1
        else:
            total_fail += 1
    return filas, dict(pass_total=total_pass, fail_total=total_fail, aws=aws, ext=ext)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("paquete", type=Path)
    ap.add_argument("--capturas", type=Path, required=True)
    ap.add_argument("--evidencias", type=Path, required=True)
    ap.add_argument("--diagrama", type=Path, required=True)
    ap.add_argument("--ldap-capturas", nargs="*", type=Path, default=[])
    ap.add_argument("--fecha", default="29/10/2026")
    a = ap.parse_args()

    pq = a.paquete
    media = pq / "media" if (pq / "media").is_dir() else pq / "word" / "media"
    prefijo = "/media/" if media.parent == pq else "media/"
    doc = pq / "word" / "document.xml"
    rels_p = pq / "word" / "_rels" / "document.xml.rels"
    x = doc.read_text(encoding="utf8")
    rels = rels_p.read_text(encoding="utf8")
    log = []

    # ---- imágenes tapadas
    n = 0
    for f in sorted(a.capturas.iterdir()):
        if (media / f.name).exists():
            shutil.copyfile(f, media / f.name)
            n += 1
    log.append(f"imágenes tapadas copiadas: {n}")

    # ---- corrección de la Fase 2
    parrafos = re.findall(r'<w:p[ >].*?</w:p>', x, flags=re.S)

    def buscar(prefijo_txt, desde=0):
        for i in range(desde, len(parrafos)):
            if texto_de(parrafos[i]).startswith(prefijo_txt):
                return i
        return None

    cambios = {}
    j = buscar("01/10/2026")
    if j is not None:
        cambios[parrafos[j]] = poner_texto_parrafo(parrafos[j], a.fecha)
        log.append(f"fecha de portada -> {a.fecha}")
    k = buscar("Imagen 12.")
    cambios[parrafos[k]] = poner_texto_parrafo(parrafos[k], fix2.IMG12_PIE)
    cambios[parrafos[k + 1]] = poner_texto_parrafo(parrafos[k + 1], fix2.IMG12_TXT)
    log.append("Imagen 12 corregida")
    for num, (pie, desc) in fix2.CORRECCIONES.items():
        k = buscar(f"Imagen {num}.")
        if k is None:
            log.append(f"AVISO: no encontré la Imagen {num}")
            continue
        cambios[parrafos[k]] = poner_texto_parrafo(parrafos[k], pie)
        sig = parrafos[k + 1]
        if texto_de(sig) and not texto_de(sig).startswith("Imagen "):
            cambios[sig] = poner_texto_parrafo(sig, desc)
        log.append(f"Imagen {num} corregida")
    for viejo, nuevo in cambios.items():
        if x.count(viejo) != 1:
            sys.exit("ERROR: párrafo no único; no se escribe nada")
        x = x.replace(viejo, nuevo)

    # ---- quitar el borrador de Fase 3
    parrafos = re.findall(r'<w:p[ >].*?</w:p>', x, flags=re.S)
    i3 = [i for i, p in enumerate(parrafos) if texto_de(p) == "Fase 3"]
    if len(i3) != 1:
        sys.exit("ERROR: no encontré (o hay varios) el título 'Fase 3'")
    p3 = parrafos[i3[0]]
    pos = x.index(p3) + len(p3)
    fin = x.rfind("<w:sectPr")
    borrado = x[pos:fin]
    x = x[:pos] + "@@FASE3@@" + x[fin:]
    log.append(f"borrador de Fase 3 quitado ({borrado.count('<w:drawing>')} imágenes, {borrado.count('<w:tbl>')} tablas)")

    # ---- Fase 3 definitiva
    filas_m, resumen = leer_matriz(a.evidencias)
    # ids de relación por nombre de medio
    rid_de = {}
    for m_ in re.finditer(r'<Relationship [^>]*?/>', rels):
        t = re.search(r'Target="(/?media/([^"]+))"', m_.group(0))
        i = re.search(r'Id="([^"]+)"', m_.group(0))
        if t and i:
            rid_de[t.group(2).rsplit(".", 1)[0]] = (i.group(1), t.group(2))
    nuevo_rels = []

    def registrar(nombre_archivo, origen: Path, clave):
        destino = media / nombre_archivo
        shutil.copyfile(origen, destino)
        rid = f"rIdF3{clave}"
        nuevo_rels.append(f'<Relationship Id="{rid}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="{prefijo}{nombre_archivo}"/>')
        return rid

    rid_diag = registrar("fase3_diagrama.png", a.diagrama, "Diagrama")
    rid_ldap = []
    for i, f in enumerate(a.ldap_capturas):
        im = Image.open(f)
        nombre = f"fase3_ldap_local_{i + 1}.png"
        im.convert("RGB").save(media / nombre)
        rid = f"rIdF3Ldap{i + 1}"
        nuevo_rels.append(f'<Relationship Id="{rid}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="{prefijo}{nombre}"/>')
        rid_ldap.append((rid, im.width, im.height))

    cuerpo, num_img, usados = [], 35, set()
    for item in contenido(resumen):
        t = item[0]
        if t == "h1": cuerpo.append(H1(item[1]))
        elif t == "h2": cuerpo.append(H2(item[1]))
        elif t == "h3": cuerpo.append(H3(item[1]))
        elif t == "p": cuerpo.append(P(item[1]))
        elif t == "vi": cuerpo.append(VI(item[1]))
        elif t == "tabla":
            cuerpo.append(tabla(item[1], item[2] if len(item) > 2 else None))
        elif t == "fig-ext":
            w, h = Image.open(a.diagrama).size
            num_img += 1
            cuerpo.append(figura(rid_diag, w, h, num_img, 6.3, 7.0))
            cuerpo.append(PIE(item[2].format(n=num_img)))
        elif t == "fig":
            nombre = item[1]
            if nombre not in rid_de:
                sys.exit(f"ERROR: no hay relación para {nombre}")
            rid, archivo = rid_de[nombre]
            w, h = Image.open(media / archivo).size
            num_img += 1
            usados.add(rid)
            cuerpo.append(figura(rid, w, h, num_img))
            cuerpo.append(PIE(item[2].format(n=num_img)))
        elif t == "ldap":
            if item[1] < len(rid_ldap):
                rid, w, h = rid_ldap[item[1]]
                num_img += 1
                cuerpo.append(figura(rid, w, h, num_img, 4.6, 6.0))
                cuerpo.append(PIE(item[2].format(n=num_img)))
        elif t == "matriz":
            cab = ["Origen", "Destino", "Protocolo / puerto", "Esperado", "Obtenido", "Resultado"]
            cuerpo.append(tabla([cab] + filas_m, [1150, 1900, 1250, 1050, 2776, 900], sz=16))
            cuerpo.append(P(f"Resumen: {resumen['pass_total']} PASS y {resumen['fail_total']} FAIL de {len(filas_m)} filas "
                            f"({resumen['aws']} desde EC2 de AWS y {resumen['ext']} desde Internet)."))
    x = x.replace("@@FASE3@@", "".join(cuerpo))
    log.append(f"Fase 3: {num_img - 35} figuras nuevas numeradas desde la Imagen 36; matriz con {len(filas_m)} filas")

    # ---- referencias a imágenes usadas y limpieza
    rels = rels.replace("</Relationships>", "".join(nuevo_rels) + "</Relationships>")
    en_uso = set(re.findall(r'r:embed="([^"]+)"', x))
    quitadas = 0
    for m_ in list(re.finditer(r'<Relationship [^>]*?/>', rels)):
        s = m_.group(0)
        t = re.search(r'Target="/?media/([^"]+)"', s)
        i = re.search(r'Id="([^"]+)"', s)
        if t and i and i.group(1) not in en_uso:
            rels = rels.replace(s, "")
            f = media / t.group(1)
            if f.exists():
                f.unlink()
            quitadas += 1
    log.append(f"imágenes sin uso quitadas: {quitadas}")
    doc.write_text(x, encoding="utf8")
    rels_p.write_text(rels, encoding="utf8")
    print("\n".join(log))


if __name__ == "__main__":
    main()
