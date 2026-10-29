# Uso: rrun.ps1 <instance-id> <puerto-local> <script-local.sh>
# Ejecuta un script bash local en la EC2 (por stdin) a través del túnel EICE.
param([string]$Id, [int]$Port, [string]$Script)
$OutputEncoding = New-Object System.Text.UTF8Encoding $false
$null = aws ec2-instance-connect send-ssh-public-key --region us-east-1 --instance-id $Id `
    --availability-zone us-east-1a --instance-os-user ubuntu `
    --ssh-public-key "file://$env:USERPROFILE\.ssh\hospital_fase3.pub"
$remoto = 'tr -d ''\r'' | sed ''1s/^\xEF\xBB\xBF//'' | bash -s'
Get-Content -Raw -Encoding UTF8 $Script | ssh -i "$env:USERPROFILE\.ssh\hospital_fase3" -p $Port -o IdentitiesOnly=yes `
    -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o HostKeyAlias=$Id -o ConnectTimeout=15 `
    ubuntu@127.0.0.1 $remoto
