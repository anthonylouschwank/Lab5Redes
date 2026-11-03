"""Citas — Hospital Privado Castillejos (Fase 4, CC3067).

Aplicación pública de gestión de citas con datos FICTICIOS.
- Crear cita -> devuelve un código (XXXX-XXXX).
- Consultar cita por código.
No almacena ni muestra expedientes clínicos.

Se ejecuta con gunicorn en 127.0.0.1:8000 detrás de nginx (TLS).
"""
import os
import re
import secrets
import sqlite3
from datetime import date, datetime, timedelta, timezone

from flask import Flask, g, render_template, request, abort

DB_PATH = os.environ.get("CITAS_DB", "/var/lib/citas/citas.db")
MAX_CITAS = int(os.environ.get("CITAS_MAX", "5000"))  # tope anti-abuso

ESPECIALIDADES = [
    "Medicina general",
    "Pediatría",
    "Ginecología",
    "Cardiología",
    "Traumatología",
    "Laboratorio clínico",
]
HORAS = [f"{h:02d}:{m:02d}" for h in range(7, 17) for m in (0, 30)]
ALFABETO = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"  # sin 0/O/1/I
RE_NOMBRE = re.compile(r"^[A-Za-zÁÉÍÓÚÜÑáéíóúüñ' .-]{3,60}$")
RE_CODIGO = re.compile(r"^[A-Z2-9]{4}-?[A-Z2-9]{4}$")

app = Flask(__name__)
app.config["MAX_CONTENT_LENGTH"] = 8 * 1024


# --- Base de datos -----------------------------------------------------------
def db():
    if "db" not in g:
        g.db = sqlite3.connect(DB_PATH)
        g.db.row_factory = sqlite3.Row
    return g.db


@app.teardown_appcontext
def cerrar_db(_exc):
    conn = g.pop("db", None)
    if conn is not None:
        conn.close()


def iniciar_db():
    os.makedirs(os.path.dirname(DB_PATH), exist_ok=True)
    with sqlite3.connect(DB_PATH) as conn:
        conn.execute(
            """CREATE TABLE IF NOT EXISTS citas (
                   codigo TEXT PRIMARY KEY,
                   nombre TEXT NOT NULL,
                   especialidad TEXT NOT NULL,
                   fecha TEXT NOT NULL,
                   hora TEXT NOT NULL,
                   motivo TEXT NOT NULL DEFAULT '',
                   creada TEXT NOT NULL
               )"""
        )


iniciar_db()


# --- Utilidades --------------------------------------------------------------
def nuevo_codigo():
    c = "".join(secrets.choice(ALFABETO) for _ in range(8))
    return f"{c[:4]}-{c[4:]}"


def iniciales(nombre):
    partes = [p for p in nombre.split() if p]
    return " ".join(p[0].upper() + "." for p in partes) or "—"


def rango_fechas():
    hoy = date.today()
    return hoy, hoy + timedelta(days=90)


@app.after_request
def cabeceras(resp):
    # nginx también las agrega; aquí van por defensa en profundidad.
    resp.headers.setdefault("X-Content-Type-Options", "nosniff")
    resp.headers.setdefault("Cache-Control", "no-store")
    return resp


# --- Rutas -------------------------------------------------------------------
@app.get("/")
def inicio():
    minimo, maximo = rango_fechas()
    return render_template(
        "index.html",
        especialidades=ESPECIALIDADES,
        horas=HORAS,
        fmin=minimo.isoformat(),
        fmax=maximo.isoformat(),
        errores=[],
        datos={},
    )


@app.post("/citas")
def crear_cita():
    f = request.form
    datos = {
        "nombre": " ".join(f.get("nombre", "").split()),
        "especialidad": f.get("especialidad", ""),
        "fecha": f.get("fecha", ""),
        "hora": f.get("hora", ""),
        "motivo": " ".join(f.get("motivo", "").split())[:200],
    }
    errores = []
    if not RE_NOMBRE.match(datos["nombre"]):
        errores.append("Nombre: 3 a 60 letras (use un nombre ficticio).")
    if datos["especialidad"] not in ESPECIALIDADES:
        errores.append("Seleccione una especialidad válida.")
    if datos["hora"] not in HORAS:
        errores.append("Seleccione una hora válida (07:00 a 16:30).")
    minimo, maximo = rango_fechas()
    try:
        fch = date.fromisoformat(datos["fecha"])
        if not (minimo <= fch <= maximo):
            errores.append("La fecha debe estar entre hoy y los próximos 90 días.")
        elif fch.weekday() == 6:
            errores.append("No se atiende los domingos.")
    except ValueError:
        errores.append("Fecha inválida.")
    if f.get("acepto") != "si":
        errores.append("Debe aceptar el aviso de privacidad.")

    if errores:
        return (
            render_template(
                "index.html",
                especialidades=ESPECIALIDADES,
                horas=HORAS,
                fmin=minimo.isoformat(),
                fmax=maximo.isoformat(),
                errores=errores,
                datos=datos,
            ),
            400,
        )

    conn = db()
    (total,) = conn.execute("SELECT COUNT(*) FROM citas").fetchone()
    if total >= MAX_CITAS:
        abort(503)
    for _ in range(5):
        codigo = nuevo_codigo()
        try:
            conn.execute(
                "INSERT INTO citas VALUES (?,?,?,?,?,?,?)",
                (
                    codigo,
                    datos["nombre"],
                    datos["especialidad"],
                    datos["fecha"],
                    datos["hora"],
                    datos["motivo"],
                    datetime.now(timezone.utc).isoformat(timespec="seconds"),
                ),
            )
            conn.commit()
            break
        except sqlite3.IntegrityError:
            continue
    else:
        abort(500)
    return render_template("creada.html", codigo=codigo, datos=datos), 201


@app.get("/consulta")
def consulta():
    codigo = request.args.get("codigo", "").strip().upper()
    if not codigo:
        return render_template("consulta.html", cita=None, codigo="", error=None)
    if not RE_CODIGO.match(codigo):
        return render_template("consulta.html", cita=None, codigo=codigo,
                               error="Formato de código inválido (XXXX-XXXX)."), 400
    if "-" not in codigo:
        codigo = f"{codigo[:4]}-{codigo[4:]}"
    fila = db().execute(
        "SELECT codigo, nombre, especialidad, fecha, hora FROM citas WHERE codigo = ?",
        (codigo,),
    ).fetchone()
    if fila is None:
        return render_template("consulta.html", cita=None, codigo=codigo,
                               error="No existe una cita con ese código."), 404
    cita = dict(fila)
    cita["paciente"] = iniciales(cita.pop("nombre"))
    return render_template("consulta.html", cita=cita, codigo=codigo, error=None)


@app.get("/privacidad")
def privacidad():
    return render_template("privacidad.html")


@app.get("/salud")
def salud():
    return {"estado": "ok"}


@app.errorhandler(404)
def no_encontrado(_e):
    return render_template("error.html", mensaje="Página no encontrada."), 404


@app.errorhandler(503)
def lleno(_e):
    return render_template("error.html", mensaje="Servicio de citas temporalmente no disponible."), 503
