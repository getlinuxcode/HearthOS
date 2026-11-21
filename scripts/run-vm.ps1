# Démarre l'ISO dans une VM VirtualBox (UEFI, 8 Go, disque de 100 Go pour tester l'installateur).
# VirtualBox est choisi pour sa redirection USB : on peut y brancher la manette.
# Limite : pas de Vulkan accéléré en VM → gamescope ne démarre pas, la session bascule sur cage.
# Usage : .\scripts\run-vm.ps1 [-Iso out\hearth-xxxx.iso] [-Reset]
param([string]$Iso, [switch]$Reset)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$vbox = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
if (-not (Test-Path $vbox)) { Write-Error "VirtualBox introuvable ($vbox). Installez-le depuis virtualbox.org." }

if (-not $Iso) { $Iso = (Get-ChildItem "$root\out\*.iso" | Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName }
if (-not $Iso) { Write-Error "Aucune ISO dans out\. Lancez d'abord scripts\build-iso.ps1." }

$name = 'Hearth-dev'
$vmDir = "$root\vm"
New-Item -ItemType Directory -Force $vmDir | Out-Null
$exists = (& $vbox list vms) -match "`"$name`""

if ($exists -and $Reset) {
  & $vbox unregistervm $name --delete
  $exists = $false
}

if (-not $exists) {
  & $vbox createvm --name $name --ostype ArchLinux_64 --basefolder $vmDir --register
  & $vbox modifyvm $name --firmware efi --memory 8192 --cpus 4 --vram 256 --graphicscontroller vmsvga `
    --audio-driver default --audio-enabled on --usb-xhci on --nic1 nat --mouse usbtablet
  & $vbox createmedium disk --filename "$vmDir\$name\disk.vdi" --size 102400
  & $vbox storagectl $name --name SATA --add sata --portcount 2
  & $vbox storageattach $name --storagectl SATA --port 0 --device 0 --type hdd --medium "$vmDir\$name\disk.vdi"
  # Filtres USB pour brancher automatiquement les manettes Sony / Microsoft dans la VM
  & $vbox usbfilter add 0 --target $name --name Sony --vendorid 054c
  & $vbox usbfilter add 1 --target $name --name Microsoft --vendorid 045e
}

& $vbox storageattach $name --storagectl SATA --port 1 --device 0 --type dvddrive --medium $Iso
& $vbox startvm $name
