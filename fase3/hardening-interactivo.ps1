# hardening-interactivo.ps1 — Ejecuta hardening.sh de Leonardo en una EC2, en TU terminal.
# Requiere: la clave en ssh-agent y el túnel EICE de esa EC2 abierto (puertos 2222-2225).
#
#   Ventana 1:  .\hardening-interactivo.ps1 <servidores|medicos|visitantes|ti>
#   Ventana 2:  .\hardening-interactivo.ps1 <mismo equipo> -Verificar
#               (cuando la ventana 1 diga "AHORA ... abre OTRA terminal")
param(
    [Parameter(Mandatory)][ValidateSet('servidores', 'medicos', 'visitantes', 'ti')][string]$Equipo,
    [switch]$Verificar
)
$tabla = @{
    servidores = @{ Id = 'i-095520a21f761f97d'; Puerto = 2222; Rol = 'servidores' }
    ti         = @{ Id = 'i-0bfd1235ccdec6e96'; Puerto = 2223; Rol = 'ti' }
    medicos    = @{ Id = 'i-080244876b92e25c6'; Puerto = 2224; Rol = 'cliente' }
    visitantes = @{ Id = 'i-0c8ad80ff90f5bdbd'; Puerto = 2225; Rol = 'cliente' }
}
$e = $tabla[$Equipo]
$null = aws ec2-instance-connect send-ssh-public-key --region us-east-1 --instance-id $e.Id `
    --availability-zone us-east-1a --instance-os-user ubuntu `
    --ssh-public-key "file://$env:USERPROFILE\.ssh\hospital_fase3.pub"
$opts = @('-i', "$env:USERPROFILE\.ssh\hospital_fase3", '-p', $e.Puerto, '-o', 'IdentitiesOnly=yes',
          '-o', "HostKeyAlias=$($e.Id)", '-o', 'ConnectTimeout=15')
if ($Verificar) {
    ssh @opts ubuntu@127.0.0.1 'echo "ACCESO OK: $(hostname) $(date +%T)"'
    if ($LASTEXITCODE -eq 0) { Write-Host "`nEntraste. Vuelve a la ventana 1 y escribe SI." -ForegroundColor Green }
    else { Write-Host "`nNO entraste. No escribas SI: el rollback automático revertirá el cambio." -ForegroundColor Red }
} else {
    ssh -t @opts ubuntu@127.0.0.1 "cd ~/fase3/leonardo && sudo FASE3_EVID_DIR=/home/ubuntu/fase3/evidencias bash hardening.sh $($e.Rol)"
}
