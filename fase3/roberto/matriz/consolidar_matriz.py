#!/usr/bin/env python3
"""Consolida los resultados-<origen>-<fecha>.csv de tests_fase3.sh (Leonardo) en una
sola matriz para el informe (E8).

Uso:
    python3 -I consolidar_matriz.py [--resultados DIR] [--esperada CSV] [--salida DIR] [--estricto]

  --resultados  carpeta con los resultados-*.csv (por defecto: ../evidencias/csv)
  --esperada    lista de pruebas esperadas (por defecto: matriz-esperada.csv junto a este script)
  --salida      carpeta de salida (por defecto: esta carpeta)
  --estricto    termina con código 1 si queda alguna prueba FAIL o PENDIENTE

Criterios:
  * CSV de entrada: fecha,origen,destino,protocolo_puerto,esperado,obtenido,resultado
    (no trae ID; se asocia por origen + destino + protocolo).
  * Si una prueba aparece varias veces (por --solo o repetición), vale la fila más reciente.
  * Una prueba esperada sin fila en ningún CSV queda PENDIENTE (no se asume que pasó).
  * Filas de los CSV que no corresponden a ninguna prueba esperada se listan aparte.
Salidas: matriz-consolidada.csv y matriz-consolidada.md
"""
import argparse
import csv
import re
import sys
from pathlib import Path

AQUI = Path(__file__).resolve().parent


def nombre_destino(destino: str) -> str:
    """'servidores (10.0.0.46)' -> 'servidores'."""
    return re.sub(r"\s*\(.*\)\s*$", "", destino.strip())


def familia_proto(proto: str) -> str:
    """HTTP/80 y HTTPS/443 cuentan como WEB (la intranet puede pasar de http a https)."""
    p = proto.strip()
    m = re.match(r"^HTTPS?/\d+$", p)
    return "WEB" if m else p


def clave(origen: str, destino: str, proto: str):
    return (origen.strip(), nombre_destino(destino), familia_proto(proto))


def leer_esperadas(ruta: Path):
    with ruta.open(newline="", encoding="utf-8") as f:
        filas = list(csv.DictReader(f))
    vistas = {}
    for r in filas:
        k = clave(r["origen"], r["destino"], r["protocolo_puerto"])
        if k in vistas:
            sys.exit(f"Error: {r['id']} y {vistas[k]} tienen la misma clave {k}; ajusta la matriz esperada.")
        vistas[k] = r["id"]
    return filas


