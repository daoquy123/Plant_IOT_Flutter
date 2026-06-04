# Chạy FastAPI AI local (chỉ phân loại ảnh /predict).
# Usage: powershell -ExecutionPolicy Bypass -File scripts/run-local-ai.ps1

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $Root

$venvPython = Join-Path $Root ".venv\Scripts\python.exe"
if (-not (Test-Path $venvPython)) {
  python -m venv .venv
  & $venvPython -m pip install --upgrade pip
  & $venvPython -m pip install -r requirements-ai-prod.txt
}

$env:PYTHONUNBUFFERED = "1"
$env:TF_CPP_MIN_LOG_LEVEL = "2"

Write-Host "API: http://127.0.0.1:8000/predict"
& $venvPython -m uvicorn app.main:app --host 127.0.0.1 --port 8000 --reload
