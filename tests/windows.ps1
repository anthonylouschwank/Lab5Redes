# INT-01 desde el cliente Windows: resolución y conexión a cada servicio usando solo su FQDN.
# Requiere la regla NRPT (infra\windows-dns.ps1). No necesita administrador.
# Uso: powershell -ExecutionPolicy Bypass -File tests\windows.ps1
# Genera tests\evidencias\INT-01-windows.txt

$ErrorActionPreference = "Continue"
$dominio = "hospital.redes.test"
$salida = Join-Path $PSScriptRoot "evidencias\INT-01-windows.txt"

function Probar-Puerto([string]$nombre, [int]$puerto) {
    $tcp = New-Object System.Net.Sockets.TcpClient
    try {
        $tcp.Connect($nombre, $puerto)
        $banner = ""
        if ($puerto -in 21, 25, 587, 143) {
            $stream = $tcp.GetStream(); $stream.ReadTimeout = 3000
            $buf = New-Object byte[] 256
            $n = $stream.Read($buf, 0, $buf.Length)
            $banner = ([Text.Encoding]::ASCII.GetString($buf, 0, $n)).Trim()
        }
        "{0,-26} {1,-5} ABIERTO  {2} -> {3}  {4}" -f $nombre, $puerto, "conectado", $tcp.Client.RemoteEndPoint, $banner
    } catch {
        "{0,-26} {1,-5} ERROR    {2}" -f $nombre, $puerto, $_.Exception.InnerException.Message
    } finally { $tcp.Close() }
}

$r = @()
$r += "# INT-01 (cliente Windows) - Uso exclusivo de nombres DNS"
$r += "# Fecha: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')   Equipo: $env:COMPUTERNAME (10.0.0.33)"
$r += ""
$r += "== Regla NRPT: la zona del laboratorio se consulta a ns1 =="
$r += (Get-DnsClientNrptRule | Where-Object Comment -eq "Lab5Redes" | Format-Table Namespace, NameServers -AutoSize | Out-String).Trim()
$r += ""
$r += "== Resolucion (Resolve-DnsName) =="
foreach ($h in "ns1", "ldap", "www", "mail", "ftp") {
    $a = Resolve-DnsName "$h.$dominio" -Type A -ErrorAction SilentlyContinue
    $r += "{0,-26} A   {1}" -f "$h.$dominio", ($a.IPAddress -join ", ")
}
$mx = Resolve-DnsName $dominio -Type MX -ErrorAction SilentlyContinue
$r += "{0,-26} MX  {1} {2}" -f $dominio, $mx.Preference, $mx.NameExchange
$r += ""
$r += "== Conexion a cada servicio por nombre =="
$r += Probar-Puerto "ns1.$dominio"  53
$r += Probar-Puerto "ldap.$dominio" 389
$r += Probar-Puerto "www.$dominio"  80
$r += Probar-Puerto "mail.$dominio" 25
$r += Probar-Puerto "mail.$dominio" 587
$r += Probar-Puerto "mail.$dominio" 143
$r += Probar-Puerto "ftp.$dominio"  21
$r += ""
$r += "== HTTP por nombre =="
try {
    $w = Invoke-WebRequest "http://www.$dominio/" -UseBasicParsing
    $r += "GET http://www.$dominio/ -> $($w.StatusCode) $($w.StatusDescription), titulo: " + ([regex]::Match($w.Content, '<title>(.*?)</title>').Groups[1].Value)
} catch { $r += "GET http://www.$dominio/ -> ERROR $($_.Exception.Message)" }
try {
    Invoke-WebRequest "http://www.$dominio/intranet/" -UseBasicParsing | Out-Null
} catch { $r += "GET http://www.$dominio/intranet/ (sin credenciales) -> $([int]$_.Exception.Response.StatusCode) $($_.Exception.Response.StatusDescription)" }

$r | Set-Content -Path $salida -Encoding utf8
$r
