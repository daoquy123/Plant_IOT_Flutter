# Chạy FastAPI AI local (predict + chat). Mặc định chat mock nếu chưa có Ollama.
# Usage:  powershell -ExecutionPolicy Bypass -File scripts/run-local-ai.ps1

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $Root

$venvPython = Join-Path $Root ".venv\Scripts\python.exe"
if (-not (Test-Path $venvPython)) {
    Write-Host "[1/3] Tao venv..."
    python -m venv .venv
    & $venvPython -m pip install --upgrade pip
    & $venvPython -m pip install -r requirements-ai-prod.txt
} else {
    Write-Host "[1/3] Venv co san."
}

# Chat: mock neu chua co ollama; nguoc lai dung ollama
$ollamaOk = $false
try {
    $null = Get-Command ollama -ErrorAction Stop
    $tags = ollama list 2>$null
    if ($LASTEXITCODE -eq 0) { $ollamaOk = $true }
} catch {}

if ($ollamaOk) {
    $env:QWEN_PROVIDER = "ollama"
    $env:OLLAMA_BASE_URL = "http://127.0.0.1:11434"
    $env:QWEN_MODEL = "qwen2.5:0.5b"
    Write-Host "[2/3] Chat: Ollama ($($env:QWEN_MODEL))"
} else {
    $env:QWEN_PROVIDER = "mock"
    Write-Host "[2/3] Chat: MOCK (cai Ollama de dung Qwen that)"
}

$env:QWEN_CHAT_ENABLED = "1"
$env:PYTHONUNBUFFERED = "1"
$env:TF_CPP_MIN_LOG_LEVEL = "2"

Write-Host "[3/3] API: http://127.0.0.1:8000  |  health: /health  |  chat: POST /api/chat"
Write-Host "Flutter Cai dat -> URL AI Server: http://127.0.0.1:8000"
Write-Host "Windows desktop: http://127.0.0.1:8000  |  Android emulator: http://10.0.2.2:8000"
Write-Host ""

& $venvPython -m uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
