import math
import os
import random
import argparse
from pathlib import Path
import numpy as np
import tensorflow as tf

from model_vgg16_cbam import build_vgg16_cbam_model, IMG_SIZE, CLASS_NAMES
from tf_perf import configure_training_runtime, with_data_perf_options
from reporting import save_training_history
from image_io import load_image_rgb_from_path


# ========= CẤU HÌNH CƠ BẢN =========
# dataset/train và dataset/val — mỗi lớp một thư mục con:
#   la_khoe, la_vang, la_sau, sau, co
PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
# dataset nằm ngoài thư mục PROJECT_ROOT một cấp
DATA_ROOT = os.path.abspath(os.path.join(PROJECT_ROOT, "..", "dataset"))

TRAIN_DIR = os.path.join(DATA_ROOT, "train")
VAL_DIR = os.path.join(DATA_ROOT, "val")

BATCH_SIZE = 32
EPOCHS_STAGE1 = 30
EPOCHS_STAGE2 = 20
AUTOTUNE = tf.data.AUTOTUNE
VAL_SPLIT = 0.2
SPLIT_SEED = 123
IMAGE_EXTS = {".jpg", ".jpeg", ".png", ".bmp", ".gif", ".webp", ".tif", ".tiff", ".heic", ".heif"}

# Nơi lưu trọng số/best model
CHECKPOINT_DIR = os.path.join(PROJECT_ROOT, "checkpoints")
os.makedirs(CHECKPOINT_DIR, exist_ok=True)
BEST_WEIGHTS_PATH = os.path.join(CHECKPOINT_DIR, "vgg16_cbam_best.weights.h5")
HISTORY_JSON_PATH = os.path.join(CHECKPOINT_DIR, "training_history.json")

# Ưu tiên "không bỏ sót sâu": phạt mạnh lỗi la_sau -> la_khoe
LA_KHOE_IDX = CLASS_NAMES.index("la_khoe")
LA_SAU_IDX = CLASS_NAMES.index("la_sau")


class _ClassSpecificBase(tf.keras.metrics.Metric):
    """Metric TP/FP/FN cho 1 lớp cụ thể (không dùng confusion-matrix nội bộ của Keras)."""

    def __init__(self, class_id: int, name: str, dtype=tf.float32):
        super().__init__(name=name, dtype=dtype)
        self.class_id = int(class_id)
        self.eps = tf.constant(1e-8, dtype=dtype)

    def _to_label(self, y_pred: tf.Tensor) -> tf.Tensor:
        # Model output: softmax probabilities [B, C]
        return tf.argmax(y_pred, axis=-1, output_type=tf.int32)

    def _to_true(self, y_true: tf.Tensor) -> tf.Tensor:
        return tf.cast(tf.reshape(y_true, [-1]), tf.int32)


class RecallLaSau(_ClassSpecificBase):
    """Recall cho lớp la_sau: TP/(TP+FN)."""

    def __init__(self, class_id: int, name: str = "recall_la_sau"):
        super().__init__(class_id=class_id, name=name)
        self.tp = self.add_weight(name="tp", initializer="zeros")
        self.fn = self.add_weight(name="fn", initializer="zeros")

    def update_state(self, y_true: tf.Tensor, y_pred: tf.Tensor, sample_weight=None):
        y_t = self._to_true(y_true)
        y_p = self._to_label(y_pred)
        # TP: đúng la_sau; FN: la_sau nhưng dự đoán != la_sau
        tp_mask = tf.logical_and(tf.equal(y_t, self.class_id), tf.equal(y_p, self.class_id))
        fn_mask = tf.logical_and(tf.equal(y_t, self.class_id), tf.not_equal(y_p, self.class_id))
        tp = tf.reduce_sum(tf.cast(tp_mask, self.dtype))
        fn = tf.reduce_sum(tf.cast(fn_mask, self.dtype))
        self.tp.assign_add(tp)
        self.fn.assign_add(fn)

    def result(self):
        return self.tp / (self.tp + self.fn + self.eps)

    def reset_state(self):
        self.tp.assign(0.0)
        self.fn.assign(0.0)


