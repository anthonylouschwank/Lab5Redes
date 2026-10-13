# Cambia la tarjeta 2 de la VM (enp0s8, la de los servicios) entre:
#   bridged  -> conectada a la red Wi-Fi real (exposicion: los demas equipos llegan al servidor)
#   hostonly -> red privada 10.0.0.32/27 solo con este equipo (desarrollo)
# Funciona con la VM encendida o apagada. Despues, en la VM: sudo bash infra/cambiar-ip.sh <IP/prefijo>
#
# Uso: powershell -ExecutionPolicy Bypass -File infra\modo-red.ps1 -Modo bridged [-Adaptador "<nombre>"]
#      powershell -ExecutionPolicy Bypass -File infra\modo-red.ps1 -Modo hostonly

param(
    [Parameter(Mandatory)][ValidateSet("bridged", "hostonly")][string]$Modo,
    [string]$Adaptador,
    [string]$Nombre = "Lab5-Hospital"
)

$ErrorActionPreference = "Stop"
$vbox = "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe"

if ($Modo -eq "bridged") {
    if (-not $Adaptador) {
        # Adaptador Wi-Fi conectado. Con Wi-Fi, VirtualBox hace que la VM salga con la MAC del equipo.
        $Adaptador = (Get-NetAdapter -Physical | Where-Object { $_.Status -eq "Up" -and $_.MediaType -eq "Native 802.11" } |
            Select-Object -First 1).InterfaceDescription
    }
    if (-not $Adaptador) { throw "No hay un adaptador Wi-Fi conectado. Use -Adaptador con un nombre de: VBoxManage list bridgedifs" }
} else {
    $Adaptador = Get-NetIPAddress -AddressFamily IPv4 -IPAddress 10.0.0.33 -ErrorAction SilentlyContinue |
        ForEach-Object { (Get-NetAdapter -InterfaceIndex $_.InterfaceIndex).InterfaceDescription }
    if (-not $Adaptador) { throw "No existe el adaptador Host-Only con IP 10.0.0.33 (ver infra\README.md)." }
}

$estado = (& $vbox showvminfo $Nombre --machinereadable | Select-String '^VMState=').Line.Split('"')[1]
if ($estado -eq "running") {
    & $vbox controlvm $Nombre nic2 $Modo "$Adaptador"
} elseif ($Modo -eq "bridged") {
    & $vbox modifyvm $Nombre --nic2 bridged --bridgeadapter2 "$Adaptador"
} else {
    & $vbox modifyvm $Nombre --nic2 hostonly --hostonlyadapter2 "$Adaptador"
}

Write-Host "Tarjeta 2 de '$Nombre' en modo $Modo sobre: $Adaptador"
& $vbox showvminfo $Nombre --machinereadable | Select-String '^(nic2|bridgeadapter2|hostonlyadapter2)='
