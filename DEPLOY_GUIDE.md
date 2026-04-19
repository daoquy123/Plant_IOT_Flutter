# Plant IoT Flutter - Hướng dẫn Deploy lên VPS Cloud

## Tổng quan
Hệ thống IoT vườn thông minh gồm:
- **Flutter app**: Dashboard, chat AI, điều khiển relay, xem ảnh ESP32-CAM
- **Node.js backend**: `server/` - tiếp nhận dữ liệu ESP32, lưu ảnh, trả lệnh relay
- **SQLite database**: Lưu trữ sensor readings, relay states, camera images, notifications
- **Socket.io**: Real-time updates cho app qua WebSocket
- **Nginx**: Reverse proxy, SSL, WebSocket upgrade

---

## Bước 1: Chuẩn bị VPS (Ubuntu 22.04 LTS)

### 1.1 Kết nối SSH vào VPS
```bash
ssh -i your_key.pem ubuntu@your-vps-ip
```

### 1.2 Cập nhật hệ thống
```bash
sudo apt update && sudo apt upgrade -y
```

### 1.3 Cài đặt Node.js 20 LTS
```bash
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt install -y nodejs
node --version  # v20.x.x
npm --version   # 10.x.x
```

### 1.4 Cài đặt PM2 (quản lý process)
```bash
sudo npm install -g pm2
pm2 completion install
```

### 1.5 Cài đặt Nginx
```bash
sudo apt install -y nginx
sudo systemctl enable nginx
sudo systemctl start nginx
```

### 1.6 Cài đặt Certbot (Let's Encrypt SSL)
```bash
sudo apt install -y certbot python3-certbot-nginx
```

### 1.7 Cấu hình UFW Firewall
```bash
sudo ufw enable
sudo ufw allow 22/tcp      # SSH
sudo ufw allow 80/tcp      # HTTP
sudo ufw allow 443/tcp     # HTTPS
sudo ufw status
```

---

## Bước 2: Clone và chuẩn bị code trên VPS

### 2.1 Tạo thư mục project
```bash
mkdir -p ~/projects
cd ~/projects
```

### 2.2 Clone repository (hoặc upload files)
```bash
git clone https://github.com/your-username/Plant_IOT_Flutter.git
cd Plant_IOT_Flutter
```

### 2.3 Chuẩn bị backend
```bash
cd server
npm install --production
```

### 2.4 Tạo file .env từ .env.example
```bash
cp .env.example .env
```

Chỉnh sửa `.env`:
```env
NODE_ENV=production
PORT=3000
API_KEY=your-very-long-secure-random-key-here-min-32-chars
DB_PATH=./data/plant_iot.db
UPLOADS_DIR=./uploads
MAX_FILE_SIZE_MB=5
SENSOR_RETENTION_DAYS=30
IMAGE_RETENTION_DAYS=7
LOG_LEVEL=info
```

**Tạo API key mạnh:**
```bash
node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"
```

### 2.5 Tạo thư mục lưu ảnh
```bash
mkdir -p data uploads logs
chmod 755 uploads logs
```

---

## Bước 3: Khởi động backend với PM2

### 3.1 Khởi động server
```bash
cd ~/projects/Plant_IOT_Flutter
pm2 start ecosystem.config.js --env production
pm2 save
```

### 3.2 Cấu hình PM2 khởi động tự động
```bash
sudo pm2 startup systemd -u $USER --hp /home/$USER
sudo pm2 save
```

### 3.3 Kiểm tra status
```bash
pm2 status
pm2 logs plant-iot
```

---

## Bước 4: Cấu hình Nginx làm Reverse Proxy

### 4.1 Tạo file cấu hình Nginx
```bash
sudo nano /etc/nginx/sites-available/plant-iot
```

Dán nội dung (thay `api.yourdomain.com`):
```nginx
upstream plant_iot_backend {
    server 127.0.0.1:3000;
}

# Redirect HTTP -> HTTPS
server {
    listen 80;
    listen [::]:80;
    server_name api.yourdomain.com;

    location / {
        return 301 https://$server_name$request_uri;
    }
}

# HTTPS server
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name api.yourdomain.com;

    # SSL certificates (sẽ được tạo bởi Certbot)
    ssl_certificate /etc/letsencrypt/live/api.yourdomain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/api.yourdomain.com/privkey.pem;

    # SSL configuration
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;

    # Security headers
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-Frame-Options "SAMEORIGIN" always;

    # Uploadsize limit
    client_max_body_size 10M;

    # Root location
    location / {
        proxy_pass http://plant_iot_backend;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_buffering off;
        proxy_request_buffering off;
    }

    # Static files cache
    location /uploads/ {
        proxy_pass http://plant_iot_backend;
        proxy_cache_valid 200 7d;
        expires 7d;
        add_header Cache-Control "public, max-age=604800";
    }

    # Health check endpoint
    location /health {
        proxy_pass http://plant_iot_backend;
        access_log off;
    }
}
```