class PrecisionLaSau(_ClassSpecificBase):
    """Precision cho lớp la_sau: TP/(TP+FP)."""

    def __init__(self, class_id: int, name: str = "precision_la_sau"):
        super().__init__(class_id=class_id, name=name)
        self.tp = self.add_weight(name="tp", initializer="zeros")
        self.fp = self.add_weight(name="fp", initializer="zeros")

    def update_state(self, y_true: tf.Tensor, y_pred: tf.Tensor, sample_weight=None):
        y_t = self._to_true(y_true)
        y_p = self._to_label(y_pred)
        # TP: dự đoán la_sau và đúng la_sau; FP: dự đoán la_sau nhưng true != la_sau
        tp_mask = tf.logical_and(tf.equal(y_t, self.class_id), tf.equal(y_p, self.class_id))
        fp_mask = tf.logical_and(tf.not_equal(y_t, self.class_id), tf.equal(y_p, self.class_id))
        tp = tf.reduce_sum(tf.cast(tp_mask, self.dtype))
        fp = tf.reduce_sum(tf.cast(fp_mask, self.dtype))
        self.tp.assign_add(tp)
        self.fp.assign_add(fp)

    def result(self):
        return self.tp / (self.tp + self.fp + self.eps)

    def reset_state(self):
        self.tp.assign(0.0)
        self.fp.assign(0.0)


def _augment_train_batch(images: tf.Tensor, labels: tf.Tensor) -> tuple[tf.Tensor, tf.Tensor]:
    """Augmentation nhẹ cho train để giảm overfit và tăng robust."""
    x = tf.cast(images, tf.float32)
    x = tf.image.random_flip_left_right(x)
    x = tf.image.random_brightness(x, max_delta=0.08)
    x = tf.image.random_contrast(x, lower=0.9, upper=1.1)
    x = tf.clip_by_value(x, 0.0, 255.0)
    return x, labels


def _build_cost_matrix() -> tf.Tensor:
    """
    Ma trận chi phí cho loss có trọng số theo cặp nhầm lẫn.
    - Đúng lớp: cost = 1.0
    - la_sau -> la_khoe: phạt mạnh hơn để tăng recall lớp la_sau
    - la_khoe -> la_sau: phạt nhẹ hơn vì bài toán ưu tiên cảnh báo sớm
    """
    n = len(CLASS_NAMES)
    matrix = np.ones((n, n), dtype=np.float32)
    np.fill_diagonal(matrix, 1.0)
    matrix[LA_SAU_IDX, LA_KHOE_IDX] = 3.0
    matrix[LA_KHOE_IDX, LA_SAU_IDX] = 1.3
    return tf.constant(matrix, dtype=tf.float32)


def _make_cost_sensitive_loss(cost_matrix: tf.Tensor):
    """
    Loss = sparse CCE * expected_cost.
    expected_cost được tính mềm theo phân phối dự đoán để gradient ổn định:
        expected_cost = sum_j cost[y_true, j] * p_j
    """
    base_loss = tf.keras.losses.SparseCategoricalCrossentropy(
        reduction=tf.keras.losses.Reduction.NONE
    )

    def loss_fn(y_true: tf.Tensor, y_pred: tf.Tensor) -> tf.Tensor:
        y_true = tf.cast(tf.reshape(y_true, [-1]), tf.int32)
        ce = base_loss(y_true, y_pred)
        row_costs = tf.gather(cost_matrix, y_true)  # [B, C]
        expected_cost = tf.reduce_sum(row_costs * y_pred, axis=-1)  # [B]
        return ce * expected_cost

    return loss_fn


def _count_train_images_per_class() -> dict[int, int]:
    counts: dict[int, int] = {}
    for idx, cls_name in enumerate(CLASS_NAMES):
        cls_dir = Path(TRAIN_DIR) / cls_name
        if not cls_dir.is_dir():
            counts[idx] = 0
            continue
        counts[idx] = sum(1 for p in cls_dir.rglob("*") if p.is_file() and p.suffix.lower() in IMAGE_EXTS)
    return counts


def _compute_class_weight(class_counts: dict[int, int]) -> dict[int, float]:
    """
    Balanced class weight: N / (K * n_c).
    Nếu lớp không có ảnh -> weight 0 để tránh chia 0.
    """
    total = sum(class_counts.values())
    num_classes = len(CLASS_NAMES)
    weights: dict[int, float] = {}
    for c, n in class_counts.items():
        if n <= 0:
            weights[c] = 0.0
        else:
            weights[c] = float(total) / float(num_classes * n)
    return weights


