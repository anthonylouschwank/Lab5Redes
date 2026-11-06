# Fase 4 · F6 — Pruebas de la VPN desde la laptop con un túnel WireGuard activo.
# Uso: .\fase4\vpn\prueba-vpn.ps1 -Peer ti|medico
param([ValidateSet('ti','medico')][string]$Peer = 'ti')

function Tcp($ip, $port, $ms = 4000) {
    $c = New-Object Net.Sockets.TcpClient
    try { $ok = $c.ConnectAsync($ip, $port).Wait($ms) -and $c.Connected } catch { $ok = $false } finally { $c.Close() }
    return $ok
}

$esperado = @{
  ti     = @{ '10.0.0.117:22'=$true; '10.0.0.46:22'=$true; '10.0.0.28:22'=$true; '10.0.0.46:80'=$true; '10.0.0.46:389'=$false; '10.0.0.69:22'=$false; '10.0.0.69:80'=$false }
  medico = @{ '10.0.0.117:22'=$false; '10.0.0.46:22'=$false; '10.0.0.28:22'=$false; '10.0.0.46:80'=$true; '10.0.0.46:389'=$false; '10.0.0.69:22'=$false; '10.0.0.69:80'=$false }
}[$Peer]

$dir = (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -like '10.8.0.*' }).IPAddress
"# Prueba VPN peer=$Peer  IP túnel=$dir  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
"destino,esperado,obtenido,resultado"
$fallos = 0
foreach ($k in ($esperado.Keys | Sort-Object)) {
    $ip, $p = $k -split ':'
    $r = Tcp $ip ([int]$p)
    $res = if ($r -eq $esperado[$k]) { 'PASS' } else { 'FAIL'; $fallos++ }
    "{0},{1},{2},{3}" -f $k, ($(if ($esperado[$k]) {'abierto'} else {'bloqueado'})), ($(if ($r) {'abierto'} else {'bloqueado'})), $res
}
if ($esperado['10.0.0.46:80']) {
    $h = curl.exe -s -o NUL -w "%{http_code}" --max-time 8 http://10.0.0.46/
    $i = curl.exe -s -o NUL -w "%{http_code}" --max-time 8 http://10.0.0.46/intranet/
    "http://10.0.0.46/,200,$h,$(if ($h -eq '200') {'PASS'} else {'FAIL'})"
    "http://10.0.0.46/intranet/ (sin credenciales),401,$i,$(if ($i -eq '401') {'PASS'} else {'FAIL'})"
}
"# FAIL: $fallos"
