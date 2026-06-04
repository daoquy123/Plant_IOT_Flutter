"""
Trợ lý chat Qwen đơn giản — gọi Ollama (mặc định) hoặc API OpenAI-compatible (DashScope, vLLM, …).

Cài Ollama trên VPS:
  curl -fsSL https://ollama.com/install.sh | sh
  ollama pull qwen2.5:0.5b

Biến môi trường (PM2 / .env):
  QWEN_CHAT_ENABLED=1
  QWEN_PROVIDER=ollama          # ollama | openai
  OLLAMA_BASE_URL=http://127.0.0.1:11434
  QWEN_MODEL=qwen2.5:0.5b
  OPENAI_API_BASE=              # khi QWEN_PROVIDER=openai
  OPENAI_API_KEY=
"""

from __future__ import annotations

import os
from typing import Any

import httpx

from app.ml.labels import CLASS_LABELS_VI, EXPLANATIONS_VI

SYSTEM_PROMPT = """Bạn là trợ lý Smart Garden — tư vấn trồng cải, IoT vườn thông minh (cảm biến, tưới, camera).
Trả lời ngắn gọn, tiếng Việt, thực tế. Không bịa số liệu cảm biến; nếu thiếu dữ liệu thì nói rõ.

Phân loại lá (model ảnh CNN trên app, không phải bạn):
""" + "\n".join(
    f"- {code}: {CLASS_LABELS_VI.get(code, code)} — {EXPLANATIONS_VI.get(code, '')}"
    for code in CLASS_LABELS_VI
) + """

Gợi ý chăm sóc: ẩm đất 45–85%, nhiệt 22–32°C, tưới sáng/chiều, kiểm tra sâu khi thấy vết lá."""


def _env_bool(name: str, default: bool = True) -> bool:
    raw = os.getenv(name, "1" if default else "0").strip().lower()
    return raw in ("1", "true", "yes", "on")


def _max_history() -> int:
    try:
        return max(0, min(24, int(os.getenv("QWEN_MAX_HISTORY", "12"))))
    except ValueError:
        return 12


def _timeout() -> float:
    try:
        return max(10.0, min(300.0, float(os.getenv("QWEN_CHAT_TIMEOUT_SEC", "90"))))
    except ValueError:
        return 90.0


def chat_status() -> dict[str, Any]:
    enabled = _env_bool("QWEN_CHAT_ENABLED", True)
    provider = os.getenv("QWEN_PROVIDER", "ollama").strip().lower() or "ollama"
    model = os.getenv("QWEN_MODEL", "qwen2.5:0.5b").strip() or "qwen2.5:0.5b"
    return {
        "enabled": enabled,
        "provider": provider,
        "model": model,
    }


def _normalize_history(history: list[dict[str, str]] | None) -> list[dict[str, str]]:
    if not history:
        return []
    out: list[dict[str, str]] = []
    for item in history[-_max_history() :]:
        role = (item.get("role") or "").strip().lower()
        content = (item.get("content") or "").strip()
        if role not in ("user", "assistant") or not content:
            continue
        out.append({"role": role, "content": content})
    return out


def _messages_for_api(user_message: str, history: list[dict[str, str]] | None) -> list[dict[str, str]]:
    msgs: list[dict[str, str]] = [{"role": "system", "content": SYSTEM_PROMPT}]
    msgs.extend(_normalize_history(history))
    msgs.append({"role": "user", "content": user_message.strip()})
    return msgs


def _chat_mock(user_message: str) -> str:
    """Trả lời giả lập khi dev local chưa cài Ollama."""
    return (
        f"[Chế độ mock — local test]\n\n"
        f"Bạn hỏi: «{user_message}»\n\n"
        "Để chat Qwen thật: cài Ollama (https://ollama.com), chạy `ollama pull qwen2.5:0.5b`, "
        "đặt QWEN_PROVIDER=ollama rồi khởi động lại API."
    )


def _chat_ollama(messages: list[dict[str, str]]) -> str:
    base = os.getenv("OLLAMA_BASE_URL", "http://127.0.0.1:11434").rstrip("/")
    model = os.getenv("QWEN_MODEL", "qwen2.5:0.5b").strip() or "qwen2.5:0.5b"
    url = f"{base}/api/chat"
    payload = {
        "model": model,
        "messages": messages,
        "stream": False,
        "options": {"temperature": 0.7},
    }
    with httpx.Client(timeout=_timeout()) as client:
        response = client.post(url, json=payload)
        response.raise_for_status()
        data = response.json()
    message = data.get("message") if isinstance(data, dict) else None
    if isinstance(message, dict):
        content = message.get("content")
        if isinstance(content, str) and content.strip():
            return content.strip()
    raise RuntimeError("Ollama trả về không có nội dung. Kiểm tra: ollama pull qwen2.5:0.5b")


def _chat_openai_compatible(messages: list[dict[str, str]]) -> str:
    base = os.getenv("OPENAI_API_BASE", "").strip().rstrip("/")
    api_key = os.getenv("OPENAI_API_KEY", "").strip()
    model = os.getenv("QWEN_MODEL", "qwen-turbo").strip() or "qwen-turbo"
    if not base or not api_key:
        raise RuntimeError(
            "Thiếu OPENAI_API_BASE hoặc OPENAI_API_KEY (DashScope / API tương thích OpenAI)."
        )
    url = f"{base}/chat/completions"
    headers = {"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"}
    payload = {
        "model": model,
        "messages": messages,
        "temperature": 0.7,
    }
    with httpx.Client(timeout=_timeout()) as client:
        response = client.post(url, headers=headers, json=payload)
        response.raise_for_status()
        data = response.json()
    choices = data.get("choices") if isinstance(data, dict) else None
    if isinstance(choices, list) and choices:
        first = choices[0]
        if isinstance(first, dict):
            msg = first.get("message")
            if isinstance(msg, dict):
                content = msg.get("content")
                if isinstance(content, str) and content.strip():
                    return content.strip()
    raise RuntimeError("API chat không trả nội dung hợp lệ.")


def chat_reply(user_message: str, history: list[dict[str, str]] | None = None) -> str:
    if not _env_bool("QWEN_CHAT_ENABLED", True):
        raise RuntimeError("Chat Qwen đang tắt (QWEN_CHAT_ENABLED=0).")

    text = user_message.strip()
    if not text:
        raise ValueError("Tin nhắn trống.")

    messages = _messages_for_api(text, history)
    provider = os.getenv("QWEN_PROVIDER", "ollama").strip().lower() or "ollama"

    try:
        if provider == "mock":
            return _chat_mock(text)
        if provider == "openai":
            return _chat_openai_compatible(messages)
        if provider == "ollama":
            return _chat_ollama(messages)
        raise ValueError(f"QWEN_PROVIDER không hỗ trợ: {provider} (mock | ollama | openai)")
    except httpx.ConnectError as exc:
        if provider == "ollama":
            raise RuntimeError(
                "Không kết nối được Ollama. Trên VPS: cài Ollama và chạy `ollama pull qwen2.5:0.5b`."
            ) from exc
        raise RuntimeError(f"Không kết nối API chat: {exc}") from exc
    except httpx.HTTPStatusError as exc:
        detail = exc.response.text[:500] if exc.response is not None else str(exc)
        raise RuntimeError(f"Lỗi API chat ({exc.response.status_code}): {detail}") from exc
