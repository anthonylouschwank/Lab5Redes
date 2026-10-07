# Configura el Windows anfitrión para resolver hospital.redes.test con el BIND9 del laboratorio.
# Usa una regla NRPT (Name Resolution Policy Table): solo las consultas de la zona del
# laboratorio van a 10.0.0.37; el resto de Internet sigue usando el DNS normal.
# No se modifica el archivo hosts.
#
# Ejecutar en PowerShell COMO ADMINISTRADOR:
#   powershell -ExecutionPolicy Bypass -File infra\windows-dns.ps1          # crear regla
#   powershell -ExecutionPolicy Bypass -File infra\windows-dns.ps1 -Quitar  # eliminar regla

param([switch]$Quitar)

$ErrorActionPreference = "Stop"
$dns = "10.0.0.37"
$zonas = @(".hospital.redes.test", "hospital.redes.test", ".0.0.10.in-addr.arpa")
$comentario = "Lab5Redes"

Get-DnsClientNrptRule | Where-Object Comment -eq $comentario | ForEach-Object {
    Remove-DnsClientNrptRule -Name $_.Name -Force
}

if (-not $Quitar) {
    Add-DnsClientNrptRule -Namespace $zonas -NameServers $dns -Comment $comentario
    Write-Host "Regla NRPT creada: $($zonas -join ', ') -> $dns"
} else {
    Write-Host "Regla NRPT eliminada."
}

Clear-DnsClientCache
Get-DnsClientNrptRule | Where-Object Comment -eq $comentario | Format-List Namespace, NameServers

if (-not $Quitar) {
    # Resolve-DnsName respeta NRPT (nslookup NO: consulta directo al DNS de la interfaz)
    foreach ($n in "ns1", "ldap", "www", "mail", "ftp") {
        Resolve-DnsName "$n.hospital.redes.test" -Type A | Format-Table Name, Type, IPAddress -AutoSize
    }
}