### 4.2 Kích hoạt site
```bash
sudo ln -s /etc/nginx/sites-available/plant-iot /etc/nginx/sites-enabled/
sudo nginx -t  # Kiểm tra cú pháp
sudo systemctl reload nginx
```

---

## Bước 5: Cấp SSL certificate với Let's Encrypt

### 5.1 Tạo SSL
```bash
sudo certbot --nginx -d api.yourdomain.com
```

Chọn:
- Email: your@email.com
- Agree terms
- Share email (optional)
- Redirect HTTP to HTTPS: **Yes (2)**

### 5.2 Auto-renew SSL
```bash
sudo systemctl enable certbot.timer
sudo systemctl start certbot.timer
sudo certbot renew --dry-run
```

---

## Bước 6: Cập nhật Flutter App

### 6.1 Mở Settings Screen
- Nhập **Server URL**: `https://api.yourdomain.com`
- Nhập **API Key**: (giá trị từ `.env`)
- Lưu và khởi động lại app

### 6.2 Test kết nối
- Kiểm tra Dashboard có dữ liệu từ esp32 chưa
- Thử gửi lệnh relay (bơm/hiên)
- Xem ảnh camera

---

## Bước 7: Cấu hình ESP32 kết nối backend

### 7.1 Mã Arduino mẫu cho ESP32 (sensor)

```cpp
#include <WiFi.h>
#include <HTTPClient.h>
#include <ArduinoJson.h>

const char* ssid = "YOUR_WIFI_SSID";
const char* password = "YOUR_WIFI_PASSWORD";
const char* serverUrl = "https://api.yourdomain.com";
const char* apiKey = "your-api-key-here";

// Pin definitions
#define SENSOR_TEMP 35      // ADC pin for temp (DS18B20 or similar)
#define SENSOR_HUMIDITY 34  // ADC pin for humidity
#define SENSOR_SOIL 32      // ADC pin for soil moisture
#define SENSOR_LIGHT 33     // ADC pin for light
#define RELAY_PUMP 26       // GPIO for pump relay
#define RELAY_SHADE 27      // GPIO for shade relay

unsigned long lastSensorSend = 0;
unsigned long lastCommandCheck = 0;
const unsigned long SENSOR_INTERVAL = 30000;    // Send sensor every 30s
const unsigned long COMMAND_INTERVAL = 5000;    // Check command every 5s

void setup() {
  Serial.begin(115200);
  pinMode(RELAY_PUMP, OUTPUT);
  pinMode(RELAY_SHADE, OUTPUT);
  digitalWrite(RELAY_PUMP, LOW);
  digitalWrite(RELAY_SHADE, LOW);

  WiFi.mode(WIFI_STA);
  WiFi.begin(ssid, password);

  int attempts = 0;
  while (WiFi.status() != WL_CONNECTED && attempts < 20) {
    delay(500);
    Serial.print(".");
    attempts++;
  }

  if (WiFi.status() == WL_CONNECTED) {
    Serial.println("\nWiFi connected: " + WiFi.localIP().toString());
  } else {
    Serial.println("\nFailed to connect WiFi");
  }
}

void loop() {
  unsigned long now = millis();

  // Send sensor data periodically
  if (now - lastSensorSend >= SENSOR_INTERVAL) {
    sendSensorData();
    lastSensorSend = now;
  }

  // Check relay commands from server
  if (now - lastCommandCheck >= COMMAND_INTERVAL) {
    checkAndApplyCommands();
    lastCommandCheck = now;
  }

  delay(100);
}

void sendSensorData() {
  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("WiFi disconnected");
    return;
  }

  HTTPClient http;
  http.setConnectTimeout(5000);
  http.setTimeout(10000);

  // Read sensor values
  float temperature = readTemperature();
  float humidity = readHumidity();
  int soil_moisture = readSoilMoisture();
  int light = readLight();

  // Build JSON payload
  StaticJsonDocument<256> doc;
  doc["temperature"] = temperature;
  doc["humidity"] = humidity;
  doc["soil_moisture"] = soil_moisture;
  doc["light"] = light;
  doc["device_id"] = "esp32_main";

  String payload;
  serializeJson(doc, payload);

  // Send POST /api/sensors
  String url = String(serverUrl) + "/api/sensors";
  http.begin(url);
  http.addHeader("Content-Type", "application/json");
  http.addHeader("X-API-KEY", apiKey);

  int httpCode = http.POST(payload);
  if (httpCode == 200) {
    Serial.println("✓ Sensor sent");
  } else {
    Serial.printf("✗ Sensor POST failed: %d\n", httpCode);
  }

  http.end();
}

void checkAndApplyCommands() {
  if (WiFi.status() != WL_CONNECTED) return;

  HTTPClient http;
  http.setConnectTimeout(5000);
  http.setTimeout(10000);

  String url = String(serverUrl) + "/api/relay/status";
  http.begin(url);
  http.addHeader("X-API-KEY", apiKey);

  int httpCode = http.GET();
  if (httpCode == 200) {
    String response = http.getString();
    StaticJsonDocument<512> doc;
    deserializeJson(doc, response);

    JsonArray relays = doc["relay_status"];
    for (JsonObject relay : relays) {
      int relay_id = relay["relay_id"];
      bool state = relay["state"];

      if (relay_id == 1) {
        digitalWrite(RELAY_PUMP, state ? HIGH : LOW);
        Serial.printf("Pump: %s\n", state ? "ON" : "OFF");
      } else if (relay_id == 2) {
        digitalWrite(RELAY_SHADE, state ? HIGH : LOW);
        Serial.printf("Shade: %s\n", state ? "ON" : "OFF");
      }
    }
  }

  http.end();
}

// Sensor read functions (implement based on your hardware)
float readTemperature() {
  // Read from ADC or DS18B20
  int raw = analogRead(SENSOR_TEMP);
  return (raw / 4095.0) * 50.0;  // Example: 0-50°C range
}

float readHumidity() {
  int raw = analogRead(SENSOR_HUMIDITY);
  return (raw / 4095.0) * 100.0;  // Example: 0-100% range
}

int readSoilMoisture() {
  return analogRead(SENSOR_SOIL);  // 0-4095
}

int readLight() {
  return analogRead(SENSOR_LIGHT);  // 0-4095
}
```

