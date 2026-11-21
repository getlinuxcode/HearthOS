# Démarre l'ISO Hearth dans une VM VirtualBox (UEFI, 8 Go, accélération 3D, disque de 100 Go
# pour essayer l'installateur). Les manettes Sony / Microsoft branchées en USB sont transmises à la VM.
# Limite : pas de Vulkan accéléré en VM → la session passe par cage (OpenGL) au lieu de gamescope.
# Usage : .\scripts\run-vm.ps1 [-Iso out\hearth-xxxx.iso] [-Reset]
param([string]$Iso, [switch]$Reset)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$vbox = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
if (-not (Test-Path $vbox)) { Write-Error "VirtualBox introuvable ($vbox)." }

if (-not $Iso) { $Iso = (Get-ChildItem "$root\out\hearth-*.iso" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName }
if (-not $Iso) { Write-Error "Aucune ISO dans out\. Lancez d'abord scripts\build-iso-vm.ps1." }

$name = 'Hearth'
$vmDir = "$root\vm"
$exists = (& $vbox list vms) -match "`"$name`""
if ($exists -and $Reset) {
  & $vbox controlvm $name poweroff 2>$null
  & $vbox unregistervm $name --delete
  $exists = $false
}

if (-not $exists) {
  & $vbox createvm --name $name --ostype ArchLinux_64 --basefolder $vmDir --register | Out-Null
  & $vbox modifyvm $name --firmware efi --memory 8192 --cpus 4 --vram 256 --graphicscontroller vmsvga `
    --accelerate-3d on --audio-driver default --audio-enabled on --audio-out on --usb-xhci on --nic1 nat --mouse usbtablet
  & $vbox createmedium disk --filename "$vmDir\$name\disk.vdi" --size 102400 | Out-Null
  & $vbox storagectl $name --name SATA --add sata --portcount 2
  & $vbox storageattach $name --storagectl SATA --port 0 --device 0 --type hdd --medium "$vmDir\$name\disk.vdi"
  & $vbox usbfilter add 0 --target $name --name Sony --vendorid 054c
  & $vbox usbfilter add 1 --target $name --name Microsoft --vendorid 045e
}

& $vbox storageattach $name --storagectl SATA --port 1 --device 0 --type dvddrive --medium $Iso
& $vbox startvm $name
