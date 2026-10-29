#!/usr/bin/env python3
"""ocultar_datos_capturas.py — Tapa con rectángulos opacos los datos sensibles de capturas de la consola AWS (E9.4).

Uso:
    python3 -I ocultar_datos_capturas.py ENTRADA SALIDA [--ip-publicas] [--extra TEXTO ...] [--reporte archivo.tsv]

  ENTRADA   carpeta con PNG/JPG (o un solo archivo). No se modifica.
  SALIDA    carpeta donde se escriben las copias ya tapadas (mismo nombre y formato).

Qué tapa (OCR con tesseract, que debe estar instalado):
  * IDs de cuenta de AWS: números de 12 dígitos, con o sin paréntesis o guiones (544754350609, 5447-5435-0609).
  * ARN completos (arn:aws:...).
  * El alias de usuario de la insignia de la consola (esquina superior derecha) y la línea de usuario bajo ella.
  * Con --ip-publicas: IPv4 públicas (no 10.x, 172.16-31.x, 192.168.x, 169.254.x, 127.x), con o sin /32.
  * Con --extra: cualquier texto adicional (por ejemplo un alias de usuario) sin importar mayúsculas.

Limitaciones: el OCR puede fallar en texto muy pequeño o borroso. Por eso el script escribe un reporte con lo
que tapó en cada imagen y **hay que abrir cada copia de SALIDA y comprobarla a ojo** antes de usarla. Si algo
quedó visible, súmalo con --extra o tápalo a mano. No es una garantía de privacidad.
"""
import argparse
import csv
import ipaddress
import re
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw, ImageOps

ESCALA_OCR = 2          # se amplía la imagen para que el OCR lea mejor el texto pequeño
RE_12 = re.compile(r"(?<!\d)(\d{4}[-\s]?\d{4}[-\s]?\d{4})(?!\d)")
RE_IP = re.compile(r"(?<![\d.])((?:\d{1,3}\.){3}\d{1,3})(?:/\d{1,2})?(?![\d.])")
RE_ARN = re.compile(r"arn:aws[a-z-]*:", re.I)


