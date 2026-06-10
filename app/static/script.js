const messagesEl = document.getElementById("messages");
const formEl = document.getElementById("upload-form");
const fileInput = document.getElementById("file");
const modelSelect = document.getElementById("model-select");

const MODEL_LABELS = {
  vgg16: "VGG16 + CBAM",
  resnet: "ResNet50 + CBAM",
};

function appendMessage({ type, html }) {
  const wrapper = document.createElement("div");
  wrapper.className = `message ${type}`;

  const avatar = document.createElement("div");
  avatar.className = "avatar";
  avatar.textContent = type === "user" ? "Bạn" : "AI";

  const bubble = document.createElement("div");
  bubble.className = "bubble";
  bubble.innerHTML = html;

  wrapper.appendChild(avatar);
  wrapper.appendChild(bubble);
  messagesEl.appendChild(wrapper);
  messagesEl.scrollTop = messagesEl.scrollHeight;
}

function formatResultHtml(data) {
  const r = data.result;
  const modelLabel = MODEL_LABELS[data.model] || data.model;

  const probs = Object.entries(r.raw_probs)
    .map(
      ([k, v]) =>
        `<span>${k.replaceAll("_", " ")}: ${(v * 100).toFixed(1)}%</span>`,
    )
    .join("");

  return `
    <p><strong>Mô hình:</strong> ${modelLabel}</p>
    <p><strong>Kết quả:</strong> ${r.label_vietnamese}</p>
    <p><strong>Độ tin cậy:</strong> ${(r.probability * 100).toFixed(1)}%</p>
    <p>${r.explanation}</p>
    <div class="probs">${probs}</div>
  `;
}

async function predictWithModel(file, model) {
  const formData = new FormData();
  formData.append("file", file);
  formData.append("model", model);

  const resp = await fetch("/api/predict", {
    method: "POST",
    body: formData,
  });

  if (!resp.ok) {
    const err = await resp.json().catch(() => ({}));
    throw new Error(err.detail || `Lỗi khi chạy ${MODEL_LABELS[model] || model}`);
  }

  return resp.json();
}

formEl.addEventListener("submit", async (e) => {
  e.preventDefault();
  const file = fileInput.files[0];
  if (!file) {
    alert("Vui lòng chọn một ảnh lá trước.");
    return;
  }

  const choice = modelSelect.value;
  const models =
    choice === "both" ? ["vgg16", "resnet"] : [choice];

  const userHtml = `
    <p><strong>Ảnh:</strong> ${file.name}</p>
    <p><strong>Mô hình:</strong> ${
      choice === "both"
        ? "VGG16 + CBAM & ResNet50 + CBAM"
        : MODEL_LABELS[choice]
    }</p>
  `;
  appendMessage({ type: "user", html: userHtml });

  const reader = new FileReader();
  reader.onload = () => {
    const imgHtml = `<img src="${reader.result}" class="image-preview" alt="preview" />`;
    appendMessage({ type: "user", html: imgHtml });
  };
  reader.readAsDataURL(file);

  const btn = formEl.querySelector(".send-btn");
  btn.disabled = true;
  btn.textContent = "Đang phân tích...";

  try {
    for (const model of models) {
      const data = await predictWithModel(file, model);
      appendMessage({ type: "bot", html: formatResultHtml(data) });
    }
  } catch (err) {
    appendMessage({
      type: "bot",
      html: `<p><strong>Lỗi:</strong> ${(err && err.message) || "Không xác định"}</p>`,
    });
  } finally {
    btn.disabled = false;
    btn.textContent = "Gửi";
    formEl.reset();
    modelSelect.value = choice;
  }
});
