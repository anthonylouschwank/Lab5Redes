# Fase 4 · F4 — Ejecuta un script remoto inyectando AUTH/PRIV leídos de TI (/etc/snmp-fase4/creds).
# Las credenciales solo viven en memoria (variable de PowerShell -> stdin de ssh). Nunca se imprimen
# ni se escriben en disco local.
# Uso: .\fase4\snmp\distribuir-snmp.ps1 -Script <script.sh> -Destinos @(@{id='i-..';port=2222}, ...)
param([string]$Script, [array]$Destinos)
$OutputEncoding = New-Object System.Text.UTF8Encoding $false
$key = "$env:USERPROFILE\.ssh\hospital_fase3"
function Push-Key($id) {
    $null = aws ec2-instance-connect send-ssh-public-key --region us-east-1 --instance-id $id `
        --availability-zone us-east-1a --instance-os-user ubuntu --ssh-public-key "file://$key.pub"
}
function Ssh-Args($id, $port) {
    @('-i', $key, '-p', $port, '-o', 'IdentitiesOnly=yes', '-o', 'BatchMode=yes', '-o', 'StrictHostKeyChecking=accept-new',
      '-o', "HostKeyAlias=$id", '-o', 'ConnectTimeout=15', 'ubuntu@127.0.0.1')
}
# 1. Leer credenciales de TI (i-0bfd1235ccdec6e96, túnel 2223)
Push-Key 'i-0bfd1235ccdec6e96'
$creds = (ssh @(Ssh-Args 'i-0bfd1235ccdec6e96' 2223) 'sudo cat /etc/snmp-fase4/creds') -join "`n"
if ($creds -notmatch '(?m)^AUTH=[0-9a-f]{32}$' -or $creds -notmatch '(?m)^PRIV=[0-9a-f]{32}$') { throw 'No se pudieron leer credenciales válidas de TI' }
$pre = ($creds -split "`n" | ForEach-Object { "export $_" }) -join "`n"
$cuerpo = (Get-Content -Raw -Encoding UTF8 $Script) -replace "`r", '' -replace "^\xEF\xBB\xBF", ''
$remoto = 'tr -d ''\r'' | sed ''1s/^\xEF\xBB\xBF//'' | bash -s'
foreach ($d in $Destinos) {
    Push-Key $d.id
    ($pre + "`n" + $cuerpo) | ssh @(Ssh-Args $d.id $d.port) $remoto
}
Remove-Variable creds, pre -ErrorAction SilentlyContinue