def _pasada(g: Image.Image, escala: int, psm: str):
    with tempfile.TemporaryDirectory() as d:
        p = Path(d) / "x.png"
        g.resize((g.width * escala, g.height * escala), Image.LANCZOS).save(p)
        r = subprocess.run(["tesseract", str(p), "-", "--psm", psm, "tsv"], capture_output=True, text=True)
    palabras = []
    for fila in csv.reader(r.stdout.splitlines(), delimiter="\t", quoting=csv.QUOTE_NONE):
        if len(fila) < 12 or fila[0] == "level" or fila[0] != "5":
            continue
        txt = fila[11].strip()
        if not txt:
            continue
        x, y, w, h = (int(fila[i]) // escala for i in (6, 7, 8, 9))
        palabras.append((txt, x, y, max(w, 1), max(h, 1), (fila[2], fila[3], fila[4])))
    return palabras


def ocr(img: Image.Image):
    """Palabras [(texto, x, y, w, h, linea_id)] en coordenadas de la imagen original.
    Las capturas de la consola suelen ser de tema oscuro: se lee la imagen invertida y la original y se unen."""
    g = img.convert("L")
    escala = 3 if img.width < 1200 else 2
    todas = _pasada(ImageOps.invert(g), escala, "11") + _pasada(g, escala, "11")
    unicas = []
    for t in todas:
        if not any(t[0] == u[0] and abs(t[1] - u[1]) < 6 and abs(t[2] - u[2]) < 6 for u in unicas):
            unicas.append(t)
    return unicas


def es_ip_publica(txt: str) -> bool:
    try:
        ip = ipaddress.ip_address(txt)
    except ValueError:
        return False
    return ip.version == 4 and not (ip.is_private or ip.is_loopback or ip.is_link_local or ip.is_multicast or ip.is_reserved)


def cajas_a_tapar(palabras, ip_publicas, extra, ancho):
    """Devuelve [(x0,y0,x1,y1,motivo)]."""
    cajas = []
    extra_l = [e.lower() for e in extra]
    for i, (t, x, y, w, h, linea) in enumerate(palabras):
        tl = t.lower()
        # El OCR agrega símbolos ($, S, £) y las columnas de la consola cortan el ID con "...": se ignoran.
        limpio = t.strip("()[],.:;$£¥…—-_ ").replace("...", "").replace("…", "")
        limpio = re.sub(r"^[SsOo$£¥]+(?=\d)", "", limpio)
        # confusiones típicas del OCR dentro de un número largo: S->5, O->0, I/l->1, B->8
        if re.fullmatch(r"\d[\dSsOoIlB]{8,13}", limpio) and sum(c.isdigit() for c in limpio) >= 0.7 * len(limpio):
            limpio = limpio.translate(str.maketrans("SsOoIlB", "5500118"))
        solo_dig = re.sub(r"\D", "", limpio)
        motivo = None
        if RE_12.fullmatch(limpio) or (len(solo_dig) >= 9 and len(limpio) - len(solo_dig) <= 2 and not re.search(r"[A-Za-z]", limpio)):
            motivo = "id-cuenta"
        elif RE_ARN.search(t):
            motivo = "arn"
        elif ip_publicas:
            m = RE_IP.search(t)
            if m and es_ip_publica(m.group(1)):
                motivo = "ip-publica"
        if motivo is None and any(e in tl for e in extra_l):
            motivo = "extra"
        if motivo is None:
            continue
        x0, x1 = x, x + w
        if motivo == "arn":  # el ARN puede quedar partido en varias palabras de la misma línea
            for t2, x2, y2, w2, h2, l2 in palabras[i + 1:]:
                if l2 == linea and x2 >= x1 - 2 and x2 - x1 < 40:
                    x1 = max(x1, x2 + w2)
        cajas.append((x0, y, x1, y + h, motivo))
    return cajas


def detectar_insignia(img: Image.Image):
    """Cubre la insignia de la consola de AWS (alias + ID de cuenta, esquina superior derecha) y el alias repetido
    debajo. Se decide por el color: la insignia es una píldora de gris (128,137,151) en la esquina superior
    derecha; si no hay suficientes píxeles de ese gris ahí, la captura no tiene insignia y devuelve None.
    La caja es proporcional al tamaño de la captura (la consola mantiene esa proporción)."""
    import numpy as np
    W, H = img.size
    if W < 700:
        return None
    gx0, gx1, gy0, gy1 = int(W * 0.86), int(W * 0.995), 0, int(H * 0.12)
    arr = np.array(img.convert("RGB"))[gy0:gy1, gx0:gx1, :].astype(int)
    r, g, b = arr[:, :, 0], arr[:, :, 1], arr[:, :, 2]
    hit = (abs(r - 128) <= 8) & (abs(g - 137) <= 8) & (abs(b - 151) <= 8)
    if int(hit.sum()) < 60:
        return None
    filas = np.nonzero(hit.sum(axis=1) >= 12)[0]
    if len(filas) == 0:
        return None
    arriba = int(filas[0])
    return (int(W * 0.862), max(arriba - 6, 0), int(W * 0.997), int(arriba + H * 0.078), "insignia")


def tapar(img: Image.Image, cajas, margen=3):
    out = img.convert("RGB")
    d = ImageDraw.Draw(out)
    for x0, y0, x1, y1, _ in cajas:
        d.rectangle((x0 - margen, y0 - margen, x1 + margen, y1 + margen), fill=(0, 0, 0))
    return out


def procesar(ruta: Path, salida: Path, ip_publicas, extra, filas):
    img = Image.open(ruta)
    pal = ocr(img)
    cajas = cajas_a_tapar(pal, ip_publicas, extra, img.width)
    ins = detectar_insignia(img)
    if ins:
        cajas.append(ins)
    # La insignia de usuario se detecta por su texto completo "alias (123456789012)": tapar la caja completa
    res = tapar(img, cajas)
    destino = salida / ruta.name
    if ruta.suffix.lower() in (".jpg", ".jpeg"):
        res.save(destino, quality=92)
    else:
        res.save(destino)
    for c in cajas:
        filas.append((ruta.name, c[4], f"{c[0]},{c[1]},{c[2]},{c[3]}"))
    return len(cajas)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("entrada", type=Path)
    ap.add_argument("salida", type=Path)
    ap.add_argument("--ip-publicas", action="store_true", help="también tapa IPv4 públicas")
    ap.add_argument("--extra", nargs="*", default=[], help="textos adicionales a tapar")
    ap.add_argument("--reporte", type=Path, help="TSV con lo que se tapó en cada imagen")
    a = ap.parse_args()
    if subprocess.run(["which", "tesseract"], capture_output=True).returncode != 0:
        sys.exit("Falta tesseract (brew install tesseract / apt install tesseract-ocr).")
    archivos = [a.entrada] if a.entrada.is_file() else sorted(p for p in a.entrada.iterdir() if p.suffix.lower() in (".png", ".jpg", ".jpeg"))
    a.salida.mkdir(parents=True, exist_ok=True)
    filas, total = [], 0
    for p in archivos:
        n = procesar(p, a.salida, a.ip_publicas, a.extra, filas)
        total += n
        print(f"{p.name}: {n} zona(s) tapada(s)")
    if a.reporte:
        with a.reporte.open("w", newline="") as f:
            w = csv.writer(f, delimiter="\t")
            w.writerow(["imagen", "motivo", "caja_x0,y0,x1,y1"])
            w.writerows(filas)
    print(f"Total: {total} zona(s) en {len(archivos)} imagen(es). ABRE cada copia de {a.salida} y comprueba a ojo.")


if __name__ == "__main__":
    main()