def _decode_resize(path: tf.Tensor, label: tf.Tensor) -> tuple[tf.Tensor, tf.Tensor]:
    """
    Decode ảnh bằng PIL để hỗ trợ nhiều định dạng (jpg/png/tif/webp/heic nếu có decoder),
    sau đó resize về IMG_SIZE.
    """
    def _load_with_pil(p: tf.Tensor) -> np.ndarray:
        p_str = p.numpy().decode("utf-8")
        return load_image_rgb_from_path(p_str, IMG_SIZE)

    img = tf.py_function(_load_with_pil, [path], Tout=tf.float32)
    img.set_shape((IMG_SIZE[0], IMG_SIZE[1], 3))
    return img, label


def _build_dataset_from_paths(paths: list[str], labels: list[int], shuffle: bool) -> tf.data.Dataset:
    ds = tf.data.Dataset.from_tensor_slices((paths, labels))
    if shuffle:
        # Dùng seed cố định để tái lập.
        ds = ds.shuffle(buffer_size=max(len(paths), 1), seed=SPLIT_SEED, reshuffle_each_iteration=True)
    ds = ds.map(_decode_resize, num_parallel_calls=AUTOTUNE)
    # Bỏ qua file ảnh lỗi/hỏng còn sót lại để không crash toàn bộ quá trình train.
    ds = ds.ignore_errors()
    ds = ds.batch(BATCH_SIZE)
    if shuffle:
        ds = ds.map(_augment_train_batch, num_parallel_calls=AUTOTUNE)
    return ds


def _collect_paths_from_split(split_dir: str) -> tuple[list[str], list[int], dict[int, int]]:
    """
    Quét ảnh theo CLASS_NAMES trong một split dir (train/val).
    Trả về: paths, labels, class_counts.
    """
    paths: list[str] = []
    labels: list[int] = []
    counts: dict[int, int] = {i: 0 for i in range(len(CLASS_NAMES))}

    for label, cls_name in enumerate(CLASS_NAMES):
        cls_dir = Path(split_dir) / cls_name
        if not cls_dir.is_dir():
            continue
        files = [str(p) for p in cls_dir.rglob("*") if p.is_file() and p.suffix.lower() in IMAGE_EXTS]
        counts[label] = len(files)
        paths.extend(files)
        labels.extend([label] * len(files))
    return paths, labels, counts


def _stratified_split_from_train_dir() -> tuple[tf.data.Dataset, tf.data.Dataset]:
    """
    Tách train/val theo từng lớp để đảm bảo lớp hiếm (vd. la_vang) luôn có mặt ở validation.
    """
    rng = random.Random(SPLIT_SEED)
    train_paths: list[str] = []
    train_labels: list[int] = []
    val_paths: list[str] = []
    val_labels: list[int] = []

    for label, cls_name in enumerate(CLASS_NAMES):
        cls_dir = Path(TRAIN_DIR) / cls_name
        files = [str(p) for p in cls_dir.rglob("*") if p.is_file() and p.suffix.lower() in IMAGE_EXTS]
        rng.shuffle(files)
        n_total = len(files)
        if n_total == 0:
            continue
        n_val = int(math.ceil(n_total * VAL_SPLIT))
        # Tránh rơi vào val rỗng hoặc train rỗng khi lớp có ít ảnh.
        n_val = min(max(1, n_val), max(1, n_total - 1)) if n_total > 1 else 1
        cls_val = files[:n_val]
        cls_train = files[n_val:] if n_total > 1 else files

        val_paths.extend(cls_val)
        val_labels.extend([label] * len(cls_val))
        train_paths.extend(cls_train)
        train_labels.extend([label] * len(cls_train))

    train_ds = _build_dataset_from_paths(train_paths, train_labels, shuffle=True)
    val_ds = _build_dataset_from_paths(val_paths, val_labels, shuffle=False)
    print(f"Stratified split từ TRAIN_DIR: train={len(train_paths)} ảnh, val={len(val_paths)} ảnh")
    return train_ds, val_ds


