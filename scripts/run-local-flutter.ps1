# Flutter app — tro den AI local (sua URL trong script neu can).
# Usage: powershell -ExecutionPolicy Bypass -File scripts/run-local-flutter.ps1

$ErrorActionPreference = "Stop"
$AppDir = Join-Path (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)) "Plant_IOT_Flutter-nhan"
Set-Location $AppDir

Write-Host "Chay Smart Garden (Windows). Trong app -> Cai dat:"
Write-Host "  URL AI Server: http://127.0.0.1:8000"
Write-Host "  (Android emulator: http://10.0.2.2:8000)"
Write-Host ""

flutter run -d windows
