import logging
import os
import sys

_CONFIGURED = False


def configure_ai_logging() -> None:
    """Ghi log ra stdout để PM2 gom vào plant-ai-out.log (cùng dòng với uvicorn)."""
    global _CONFIGURED
    if _CONFIGURED:
        return

    level_name = os.getenv("AI_LOG_LEVEL", "INFO").upper()
    level = getattr(logging, level_name, logging.INFO)
    fmt = logging.Formatter(
        "%(asctime)s %(levelname)s [plant-ai] %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
    )
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(fmt)

    for name in ("plant_ai", "plant_ai.predict"):
        logger = logging.getLogger(name)
        logger.setLevel(level)
        logger.handlers.clear()
        logger.addHandler(handler)
        logger.propagate = False

    _CONFIGURED = True
