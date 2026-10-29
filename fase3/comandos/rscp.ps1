# Uso: rscp.ps1 <instance-id> <puerto-local> <origen-local> <destino-remoto>
# Copia archivos o carpetas (-r) a la EC2 a través del túnel EICE.
param([string]$Id, [int]$Port, [string]$Src, [string]$Dst)
$null = aws ec2-instance-connect send-ssh-public-key --region us-east-1 --instance-id $Id `
    --availability-zone us-east-1a --instance-os-user ubuntu `
    --ssh-public-key "file://$env:USERPROFILE\.ssh\hospital_fase3.pub"
scp -r -i "$env:USERPROFILE\.ssh\hospital_fase3" -P $Port -o IdentitiesOnly=yes -o BatchMode=yes `
    -o StrictHostKeyChecking=accept-new -o HostKeyAlias=$Id $Src "ubuntu@127.0.0.1:$Dst"
