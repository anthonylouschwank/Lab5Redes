# Fase 4 - F4 - Fijar la clave del usuario admin de Grafana en TI (la escribe el usuario; no se muestra).
# Requisitos: clave cargada en ssh-agent y tunel EICE a TI abierto en el puerto 2223:
#   aws ec2-instance-connect open-tunnel --instance-id i-0bfd1235ccdec6e96 --local-port 2223 --remote-port 22 --region us-east-1
# Uso: .\fase4\snmp\grafana-password.ps1
# Nota: PowerShell 5.1 rompe las comillas dobles en argumentos de programas nativos, por eso el
# script remoto viaja en base64 (sin comillas) y se ejecuta con la terminal (-t) como stdin.
$id = 'i-0bfd1235ccdec6e96'; $key = "$env:USERPROFILE\.ssh\hospital_fase3"
$bash = @'
set -u
cd /usr/share/grafana || exit 1
read -rs -p "Nueva clave de admin de Grafana: " P1; echo
read -rs -p "Repitela: " P2; echo
if [ -z "$P1" ] || [ "$P1" != "$P2" ]; then echo "No coinciden o esta vacia. Sin cambios."; exit 1; fi
if printf '%s' "$P1" | sudo -u grafana grafana cli --homepath /usr/share/grafana --config /etc/grafana/grafana.ini admin reset-admin-password --password-from-stdin >/dev/null 2>&1; then
  echo "Listo. Usuario: admin"
else
  echo "ERROR: grafana cli fallo (sin cambios)"
fi
unset P1 P2
'@
$b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($bash -replace "`r", '')))
$remoto = "echo $b64 | base64 -d > /tmp/gpw.`$`$.sh; bash /tmp/gpw.`$`$.sh; rm -f /tmp/gpw.`$`$.sh"
$null = aws ec2-instance-connect send-ssh-public-key --region us-east-1 --instance-id $id `
    --availability-zone us-east-1a --instance-os-user ubuntu --ssh-public-key "file://$key.pub"
ssh -t -i $key -p 2223 -o IdentitiesOnly=yes -o HostKeyAlias=$id ubuntu@127.0.0.1 $remoto
