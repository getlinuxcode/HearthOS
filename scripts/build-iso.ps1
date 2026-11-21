# Construit l'ISO depuis Windows via Docker Desktop (moteur WSL2).
# Usage : .\scripts\build-iso.ps1
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
  Write-Error "Docker n'est pas installé. Installez Docker Desktop (moteur WSL2) puis relancez."
}

Push-Location $root
try {
  npm run build
  # --privileged : mkarchiso a besoin de monter des systèmes de fichiers
  docker run --rm --privileged -v "${root}:/src" archlinux:latest bash /src/os/build.sh
  Write-Host "ISO disponible dans $root\out"
} finally {
  Pop-Location
}
