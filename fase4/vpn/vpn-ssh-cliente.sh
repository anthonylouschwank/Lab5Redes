#!/bin/bash
# Fase 4 · F3 — TI y Médicos: SSH desde el peer VPN hospital-ti (10.8.0.2).
# Reversión: sudo ufw delete allow from 10.8.0.2 to any port 22 proto tcp
set -euo pipefail
echo "== $(hostname)"
sudo ufw allow from 10.8.0.2 to any port 22 proto tcp comment 'fase4: SSH desde VPN peer hospital-ti'
sudo ufw status numbered | grep -E '22/tcp|Status'
