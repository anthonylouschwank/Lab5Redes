# Crea la VM del laboratorio en VirtualBox (Windows anfitrión).
# Requisito previo: red Host-Only creada con IP 10.0.0.33 / 255.255.255.224 y DHCP desactivado.
# Uso: powershell -ExecutionPolicy Bypass -File infra\crear-vm.ps1 [-Iso <ruta>]

param(
    [string]$Iso = "$env:USERPROFILE\VirtualBox VMs\ISOs\ubuntu-24.04.5-live-server-amd64.iso",
    [string]$Nombre = "Lab5-Hospital",
    [int]$Cpus = 2,
    [int]$MemoriaMB = 3072,
    [int]$DiscoMB = 25600
)

$ErrorActionPreference = "Stop"
$vbox = "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe"

if (-not (Test-Path $Iso)) { throw "No se encontró la ISO: $Iso" }

# Adaptador Host-Only con la IP del gateway del laboratorio (10.0.0.33)
$hostOnly = Get-NetIPAddress -AddressFamily IPv4 -IPAddress 10.0.0.33 -ErrorAction SilentlyContinue |
    ForEach-Object { (Get-NetAdapter -InterfaceIndex $_.InterfaceIndex).InterfaceDescription }
if (-not $hostOnly) {
    throw "No existe un adaptador Host-Only con IP 10.0.0.33. Créalo en VirtualBox > Herramientas > Network Manager."
}
Write-Host "Adaptador Host-Only: $hostOnly"

if ((& $vbox list vms) -match "`"$Nombre`"") { throw "La VM '$Nombre' ya existe." }

& $vbox createvm --name $Nombre --ostype Ubuntu_64 --register
$carpeta = Split-Path (& $vbox showvminfo $Nombre --machinereadable |
    Select-String '^CfgFile=' | ForEach-Object { $_.Line.Split('"')[1] })

& $vbox modifyvm $Nombre --cpus $Cpus --memory $MemoriaMB --vram 16 `
    --graphicscontroller vmsvga --audio-enabled off --rtc-use-utc on `
    --boot1 dvd --boot2 disk --boot3 none --boot4 none `
    --nic1 nat `
    --nic2 hostonly --hostonlyadapter2 "$hostOnly"

$disco = Join-Path $carpeta "$Nombre.vdi"
& $vbox createmedium disk --filename $disco --size $DiscoMB --format VDI
& $vbox storagectl $Nombre --name SATA --add sata --controller IntelAhci --portcount 2
& $vbox storageattach $Nombre --storagectl SATA --port 0 --device 0 --type hdd --medium $disco
& $vbox storageattach $Nombre --storagectl SATA --port 1 --device 0 --type dvddrive --medium $Iso

Write-Host "VM '$Nombre' creada. Iníciala desde VirtualBox para instalar Ubuntu."
