from pathlib import Path

from fastapi import FastAPI, File, Form, HTTPException, Request, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import HTMLResponse, JSONResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from pydantic import BaseModel, Field

from app.chat.qwen_client import chat_reply, chat_status
from app.ml.predictor import get_predictor

_APP_ROOT = Path(__file__).resolve().parent

app = FastAPI(title="Plant AI — Leaf CNN + Qwen Chat")


class ChatHistoryItem(BaseModel):
    role: str = Field(..., description="user hoặc assistant")
    content: str = Field(..., min_length=1, max_length=8000)


class ChatRequest(BaseModel):
    message: str = Field(..., min_length=1, max_length=4000)
    history: list[ChatHistoryItem] = Field(default_factory=list)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

_static_dir = _APP_ROOT / "static"
_templates_dir = _APP_ROOT / "templates"
if _static_dir.is_dir():
    app.mount("/static", StaticFiles(directory=_static_dir), name="static")
templates = (
    Jinja2Templates(directory=str(_templates_dir)) if _templates_dir.is_dir() else None
)


@app.get("/", response_class=HTMLResponse)
async def index(request: Request):
    if templates is None:
        return HTMLResponse(
            "<h1>Plant AI API</h1><p>POST /predict hoặc /api/predict với file ảnh.</p>",
            status_code=200,
        )
    return templates.TemplateResponse("index.html", {"request": request})


async def _predict_image(file: UploadFile, model: str) -> JSONResponse:
    if not file.content_type or not file.content_type.startswith("image/"):
        raise HTTPException(status_code=400, detail="Vui lòng tải lên một file ảnh hợp lệ.")

    contents = await file.read()
    predictor = get_predictor()
    try:
        result = predictor.predict(contents, model_name=model)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    except FileNotFoundError as exc:
        raise HTTPException(status_code=500, detail=str(exc)) from exc

    return JSONResponse(
        {
            "status": "ok",
            "filename": file.filename,
            "model": model,
            "result": result,
        }
    )


@app.post("/api/predict")
async def api_predict(file: UploadFile = File(...), model: str = Form("vgg16")):
    return await _predict_image(file, model)


@app.post("/predict")
async def predict_flutter(file: UploadFile = File(...), model: str = Form("vgg16")):
    """Alias cho Flutter app (Settings → URL AI Server = http://IP:8000)."""
    return await _predict_image(file, model)


async def _chat_json(body: ChatRequest) -> JSONResponse:
    history = []
    for h in body.history:
        role = h.role.strip().lower()
        if role not in ("user", "assistant"):
            raise HTTPException(
                status_code=400,
                detail="history.role phải là user hoặc assistant",
            )
        history.append({"role": role, "content": h.content})
    try:
        reply = chat_reply(body.message, history=history)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    except RuntimeError as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc
    return JSONResponse({"status": "ok", "reply": reply})


@app.post("/api/chat")
async def api_chat(body: ChatRequest):
    """Chat Qwen (Ollama / API tương thích) — Flutter gọi cùng base AI server."""
    return await _chat_json(body)


@app.post("/chat")
async def chat_flutter(body: ChatRequest):
    """Alias cho Flutter: {aiServerUrl}/chat."""
    return await _chat_json(body)


@app.get("/api/health")
@app.get("/health")
async def health_check():
    return {"status": "ok", "service": "plant-ai", "qwen_chat": chat_status()}


if __name__ == "__main__":
    import uvicorn

    uvicorn.run("app.main:app", host="0.0.0.0", port=8000, reload=True)