### 7.2 Mã Arduino cho ESP32-CAM

```cpp
#include <WiFi.h>
#include <HTTPClient.h>
#include "esp_camera.h"
#include "esp_timer.h"
#include "img_converters.h"
#include "camera_pins.h"

const char* ssid = "YOUR_WIFI_SSID";
const char* password = "YOUR_WIFI_PASSWORD";
const char* serverUrl = "https://api.yourdomain.com";
const char* apiKey = "your-api-key-here";

unsigned long lastCapture = 0;
const unsigned long CAPTURE_INTERVAL = 600000;  // Capture every 10 minutes

void setup() {
  Serial.begin(115200);

  // Camera config
  camera_config_t config;
  config.ledc_channel = LEDC_CHANNEL_0;
  config.ledc_freq_hz = 20000000;
  config.pin_d7 = Y9_GPIO_NUM;
  config.pin_d6 = Y8_GPIO_NUM;
  config.pin_d5 = Y7_GPIO_NUM;
  config.pin_d4 = Y6_GPIO_NUM;
  config.pin_d3 = Y5_GPIO_NUM;
  config.pin_d2 = Y4_GPIO_NUM;
  config.pin_d1 = Y3_GPIO_NUM;
  config.pin_d0 = Y2_GPIO_NUM;
  config.pin_vsync = VSYNC_GPIO_NUM;
  config.pin_href = HREF_GPIO_NUM;
  config.pin_sclk = SCLK_GPIO_NUM;
  config.pin_pclk = PCLK_GPIO_NUM;
  config.pin_pwdn = PWDN_GPIO_NUM;
  config.pin_reset = RESET_GPIO_NUM;
  config.xclk_freq_hz = 20000000;
  config.grab_mode = CAMERA_GRAB_WHEN_EMPTY;
  config.fb_location = CAMERA_FB_IN_PSRAM;
  config.jpeg_quality = 12;
  config.fb_count = 1;

  if (esp_camera_init(&config) != ESP_OK) {
    Serial.println("Camera init failed!");
    return;
  }

  // WiFi connect
  WiFi.mode(WIFI_STA);
  WiFi.begin(ssid, password);

  int attempts = 0;
  while (WiFi.status() != WL_CONNECTED && attempts < 20) {
    delay(500);
    Serial.print(".");
    attempts++;
  }

  if (WiFi.status() == WL_CONNECTED) {
    Serial.println("\nWiFi connected: " + WiFi.localIP().toString());
  }
}

void loop() {
  unsigned long now = millis();

  if (now - lastCapture >= CAPTURE_INTERVAL) {
    captureAndUpload();
    lastCapture = now;
  }

  delay(1000);
}

void captureAndUpload() {
  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("WiFi not connected");
    return;
  }

  camera_fb_t* fb = esp_camera_fb_get();
  if (!fb) {
    Serial.println("Camera capture failed");
    return;
  }

  HTTPClient http;
  http.setConnectTimeout(10000);
  http.setTimeout(30000);

  String url = String(serverUrl) + "/api/camera/upload";
  http.begin(url);
  http.addHeader("X-API-KEY", apiKey);

  int httpCode = http.POST(fb->buf, fb->len);

  if (httpCode == 200) {
    Serial.println("✓ Image uploaded");
  } else {
    Serial.printf("✗ Upload failed: %d\n", httpCode);
  }

  http.end();
  esp_camera_fb_return(fb);
}
```

