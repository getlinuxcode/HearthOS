# Lance l'interface console native (Godot) avec le daemon, sous Windows.
# Usage : .\scripts\run-console.ps1            (parcours complet depuis l'allumage)
#         .\scripts\run-console.ps1 -Scene home (directement l'accueil ; aussi : pad, network, overlay)
#         .\scripts\run-console.ps1 -Fullscreen
param([string]$Scene = 'boot', [switch]$Fullscreen)
$root = Split-Path $PSScriptRoot -Parent
$godot = Join-Path $root 'tools\godot\Godot_v4.7.2-stable_win64.exe'
if (-not (Test-Path $godot)) { Write-Error "Godot introuvable : $godot" }

# Daemon (Steam, réseau, ROM, FTP…) s'il ne tourne pas déjà
$up = $false
try { Invoke-RestMethod http://127.0.0.1:7300/api/system/info -TimeoutSec 1 | Out-Null; $up = $true } catch {}
if (-not $up) {
  Start-Process -WindowStyle Minimized -FilePath 'npm.cmd' -ArgumentList 'run', 'dev', '-w', 'daemon' -WorkingDirectory $root
  Start-Sleep 3
}

$args = @('--path', (Join-Path $root 'console'))
if ($Fullscreen) { $args += '--fullscreen' } else { $args += @('--resolution', '1600x900') }
$args += @('--', "--scene=$Scene")
& $godot @args
