# Fase 4 · F4 — Acceso a Grafana (solo TI): reenvía http://127.0.0.1:3000 de la laptop a 127.0.0.1:3000 en TI.
# Modo EICE (por defecto): requiere el túnel EICE a TI en el puerto 2223.
# Modo VPN (-Vpn): requiere el túnel WireGuard hospital-ti activo (SSH directo a 10.0.0.117).
# Deja la ventana abierta mientras uses Grafana; Ctrl+C para cerrar.
param([switch]$Vpn)
$id = 'i-0bfd1235ccdec6e96'; $key = "$env:USERPROFILE\.ssh\hospital_fase3"
$null = aws ec2-instance-connect send-ssh-public-key --region us-east-1 --instance-id $id `
    --availability-zone us-east-1a --instance-os-user ubuntu --ssh-public-key "file://$key.pub"
if ($Vpn) { $dest = @('ubuntu@10.0.0.117') } else { $dest = @('-p', '2223', 'ubuntu@127.0.0.1') }
Write-Host "Grafana en http://127.0.0.1:3000  (usuario admin). Ctrl+C para cerrar."
ssh -N -L 3000:127.0.0.1:3000 -i $key -o IdentitiesOnly=yes -o HostKeyAlias=$id -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 @dest
