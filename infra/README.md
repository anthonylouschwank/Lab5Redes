# Infraestructura: VM del laboratorio

Todos los servicios corren en **una VM Ubuntu Server 24.04 LTS** en VirtualBox. El Windows anfitrión
actúa como cliente (navegador, Thunderbird y cliente FTP).

| Equipo            | Interfaz                   | IP             | Rol |
|-------------------|----------------------------|----------------|-----|
| VM `srv`          | `enp0s3` (NAT)             | DHCP (10.0.2.15) | Salida a Internet para `apt` |
| VM `srv`          | `enp0s8` (Host-Only)       | `10.0.0.37/27` | ns1, ldap, www, mail, ftp |
| Windows anfitrión | VirtualBox Host-Only #2    | `10.0.0.33/27` | Cliente del laboratorio |

Se usa Ubuntu 24.04 (y no 26.04) porque trae Dovecot 2.3; Dovecot 2.4 cambió la sintaxis de configuración.

## 1. Red Host-Only (Windows, requiere administrador)

VirtualBox → *Archivo → Herramientas → Network Manager → Host-only Networks → Crear*:

- IPv4: `10.0.0.33`, máscara `255.255.255.224`
- Servidor DHCP: **desactivado**

No modificar el adaptador existente `192.168.56.1` (lo usa la GNS3 VM).

## 2. Crear la VM

```powershell
powershell -ExecutionPolicy Bypass -File infra\crear-vm.ps1
```

Crea `Lab5-Hospital`: 2 vCPU, 3 GB RAM, disco de 25 GB, NIC1 NAT y NIC2 Host-Only, con la ISO montada.

## 3. Instalar Ubuntu Server

Valores a usar en el instalador:

| Pantalla            | Valor |
|---------------------|-------|
| Idioma / teclado    | English (o Español) / Spanish (Latin American) |
| Tipo de instalación | Ubuntu Server (no "minimized") |
| Red `enp0s3`        | DHCPv4 (dejar como está) |
| Red `enp0s8`        | *Edit IPv4 → Manual*: subnet `10.0.0.32/27`, address `10.0.0.37`, gateway **vacío**, name servers **vacío** |
| Proxy / mirror      | Dejar por defecto |
| Disco               | Use an entire disk (sin LVM está bien) |
| Perfil              | Nombre del servidor: `srv` · usuario: `lab` · contraseña exclusiva del laboratorio |
| Ubuntu Pro          | Skip |
| SSH                 | **Install OpenSSH server** (sin importar llaves) |
| Snaps               | Ninguno |

Al terminar: *Reboot Now* (si pide quitar el medio, presionar Enter).

## 4. Acceso SSH desde Windows

La llave `~/.ssh/lab5_ed25519` y el alias `lab5` (en `~/.ssh/config`) ya existen en el anfitrión.
Copiar la llave pública a la VM (pide la contraseña de `lab` una sola vez):

```powershell
type $env:USERPROFILE\.ssh\lab5_ed25519.pub | ssh lab@10.0.0.37 "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
```

Para que los scripts de instalación corran sin pedir contraseña de `sudo` (solo en esta VM de laboratorio):

```bash
echo "lab ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/lab5 && sudo chmod 440 /etc/sudoers.d/lab5
```

Prueba: `ssh lab5 hostname` debe responder `srv` sin pedir contraseña.

Zona horaria (para que los logs y evidencias tengan hora local):

```bash
sudo timedatectl set-timezone America/Guatemala
```

## 5. Copiar el repositorio a la VM

Desde Git Bash en Windows (copia también `secrets/`, que no está en GitHub):

```bash
bash infra/sync.sh           # repo -> lab5:~/lab5
bash infra/sync.sh --traer   # evidencias de la VM -> tests/evidencias/
```

## 6. Red persistente

`netplan/60-lab5.yaml` deja la configuración de red en el repositorio. Se instala con:

```bash
sudo cp infra/netplan/60-lab5.yaml /etc/netplan/60-lab5.yaml
sudo rm -f /etc/netplan/50-cloud-init.yaml
sudo chmod 600 /etc/netplan/60-lab5.yaml
sudo netplan apply
```
