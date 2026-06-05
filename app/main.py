import logging
import os
import time
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI, File, Form, HTTPException, Request, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import HTMLResponse, JSONResponse
from fastapi.staticfiles import StaticFiles

from app.logging_setup import configure_ai_logging
from app.ml.predictor import get_predictor

configure_ai_logging()

_APP_ROOT = Path(__file__).resolve().parent
log = logging.getLogger("plant_ai")


def _client_ip(request: Request) -> str:
    forwarded = (request.headers.get("x-forwarded-for") or "").split(",")[0].strip()
    if forwarded:
        return forwarded
    if request.client and request.client.host:
        return request.client.host
    return "unknown"


@asynccontextmanager
async def lifespan(_app: FastAPI):
    configure_ai_logging()
    log.info("service started — log_level=%s", os.getenv("AI_LOG_LEVEL", "INFO"))
    yield
    log.info("service stopped")


app = FastAPI(title="Leaf Health AI - VGG16 + CBAM", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

_static_dir = _APP_ROOT / "static"
if _static_dir.is_dir():
    app.mount("/static", StaticFiles(directory=_static_dir), name="static")


@app.get("/", response_class=HTMLResponse)
async def index(_request: Request):
    return HTMLResponse(
        "<h1>Plant AI API</h1>"
        "<p>POST <code>/predict</code> hoặc <code>/api/predict</code> "
        "với file ảnh và <code>model=vgg16|resnet</code>.</p>"
        "<p>GET <code>/health</code> — kiểm tra service.</p>",
        status_code=200,
    )


async def _predict_image(request: Request, file: UploadFile, model: str) -> JSONResponse:
    client = _client_ip(request)
    model_name = (model or "vgg16").strip().lower() or "vgg16"
    t0 = time.perf_counter()

    if not file.content_type or not file.content_type.startswith("image/"):
        log.warning(
            "rejected client=%s model=%s filename=%s reason=invalid_content_type type=%s",
            client,
            model_name,
            file.filename,
            file.content_type,
        )
        raise HTTPException(status_code=400, detail="Vui lòng tải lên một file ảnh hợp lệ.")

    contents = await file.read()
    log.info(
        "request client=%s model=%s filename=%s bytes=%d content_type=%s",
        client,
        model_name,
        file.filename,
        len(contents),
        file.content_type,
    )

    predictor = get_predictor()
    try:
        result = predictor.predict(contents, model_name=model_name)
    except ValueError as exc:
        log.warning(
            "failed client=%s model=%s elapsed=%.0fms error=%s",
            client,
            model_name,
            (time.perf_counter() - t0) * 1000,
            exc,
        )
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    except FileNotFoundError as exc:
        log.error(
            "failed client=%s model=%s elapsed=%.0fms error=%s",
            client,
            model_name,
            (time.perf_counter() - t0) * 1000,
            exc,
        )
        raise HTTPException(status_code=500, detail=str(exc)) from exc
    except Exception as exc:
        log.exception(
            "failed client=%s model=%s elapsed=%.0fms",
            client,
            model_name,
            (time.perf_counter() - t0) * 1000,
        )
        raise HTTPException(status_code=500, detail="Lỗi xử lý ảnh trên AI server.") from exc

    elapsed_ms = (time.perf_counter() - t0) * 1000
    log.info(
        "completed client=%s model=%s label=%s confidence=%.1f%% total=%.0fms",
        client,
        model_name,
        result.get("label"),
        float(result.get("probability", 0)) * 100,
        elapsed_ms,
    )

    return JSONResponse(
        {
            "status": "ok",
            "filename": file.filename,
            "model": model_name,
            "result": result,
        }
    )


@app.post("/api/predict")
async def api_predict(
    request: Request,
    file: UploadFile = File(...),
    model: str = Form("vgg16"),
):
    return await _predict_image(request, file, model)


@app.post("/predict")
async def predict_flutter(
    request: Request,
    file: UploadFile = File(...),
    model: str = Form("vgg16"),
):
    """Alias cho Flutter app (Settings → URL AI Server = http://IP:8000)."""
    return await _predict_image(request, file, model)


@app.get("/api/health")
@app.get("/health")
async def health_check():
    return {"status": "ok", "service": "plant-ai"}


if __name__ == "__main__":
    import uvicorn

    uvicorn.run("app.main:app", host="0.0.0.0", port=8000, reload=True)