def load_datasets() -> tuple[tf.data.Dataset, tf.data.Dataset, dict[int, float]]:
    """
    Tạo tf.data.Dataset từ thư mục.
    Trả về: train_ds, val_ds, class_weight.
    """
    print(f"Đang load dữ liệu từ:\n  TRAIN_DIR = {TRAIN_DIR}\n  VAL_DIR   = {VAL_DIR}")

    train_paths_all, train_labels_all, train_class_counts = _collect_paths_from_split(TRAIN_DIR)
    class_weight = _compute_class_weight(train_class_counts)
    print("Số ảnh train theo lớp:", {CLASS_NAMES[k]: v for k, v in train_class_counts.items()})
    print("Class weight:", {CLASS_NAMES[k]: round(v, 3) for k, v in class_weight.items()})

    # Dùng pipeline quét đường dẫn + PIL decode để hỗ trợ nhiều định dạng hơn
    # (bao gồm HEIC/HEIF nếu môi trường có decoder tương ứng).
    val_paths_all, val_labels_all, _ = _collect_paths_from_split(VAL_DIR)

    shuffle_buf = 4096
    if len(val_paths_all) > 0 and len(train_paths_all) > 0:
        train_ds = _build_dataset_from_paths(train_paths_all, train_labels_all, shuffle=True)
        val_ds = _build_dataset_from_paths(val_paths_all, val_labels_all, shuffle=False)
        print(f"Dùng trực tiếp TRAIN_DIR/VAL_DIR: train={len(train_paths_all)} ảnh, val={len(val_paths_all)} ảnh")
        shuffle_buf = min(8192, max(1024, len(train_paths_all)))
    else:
        # Nếu VAL_DIR trống hoặc không có ảnh hợp lệ,
        # fallback: tách validation theo từng lớp từ TRAIN_DIR.
        print(
            "Không tìm thấy ảnh trong VAL_DIR, tự động tách validation theo lớp "
            f"({int(VAL_SPLIT * 100)}%) từ TRAIN_DIR."
        )
        train_ds, val_ds = _stratified_split_from_train_dir()

    train_ds = with_data_perf_options(train_ds)
    val_ds = with_data_perf_options(val_ds)
    train_ds = train_ds.cache().shuffle(shuffle_buf, seed=SPLIT_SEED).prefetch(buffer_size=AUTOTUNE)
    val_ds = val_ds.cache().prefetch(buffer_size=AUTOTUNE)

    return train_ds, val_ds, class_weight


def _set_global_seed(seed: int) -> None:
    """Đồng bộ seed cho Python/NumPy/TensorFlow để tăng khả năng tái lập."""
    global SPLIT_SEED
    SPLIT_SEED = int(seed)
    random.seed(SPLIT_SEED)
    np.random.seed(SPLIT_SEED)
    tf.random.set_seed(SPLIT_SEED)


