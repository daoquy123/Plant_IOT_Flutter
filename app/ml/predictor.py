import logging
import time
from pathlib import Path
from typing import Any

import numpy as np
import tensorflow as tf

from app.logging_setup import configure_ai_logging

configure_ai_logging()
log = logging.getLogger("plant_ai.predict")

from .model_vgg16_cbam import load_trained_model, IMG_SIZE, CLASS_NAMES
from .model_resnet50_cbam import load_trained_model as load_resnet_model
from .labels import EXPLANATIONS_VI, CLASS_LABELS_VI
from .image_io import load_image_rgb_from_bytes

_APP_DIR = Path(__file__).resolve().parent.parent
_DEFAULT_WEIGHTS = _APP_DIR / "checkpoints" / "vgg16_cbam_best.weights.h5"
_DEFAULT_RESNET_WEIGHTS = _APP_DIR / "checkpoints" / "resnet50_best.weights.h5"


class LeafHealthPredictor:
    """Tải model VGG16+CBAM và trả về nhãn + xác suất + giải thích tiếng Việt."""

    def __init__(self, weights_path: str | Path | None = None):
        path = Path(weights_path) if weights_path is not None else _DEFAULT_WEIGHTS
        if not path.is_file():
            legacy = _APP_DIR / "models" / "leaf_vgg16_cbam_best.h5"
            if legacy.is_file():
                path = legacy

        if not path.is_file():
            raise FileNotFoundError(
                f"Chưa có file trọng số. Hãy train: python app/ml/train_vgg16_cbam.py "
                f"(kỳ vọng: {_DEFAULT_WEIGHTS})"
            )

        self.weights_path = str(path)
        self.model = load_trained_model(self.weights_path)

    def preprocess_image(self, file_bytes: bytes) -> tf.Tensor:
        arr = load_image_rgb_from_bytes(file_bytes, IMG_SIZE)
        img = tf.convert_to_tensor(arr, dtype=tf.float32)
        img = tf.expand_dims(img, 0)
        return img

    def predict(self, file_bytes: bytes, *, model_name: str = "vgg16") -> dict[str, Any]:
        t0 = time.perf_counter()
        img_batch = self.preprocess_image(file_bytes)
        preprocess_ms = (time.perf_counter() - t0) * 1000

        t1 = time.perf_counter()
        preds = self.model.predict(img_batch, verbose=0)[0]
        inference_ms = (time.perf_counter() - t1) * 1000

        idx = int(np.argmax(preds))
        prob = float(preds[idx])
        label = CLASS_NAMES[idx]
        raw_probs = {CLASS_NAMES[i]: float(preds[i]) for i in range(len(CLASS_NAMES))}
        top3 = sorted(raw_probs.items(), key=lambda item: item[1], reverse=True)[:3]
        top3_text = ", ".join(f"{name}:{pct * 100:.1f}%" for name, pct in top3)

        log.info(
            "inference model=%s image_bytes=%d preprocess=%.0fms inference=%.0fms "
            "label=%s label_vi=%s confidence=%.1f%% top3=[%s]",
            model_name,
            len(file_bytes),
            preprocess_ms,
            inference_ms,
            label,
            CLASS_LABELS_VI.get(label, label),
            prob * 100,
            top3_text,
        )

        return {
            "label": label,
            "probability": prob,
            "label_vietnamese": CLASS_LABELS_VI.get(label, label),
            "explanation": EXPLANATIONS_VI.get(label, ""),
            "raw_probs": raw_probs,
        }


class MultiModelLeafHealthPredictor:
    """Quản lý nhiều mô hình để cho phép chọn model lúc predict."""

    def __init__(self):
        self._cache: dict[str, LeafHealthPredictor] = {}

    def _create_predictor(self, model_name: str) -> LeafHealthPredictor:
        normalized = model_name.strip().lower()
        if normalized == "vgg16":
            return LeafHealthPredictor(weights_path=_DEFAULT_WEIGHTS)
        if normalized == "resnet":
            predictor = LeafHealthPredictor.__new__(LeafHealthPredictor)
            predictor.weights_path = str(_DEFAULT_RESNET_WEIGHTS)
            if not _DEFAULT_RESNET_WEIGHTS.is_file():
                raise FileNotFoundError(
                    f"Chưa có file trọng số ResNet: {_DEFAULT_RESNET_WEIGHTS}. "
                    "Hãy copy file này lên server."
                )
            predictor.model = load_resnet_model(str(_DEFAULT_RESNET_WEIGHTS), use_cbam=False)
            return predictor
        raise ValueError("Model không hợp lệ. Chỉ hỗ trợ: vgg16, resnet")

    def predict(self, file_bytes: bytes, model_name: str = "vgg16") -> dict[str, Any]:
        normalized = model_name.strip().lower() or "vgg16"
        predictor = self._cache.get(normalized)
        if predictor is None:
            log.info("loading model=%s (cold start)...", normalized)
            t0 = time.perf_counter()
            predictor = self._create_predictor(normalized)
            self._cache[normalized] = predictor
            log.info(
                "model=%s ready in %.0fms weights=%s",
                normalized,
                (time.perf_counter() - t0) * 1000,
                predictor.weights_path,
            )
        result = predictor.predict(file_bytes, model_name=normalized)
        result["model"] = normalized
        return result


_global_predictor: MultiModelLeafHealthPredictor | None = None


def get_predictor() -> MultiModelLeafHealthPredictor:
    global _global_predictor
    if _global_predictor is None:
        _global_predictor = MultiModelLeafHealthPredictor()
    return _global_predictor
