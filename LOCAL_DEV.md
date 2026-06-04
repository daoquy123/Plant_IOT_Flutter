# Chạy local để test

## 1. API AI (bắt buộc cho chat + phân loại ảnh)

Mở **terminal 1**:

```powershell
cd D:\Downloads\Plant_IOT_Flutter
powershell -ExecutionPolicy Bypass -File scripts\run-local-ai.ps1
```

Kiểm tra:

```powershell
curl http://127.0.0.1:8000/health
curl -Method POST http://127.0.0.1:8000/api/chat `
  -ContentType "application/json" `
  -Body '{"message":"Nen tuoi cai khi nao?","history":[]}'
```

| URL trong Flutter | Khi nào dùng |
|-------------------|--------------|
| `http://127.0.0.1:8000` | Windows / iOS simulator |
| `http://10.0.2.2:8000` | Android emulator |
| `http://<LAN-IP>:8000` | Điện thoại thật cùng Wi‑Fi |

## 2. Chat Qwen thật (tuỳ chọn)

Script tự dùng **mock** nếu chưa có Ollama.

1. Cài [Ollama](https://ollama.com/download/windows)
2. Terminal mới: `ollama pull qwen2.5:0.5b`
3. Khởi động lại `run-local-ai.ps1` — sẽ chuyển sang `QWEN_PROVIDER=ollama`

Hoặc DashScope (không cần Ollama):

```powershell
$env:QWEN_PROVIDER = "openai"
$env:OPENAI_API_BASE = "https://dashscope.aliyuncs.com/compatible-mode/v1"
$env:OPENAI_API_KEY = "sk-..."
$env:QWEN_MODEL = "qwen-turbo"
.\.venv\Scripts\python.exe -m uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
```

## 3. Flutter app

Mở **terminal 2**:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\run-local-flutter.ps1
```

Trong app → **Cài đặt** → **URL AI Server**: `http://127.0.0.1:8000` → **Lưu**.

Tab **AI**: gõ câu hỏi hoặc gửi ảnh (predict cần file `app/checkpoints/vgg16_cbam_best.weights.h5`).

## 4. Server IoT Node (tuỳ chọn)

Chỉ cần nếu test dashboard / camera / relay local:

```powershell
cd Plant_IOT_Flutter-nhan\server
npm install
npm start
```

Cài đặt app: Server URL `http://127.0.0.1:3000`, API key như trong `server/.env`.
