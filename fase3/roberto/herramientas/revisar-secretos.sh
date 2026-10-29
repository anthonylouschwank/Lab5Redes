#!/usr/bin/env bash
# revisar-secretos.sh — Revisión final de secretos antes de subir/entregar (E9.4, E10.6).
#
#   bash revisar-secretos.sh [carpeta ...]     (por defecto: la carpeta fase3/ del repo)
#
# Busca en archivos de texto: claves privadas, claves de acceso de AWS, ARN con ID de cuenta,
# IDs de cuenta de 12 dígitos junto a palabras de cuenta, hashes de contraseña, asignaciones
# de contraseña/token con valor real, y archivos que no deben versionarse (.pem, .key, credenciales.env).
# Imprime archivo:línea y el TIPO de hallazgo; NUNCA imprime el valor encontrado.
# Código de salida: 0 = sin hallazgos, 1 = hay hallazgos. Esto NO revisa imágenes (PNG/JPG):
# las capturas hay que mirarlas a ojo (ver evidencias/README.md).
set -uo pipefail

if (($# == 0)); then
    RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
    set -- "$RAIZ"
fi

hallazgos=0
reporta() { printf 'HALLAZGO [%s] %s:%s\n' "$1" "$2" "$3"; hallazgos=$((hallazgos + 1)); }

# tipo|regex (grep -E). Los valores de ejemplo/placeholder se descartan más abajo.
PATRONES=(
    "clave-privada|-----BEGIN [A-Z ]*PRIVATE KEY-----"
    "aws-access-key|\b(AKIA|ASIA)[0-9A-Z]{16}\b"
    "aws-secret|aws_secret_access_key[[:space:]]*[=:]"
    "arn-con-cuenta|arn:aws[a-z-]*:[a-z0-9-]*:[a-z0-9-]*:[0-9]{12}:"
    "id-de-cuenta|(account[ _-]?id|cuenta|OwnerId)[^0-9]{0,20}[0-9]{12}\b"
    "hash-ldap|\{(SSHA|SHA|SSHA512|CRYPT|PBKDF2[A-Z0-9-]*)\}[A-Za-z0-9+/=]{10,}"
    'hash-etc-shadow|\$(1|5|6|y)\$[A-Za-z0-9./]{2,}\$[A-Za-z0-9./]{10,}'
    "contrasena-asignada|(pass(word)?|passwd|secret|token|api[_-]?key)[A-Za-z0-9_]*[[:space:]]*[=:][[:space:]]*[\"']?[^[:space:]\"'$<>{}(][^[:space:]\"']{3,}"
)
# Valores que cuentan como marcador de posición y no son un secreto
PLACEHOLDER='(changeme|cambiar|ejemplo|example|placeholder|xxxx|\*{4,}|<[^>]*>|oculto|SECRETO_INSTALADO|generada-en-el-momento|\$\{?[A-Za-z_])'

while IFS= read -r -d '' f; do
    base="$(basename "$f")"
    case "$base" in
        *.pem|*.key|*.p12|*.pfx|id_rsa*|id_ed25519*|credenciales.env|fase3.env|*.tfstate)
            case "$base" in *.example*|*.pub) ;; *) reporta "archivo-que-no-se-versiona" "$f" "-" ;; esac ;;
    esac
    # Solo texto
    grep -Iq . "$f" 2>/dev/null || continue
    for par in "${PATRONES[@]}"; do
        tipo="${par%%|*}"; rx="${par#*|}"
        while IFS=: read -r n resto; do
            [[ -z "$n" ]] && continue
            if [[ "$tipo" == "contrasena-asignada" || "$tipo" == "id-de-cuenta" ]]; then
                grep -Eiq "$PLACEHOLDER" <<<"$resto" && continue
            fi
            reporta "$tipo" "$f" "$n"
        done < <(grep -nEi -- "$rx" "$f" 2>/dev/null)
    done
done < <(find "$@" -type f -not -path '*/.git/*' -not -name 'revisar-secretos.sh' -print0 2>/dev/null)

if ((hallazgos == 0)); then
    echo "Sin hallazgos en archivos de texto de: $*"
    echo "Pendiente a mano: capturas PNG/JPG (ID de cuenta, ARN, claves en pantalla) y el DOCX del informe."
    exit 0
fi
echo "Total: $hallazgos hallazgo(s). Corrígelos o confirma que son falsos positivos antes de entregar."
exit 1