---

## Bước 8: Backup hàng ngày

### 8.1 Cấu hình cron job
```bash
chmod +x ~/projects/Plant_IOT_Flutter/scripts/backup.sh
crontab -e
```

Thêm dòng:
```cron
0 2 * * * /home/ubuntu/projects/Plant_IOT_Flutter/scripts/backup.sh
```

---

## Bước 9: Monitoring và Log

### 9.1 Xem PM2 logs
```bash
pm2 logs plant-iot --lines 100
pm2 logs plant-iot --err
```

### 9.2 Xem Nginx logs
```bash
sudo tail -f /var/log/nginx/error.log
sudo tail -f /var/log/nginx/access.log
```

### 9.3 Xem server logs
```bash
tail -f ~/projects/Plant_IOT_Flutter/server/logs/server.log
```

### 9.4 Health check
```bash
curl https://api.yourdomain.com/health
```

---

## Bước 10: Auto-deploy với GitHub Actions

### 10.1 Thiết lập SSH keys trên GitHub
1. Tạo SSH key mới trên VPS (nếu chưa có):
   ```bash
   ssh-keygen -t ed25519 -C "deploy@vps" -f ~/.ssh/deploy_key -N ""
   ```

2. Thêm public key vào `~/.ssh/authorized_keys`:
   ```bash
   cat ~/.ssh/deploy_key.pub >> ~/.ssh/authorized_keys
   ```

3. Copy private key sang GitHub Secrets:
   ```bash
   cat ~/.ssh/deploy_key | xclip -selection clipboard
   ```

### 10.2 Cấu hình GitHub Secrets
Vào **Settings → Secrets and variables → Actions** và thêm:
- `VPS_HOST`: IP hoặc domain của VPS
- `VPS_USER`: ubuntu (hoặc user của bạn)
- `VPS_SSH_KEY`: (nội dung private key)
- `VPS_PORT`: 22 (nếu custom)

### 10.3 GitHub Actions sẽ tự động deploy khi push lên `main`

---

## Troubleshooting

### Lỗi: "Cannot find module 'better-sqlite3'"
```bash
cd ~/projects/Plant_IOT_Flutter/server
npm install better-sqlite3
```

### Lỗi: "EACCES: permission denied"
```bash
sudo chown -R $USER:$USER ~/projects/Plant_IOT_Flutter
chmod -R u+w ~/projects/Plant_IOT_Flutter/server/{data,uploads,logs}
```

### Lỗi: Socket.io không kết nối
- Kiểm tra Nginx config có `Upgrade` headers chưa
- Kiểm tra firewall cho phép WebSocket (port 443)
- App phải dùng `https://` với SSL certificate hợp lệ

### ESP32 không gửi dữ liệu
- Kiểm tra WiFi connection: `Serial.println(WiFi.status())`
- Test API: `curl -H "X-API-KEY: xxx" https://api.yourdomain.com/health`
- Kiểm tra ESP32 tinymem có CA certificate chưa (hoặc dùng `setInsecure()` dev-only)

---

## Maintenance

### Xoá dữ liệu cũ thủ công
```bash
cd ~/projects/Plant_IOT_Flutter/server
npm run migrate
```

### Restart server
```bash
pm2 restart plant-iot
```

### Stop/Start
```bash
pm2 stop plant-iot
pm2 start plant-iot
```

### Xem DB size
```bash
ls -lh ~/projects/Plant_IOT_Flutter/server/data/plant_iot.db
```

---

## Chúc mừng! 🎉
Hệ thống Plant IoT của bạn giờ đã chạy trên production! 

**Các địa chỉ chính:**
- **API**: https://api.yourdomain.com
- **Health check**: https://api.yourdomain.com/health
- **Uploads**: https://api.yourdomain.com/uploads/

Hãy cập nhật URL server trong Flutter app Settings và bắt đầu sử dụng!
