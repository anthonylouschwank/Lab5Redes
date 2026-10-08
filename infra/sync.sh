#!/usr/bin/env bash
# Sincroniza el repositorio con la VM (alias "lab5" en ~/.ssh/config, ver infra/README.md).
# Uso desde Windows (Git Bash), en la raíz del repo:
#   bash infra/sync.sh          # copia el repo (incluye secrets/, sin .git) a lab5:~/lab5
#   bash infra/sync.sh --traer  # trae las evidencias generadas en la VM a tests/evidencias/
set -euo pipefail
cd "$(dirname "$0")/.."

if [ "${1:-}" = "--traer" ]; then
    ssh lab5 'tar czf - -C ~/lab5 tests/evidencias' | tar xzf -
    echo "Evidencias copiadas a tests/evidencias/"
    exit 0
fi

# Las evidencias generadas en la VM no se sobrescriben con las locales
tar czf - --exclude=.git --exclude=tests/evidencias . |
    ssh lab5 'mkdir -p ~/lab5 && tar xzf - -C ~/lab5 --no-same-owner && chmod 700 ~/lab5/secrets'
echo "Repositorio sincronizado en lab5:~/lab5"
