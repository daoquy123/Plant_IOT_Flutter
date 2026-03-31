const express = require("express");
const http = require("http");
const { Server } = require("socket.io");
const cors = require("cors");
const fs = require("fs");
const path = require("path");

const app = express();
const server = http.createServer(app);
const io = new Server(server, {
  cors: { origin: "*" },
});

const UPLOAD_DIR = path.join(__dirname, "uploads");
fs.mkdirSync(UPLOAD_DIR, { recursive: true });

app.use(cors());
app.use(express.json({ limit: "10mb" }));
app.use("/uploads", express.static(UPLOAD_DIR));

let latestSensor = {
  status: "waiting",
  temperature: null,
  humidity: null,
  current_moisture: null,
  light_lux: null,
  rain: null,
  updatedAt: null,
};

let latestCommand = {
  pump: false,
  cover: false,
  action: "idle",
  ts: null,
};

// Relay bơm thực tế đang nhận mức HIGH để bật, nên map `pump_on` -> false
// để ESP32 hiện tại đi vào nhánh `else` và xuất HIGH ở chân relay.
const COMMAND_POLARITY = {
  pumpOnValue: false,
  pumpOffValue: true,
  coverOpenValue: true,
  coverCloseValue: false,
};

let latestImage = {
  url: "",
  ts: null,
};

function toNumber(value) {
  if (value === null || value === undefined || value === "") {
    return null;
  }
  if (typeof value === "number" && Number.isFinite(value)) {
    return value;
  }
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

function buildPublicUrl(req, relativePath) {
  const host = process.env.PUBLIC_HOST || req.get("host");
  return `${req.protocol}://${host}${relativePath}`;
}

// =============================
// 📤 ESP32 gửi SENSOR
// =============================
app.post("/api/sensor", (req, res) => {
  const body = req.body || {};

  latestSensor = {
    ...latestSensor,
    ...body,
    status: body.status || "success",
    temperature: toNumber(body.temperature ?? body.air_temp),
    humidity: toNumber(body.humidity ?? body.air_humidity),
    current_moisture: toNumber(body.current_moisture ?? body.soil),
    light_lux: toNumber(body.light_lux ?? body.lux),
    rain: toNumber(body.rain),
    updatedAt: new Date().toISOString(),
  };

  console.log("📡 Sensor:", latestSensor);
  io.emit("sensor", latestSensor);

  res.json({ status: "ok", sensor: latestSensor });
});

app.get("/api/sensor/latest", (req, res) => {
  res.json(latestSensor);
});

// =============================
// 📷 ESP32-CAM gửi IMAGE
// =============================
app.post("/api/image", (req, res) => {
  const chunks = [];

  req.on("data", (chunk) => {
    chunks.push(chunk);
  });

  req.on("end", () => {
    try {
      const buffer = Buffer.concat(chunks);
      if (!buffer.length) {
        return res.status(400).json({ status: "error", message: "Empty image body" });
      }

      const filename = `img_${Date.now()}.jpg`;
      const filepath = path.join(UPLOAD_DIR, filename);
      fs.writeFileSync(filepath, buffer);

      latestImage = {
        url: buildPublicUrl(req, `/uploads/${filename}`),
        ts: new Date().toISOString(),
      };

      console.log("📷 Image:", latestImage);
      io.emit("image", latestImage);

      res.json({ status: "ok", ...latestImage });
    } catch (error) {
      console.error("❌ Save image error:", error);
      res.status(500).json({ status: "error", message: "Cannot save image" });
    }
  });
});

app.get("/api/image/latest", (req, res) => {
  res.json(latestImage);
});

// =============================
// 📥 Flutter gửi lệnh relay
// =============================
app.post("/api/relay", (req, res) => {
  const body = req.body || {};
  const action = body.action?.toString().trim();

  if (!action) {
    return res.status(400).json({ status: "error", message: "Missing action" });
  }

  switch (action) {
    case "pump_on":
      latestCommand.pump = COMMAND_POLARITY.pumpOnValue;
      break;
    case "pump_off":
      latestCommand.pump = COMMAND_POLARITY.pumpOffValue;
      break;
    case "shade_on":
      latestCommand.cover = COMMAND_POLARITY.coverOpenValue;
      break;
    case "shade_off":
      latestCommand.cover = COMMAND_POLARITY.coverCloseValue;
      break;
    case "status":
      break;
    default:
      return res.status(400).json({
        status: "error",
        message: `Unsupported action: ${action}`,
      });
  }

  latestCommand = {
    ...latestCommand,
    action,
    ts: Date.now(),
  };

  console.log("🎮 Command:", latestCommand);
  io.emit("command", latestCommand);

  res.json({
    status: "ok",
    command: latestCommand,
    sensor: latestSensor,
    image: latestImage,
  });
});

// =============================
// 📥 ESP32 lấy lệnh
// =============================
app.get("/api/command", (req, res) => {
  res.json(latestCommand);
});

// =============================
// 📊 API test
// =============================
app.get("/", (req, res) => {
  res.json({
    status: "ok",
    message: "IoT Server is running",
    sensor: latestSensor,
    command: latestCommand,
    image: latestImage,
  });
});

// =============================
// 🔌 Socket.IO
// =============================
io.on("connection", (socket) => {
  console.log("📱 Client connected:", socket.id);

  socket.emit("sensor", latestSensor);
  socket.emit("command", latestCommand);
  socket.emit("image", latestImage);

  socket.on("disconnect", () => {
    console.log("❌ Client disconnected");
  });
});

// =============================
// 🚀 RUN SERVER
// =============================
const PORT = Number(process.env.PORT || 3000);
server.listen(PORT, () => {
  console.log(`🚀 Server chạy tại http://localhost:${PORT}`);
});