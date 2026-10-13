#!/usr/bin/env bash
# CA propia del laboratorio: "CA Hospital Privado Castillejos".
# Firma los certificados TLS de los servidores (p. ej. mail.hospital.redes.test) para que los
# clientes solo importen UNA vez el certificado de la CA y confíen en todos los servidores.
# La clave privada de la CA vive solo en este equipo (/etc/ssl/hospital-ca, no se sube al repo).
#
# Uso (en la VM que guarda la CA, desde ~/lab5):
#   sudo bash infra/ca.sh init                          # crea la CA (una sola vez)
#   sudo bash infra/ca.sh firmar <archivo.csr> <nombre>  # firma la CSR de un servidor -> <nombre>.crt
#   p. ej.: sudo bash infra/ca.sh firmar mail.csr mail.hospital.redes.test
set -euo pipefail
ORIGEN="$(pwd)"                       # la CSR y el certificado firmado van relativos a aquí
cd "$(dirname "$0")/.."
source lab.env

DIR=/etc/ssl/hospital-ca
CA_KEY="$DIR/ca.key"
CA_CRT="$DIR/ca.crt"
PUBLICO="infra/ca/hospital-ca.crt"     # copia pública para distribuir a los clientes

case "${1:-}" in
init)
    [ -f "$CA_KEY" ] && { echo "La CA ya existe en $DIR"; exit 0; }
    install -d -m 700 "$DIR"
    openssl req -x509 -newkey rsa:3072 -nodes -days 1825 \
        -subj "/O=${ORG_NAME}/CN=CA ${ORG_NAME}" \
        -addext "basicConstraints=critical,CA:TRUE,pathlen:0" \
        -addext "keyUsage=critical,keyCertSign,cRLSign" \
        -keyout "$CA_KEY" -out "$CA_CRT"
    chmod 600 "$CA_KEY"
    ;;
firmar)
    CSR="${2:?Falta el archivo .csr}"; NOMBRE="${3:?Falta el nombre DNS del servidor}"
    case "$CSR" in /*) ;; *) CSR="${ORIGEN}/${CSR}" ;; esac
    SALIDA="${ORIGEN}/${NOMBRE}.crt"
    [ -f "$CA_KEY" ] || { echo "Primero: sudo bash infra/ca.sh init"; exit 1; }
    EXT="$(mktemp)"; trap 'rm -f "$EXT"' EXIT
    cat > "$EXT" <<EOF
basicConstraints = critical, CA:FALSE
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = DNS:${NOMBRE}
EOF
    # El nombre que validan los clientes (SAN) lo fija la CA, no la CSR
    openssl x509 -req -in "$CSR" -CA "$CA_CRT" -CAkey "$CA_KEY" -CAcreateserial \
        -days 825 -sha256 -extfile "$EXT" -out "$SALIDA"
    openssl verify -CAfile "$CA_CRT" "$SALIDA"
    openssl x509 -in "$SALIDA" -noout -subject -issuer -ext basicConstraints,subjectAltName -fingerprint -sha256
    echo "Certificado firmado: $SALIDA"
    ;;
*)
    sed -n '6,10p' "$0"; exit 1 ;;
esac

install -d infra/ca
cp "$CA_CRT" "$PUBLICO"
echo "Certificado público de la CA (para importar en los clientes): $PUBLICO"
openssl x509 -in "$PUBLICO" -noout -subject -fingerprint -sha256