def train(
    seed: int = 123,
    batch_size: int | None = None,
    mixed_precision: bool = True,
    xla: bool = True,
):
    global BATCH_SIZE
    if batch_size is not None:
        BATCH_SIZE = max(1, int(batch_size))
    _set_global_seed(seed)
    print(f"[SEED] SPLIT_SEED={SPLIT_SEED}")
    perf = configure_training_runtime(mixed_precision=mixed_precision, xla=xla)
    print(
        "[PERF] "
        f"physical_gpus={perf['physical_gpus']}, "
        f"mixed_float16={perf['mixed_float16']}, "
        f"xla_jit={perf['xla_jit']}"
    )
    print(f"[PERF] devices: {perf['devices_preview']}")
    train_ds, val_ds, class_weight = load_datasets()

    model = build_vgg16_cbam_model()
    cost_matrix = _build_cost_matrix()
    cost_sensitive_loss = _make_cost_sensitive_loss(cost_matrix)
    model.compile(
        optimizer=tf.keras.optimizers.Adam(1e-4),
        loss=cost_sensitive_loss,
        metrics=[
            "accuracy",
            RecallLaSau(class_id=LA_SAU_IDX, name="recall_la_sau"),
            PrecisionLaSau(class_id=LA_SAU_IDX, name="precision_la_sau"),
        ],
    )
    model.summary()

    # Callback: early stopping + lưu best weights
    early_stopping = tf.keras.callbacks.EarlyStopping(
        monitor="val_loss",
        patience=5,
        restore_best_weights=True,
    )

    checkpoint = tf.keras.callbacks.ModelCheckpoint(
        BEST_WEIGHTS_PATH,
        monitor="val_recall_la_sau",
        save_best_only=True,
        save_weights_only=True,
        mode="max",
        verbose=1,
    )

    reduce_lr = tf.keras.callbacks.ReduceLROnPlateau(
        monitor="val_loss",
        factor=0.5,
        patience=3,
        min_lr=1e-6,
        verbose=1,
    )

    print(f"\n=== Stage 1: train head với VGG16 frozen ({EPOCHS_STAGE1} epochs) ===")
    history_stage1 = model.fit(
        train_ds,
        validation_data=val_ds,
        epochs=EPOCHS_STAGE1,
        callbacks=[early_stopping, checkpoint, reduce_lr],
        class_weight=class_weight,
    )

    # Stage 2: fine-tune block cuối VGG16 với LR thấp để cải thiện biên giữa la_khoe/la_sau.
    print(f"\n=== Stage 2: fine-tune block5 VGG16 ({EPOCHS_STAGE2} epochs) ===")
    vgg_layer = next((l for l in model.layers if "vgg" in l.name.lower()), None)
    if vgg_layer is not None:
        for layer in vgg_layer.layers:
            layer.trainable = layer.name.startswith("block5")
    model.compile(
        optimizer=tf.keras.optimizers.Adam(2e-5),
        loss=cost_sensitive_loss,
        metrics=[
            "accuracy",
            RecallLaSau(class_id=LA_SAU_IDX, name="recall_la_sau"),
            PrecisionLaSau(class_id=LA_SAU_IDX, name="precision_la_sau"),
        ],
    )

    fine_tune_start = len(history_stage1.history.get("loss", []))
    history_stage2 = model.fit(
        train_ds,
        validation_data=val_ds,
        epochs=fine_tune_start + EPOCHS_STAGE2,
        initial_epoch=fine_tune_start,
        callbacks=[early_stopping, checkpoint, reduce_lr],
        class_weight=class_weight,
    )

    # Gộp history của 2 stage để notebook vẽ đủ timeline.
    merged_history: dict[str, list[float]] = {}
    for k, v in history_stage1.history.items():
        merged_history[k] = list(v)
    for k, v in history_stage2.history.items():
        merged_history.setdefault(k, [])
        if len(merged_history[k]) < fine_tune_start:
            merged_history[k].extend([float("nan")] * (fine_tune_start - len(merged_history[k])))
        merged_history[k].extend(list(v))
    history = tf.keras.callbacks.History()
    history.history = merged_history

    save_training_history(history, HISTORY_JSON_PATH)
    print(f"Đã lưu biểu đồ huấn luyện (raw): {HISTORY_JSON_PATH}")

    # File .keras có thể lỗi với Lambda layer — chỉ thử lưu khi cần
    saved_model_path = os.path.join(PROJECT_ROOT, "saved_models", "vgg16_cbam.keras")
    os.makedirs(os.path.dirname(saved_model_path), exist_ok=True)
    try:
        model.save(saved_model_path)
        print(f"Full model: {saved_model_path}")
    except Exception as e:
        print(f"Bỏ qua lưu .keras (dùng weights .h5): {e}")

    print(f"\nĐã train xong. Best weights: {BEST_WEIGHTS_PATH}")

    return model, history


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Train VGG16+CBAM")
    parser.add_argument("--seed", type=int, default=123, help="Random seed cho split/shuffle/train")
    parser.add_argument(
        "--batch-size",
        type=int,
        default=None,
        metavar="N",
        help="Batch size (mặc định 32; có GPU thường tăng 48–64 nếu vừa VRAM)",
    )
    parser.add_argument(
        "--no-mixed-precision",
        action="store_true",
        help="Tắt mixed_float16 (khi có GPU). Mặc định bật nếu có GPU.",
    )
    parser.add_argument("--no-xla", action="store_true", help="Tắt XLA jit (mặc định bật)")
    return parser.parse_args()


if __name__ == "__main__":
    args = parse_args()
    model, history = train(
        seed=args.seed,
        batch_size=args.batch_size,
        mixed_precision=not args.no_mixed_precision,
        xla=not args.no_xla,
    )