def leer_resultados(carpeta: Path):
    """Devuelve {clave: fila_mas_reciente} y la lista de archivos leídos."""
    mejores, archivos = {}, []
    for ruta in sorted(carpeta.glob("resultados-*.csv")):
        archivos.append(ruta.name)
        with ruta.open(newline="", encoding="utf-8") as f:
            for r in csv.DictReader(f):
                if not r.get("origen") or not r.get("destino"):
                    continue
                r["_archivo"] = ruta.name
                k = clave(r["origen"], r["destino"], r["protocolo_puerto"])
                if k not in mejores or r["fecha"] >= mejores[k]["fecha"]:
                    mejores[k] = r
    return mejores, archivos


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--resultados", type=Path, default=AQUI.parent / "evidencias" / "csv")
    ap.add_argument("--esperada", type=Path, default=AQUI / "matriz-esperada.csv")
    ap.add_argument("--salida", type=Path, default=AQUI)
    ap.add_argument("--estricto", action="store_true")
    a = ap.parse_args()

    if not a.esperada.is_file():
        sys.exit(f"No existe {a.esperada}")
    esperadas = leer_esperadas(a.esperada)
    if a.resultados.is_dir():
        res, archivos = leer_resultados(a.resultados)
    else:
        print(f"Aviso: no existe la carpeta {a.resultados}; todo quedará PENDIENTE.", file=sys.stderr)
        res, archivos = {}, []

    campos = ["id", "fecha", "origen", "destino", "protocolo_puerto", "esperado", "obtenido", "resultado",
              "archivo_evidencia", "descripcion"]
    filas, usadas = [], set()
    for e in esperadas:
        k = clave(e["origen"], e["destino"], e["protocolo_puerto"])
        r = res.get(k)
        if r:
            usadas.add(k)
            if r["esperado"].strip() != e["esperado"].strip():
                obtenido = f"[AVISO: el CSV esperaba '{r['esperado']}', la matriz esperada dice '{e['esperado']}'] {r['obtenido']}"
            else:
                obtenido = r["obtenido"]
            filas.append({"id": e["id"], "fecha": r["fecha"], "origen": e["origen"], "destino": r["destino"],
                          "protocolo_puerto": r["protocolo_puerto"], "esperado": e["esperado"], "obtenido": obtenido,
                          "resultado": r["resultado"].strip().upper(), "archivo_evidencia": r["_archivo"],
                          "descripcion": e["descripcion"]})
        else:
            filas.append({"id": e["id"], "fecha": "", "origen": e["origen"], "destino": e["destino"],
                          "protocolo_puerto": e["protocolo_puerto"], "esperado": e["esperado"], "obtenido": "",
                          "resultado": "PENDIENTE", "archivo_evidencia": "", "descripcion": e["descripcion"]})
    extras = [r for k, r in res.items() if k not in usadas]

    a.salida.mkdir(parents=True, exist_ok=True)
    with (a.salida / "matriz-consolidada.csv").open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=campos)
        w.writeheader()
        w.writerows(filas)

    n = {k: sum(1 for r in filas if r["resultado"] == k) for k in ("PASS", "FAIL", "PENDIENTE")}
    icono = {"PASS": "✅ PASS", "FAIL": "❌ FAIL", "PENDIENTE": "⏳ PENDIENTE"}
    md = ["# Matriz de pruebas de conectividad — Fase 3", "",
          f"Archivos leídos: {', '.join(archivos) if archivos else '(ninguno)'}", "",
          f"**Resumen:** {n['PASS']} PASS · {n['FAIL']} FAIL · {n['PENDIENTE']} PENDIENTE de {len(filas)} pruebas.", "",
          "| ID | Origen | Destino | Protocolo | Esperado | Resultado | Obtenido | Evidencia |",
          "|---|---|---|---|---|---|---|---|"]
    for r in filas:
        md.append("| {id} | {origen} | {destino} | {protocolo_puerto} | {esperado} | {res} | {obtenido} | {archivo_evidencia} |".format(
            res=icono.get(r["resultado"], r["resultado"]), **{k: r[k].replace("|", "/") for k in r}))
    if extras:
        md += ["", "## Filas de los CSV que no corresponden a ninguna prueba esperada", ""]
        for r in extras:
            md.append(f"- {r['origen']} → {r['destino']} {r['protocolo_puerto']} ({r['resultado']}) en {r['_archivo']}")
    md += ["", "Una prueba PENDIENTE no se ejecutó o su destino no tenía IP en fase3.env: no cuenta como aprobada.", ""]
    (a.salida / "matriz-consolidada.md").write_text("\n".join(md), encoding="utf-8")

    print(f"PASS {n['PASS']} · FAIL {n['FAIL']} · PENDIENTE {n['PENDIENTE']} (de {len(filas)})")
    for r in filas:
        if r["resultado"] == "FAIL":
            print(f"  FAIL {r['id']}: {r['origen']} -> {r['destino']} {r['protocolo_puerto']} | {r['obtenido']}")
    if extras:
        print(f"  {len(extras)} fila(s) de CSV sin prueba esperada (ver el .md)")
    print(f"Escrito: {a.salida / 'matriz-consolidada.csv'} y .md")
    if a.estricto and (n["FAIL"] or n["PENDIENTE"]):
        sys.exit(1)


if __name__ == "__main__":
    main()
