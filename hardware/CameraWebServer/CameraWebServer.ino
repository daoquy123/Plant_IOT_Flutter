/*
 * ESP32-CAM (AI-Thinker) — Periodic JPEG upload to Node backend (HTTPS)
 * Dự án: PBL5 - Hệ thống giám sát hình ảnh
 * * Lưu ý: Chọn Board "AI Thinker ESP32-CAM" và Enable PSRAM trong Arduino IDE.
 */

#include "esp_camera.h"
#include <WiFi.h>
#include <WiFiManager.h>
#include <WiFiClientSecure.h>
#include <HTTPClient.h>

#include "soc/soc.h"
#include "soc/rtc_cntl_reg.h"
#include <esp_heap_caps.h>

// ===================== CẤU HÌNH NGƯỜI DÙNG =====================
static const char *API_KEY = "a90cfc28468dc7b73eda44573bebb3a6d39981c92f449a9fc3cda4e56e113ce0";
static const char *API_HOST = "five-small-snowflake.site";
static const char *UPLOAD_PATH = "/api/camera/upload";

// GPIO0: Giữ 3s để xóa WiFi cũ nếu cần cấu hình lại
static const int WIFI_RESET_PIN = 0;
static const unsigned long UPLOAD_INTERVAL_MS = 8000;
static const uint32_t HTTP_TIMEOUT_MS = 30000;

WiFiManager wm;
unsigned long lastUploadMs = 0;

// ----- Cấu hình chân AI-Thinker ESP32-CAM -----
#define PWDN_GPIO_NUM     32
#define RESET_GPIO_NUM    -1
#define XCLK_GPIO_NUM      0
#define SIOD_GPIO_NUM     26
#define SIOC_GPIO_NUM     27
#define Y9_GPIO_NUM       35
#define Y8_GPIO_NUM       34
#define Y7_GPIO_NUM       39
#define Y6_GPIO_NUM       36
#define Y5_GPIO_NUM       21
#define Y4_GPIO_NUM       19
#define Y3_GPIO_NUM       18
#define Y2_GPIO_NUM        5
#define VSYNC_GPIO_NUM    25
#define HREF_GPIO_NUM     23
#define PCLK_GPIO_NUM     22

// -------------------- Khởi tạo Camera -------------------------
bool initCamera() {
  camera_config_t config;
  config.ledc_channel = LEDC_CHANNEL_0;
  config.ledc_timer = LEDC_TIMER_0;
  config.pin_d0 = Y2_GPIO_NUM;
  config.pin_d1 = Y3_GPIO_NUM;
  config.pin_d2 = Y4_GPIO_NUM;
  config.pin_d3 = Y5_GPIO_NUM;
  config.pin_d4 = Y6_GPIO_NUM;
  config.pin_d5 = Y7_GPIO_NUM;
  config.pin_d6 = Y8_GPIO_NUM;
  config.pin_d7 = Y9_GPIO_NUM;
  config.pin_xclk = XCLK_GPIO_NUM;
  config.pin_pclk = PCLK_GPIO_NUM;
  config.pin_vsync = VSYNC_GPIO_NUM;
  config.pin_href = HREF_GPIO_NUM;
  config.pin_sscb_sda = SIOD_GPIO_NUM;
  config.pin_sscb_scl = SIOC_GPIO_NUM;
  config.pin_pwdn = PWDN_GPIO_NUM;
  config.pin_reset = RESET_GPIO_NUM;
  config.xclk_freq_hz = 10000000; // 10MHz để giảm nhiễu và điện năng
  config.pixel_format = PIXFORMAT_JPEG;

  if (psramFound()) {
    config.frame_size = FRAMESIZE_VGA;
    config.jpeg_quality = 12; // 0-63, số thấp chất lượng cao hơn
    config.fb_count = 2;
  } else {
    config.frame_size = FRAMESIZE_SVGA;
    config.jpeg_quality = 16;
    config.fb_count = 1;
  }

  esp_err_t err = esp_camera_init(&config);
  if (err != ESP_OK) {
    Serial.printf("[CAM] init failed: 0x%x\n", err);
    return false;
  }

  sensor_t *s = esp_camera_sensor_get();
  if (s) s->set_brightness(s, 0); 
  return true;
}

// -------------------- Kết nối WiFi ----------------------------
void connectWiFi() {
  WiFi.mode(WIFI_STA);
  WiFi.setSleep(false); // Ngăn ngắt kết nối do tiết kiệm điện

  // Cấu hình WiFiManager để chạy nhẹ nhất
  wm.setConnectTimeout(60); 
  wm.setConfigPortalTimeout(180);
  wm.setMinimumSignalQuality(15); // Bỏ qua các mạng quá yếu gây tràn RAM

  Serial.println(F("[WiFi] Dang thu ket noi lai..."));

  // Thử kết nối tự động, nếu không được mới mở Portal "ESP32_Config"
  if (!wm.autoConnect("ESP32_Config")) {
    Serial.println(F("[WiFi] Failed, restarting..."));
    delay(3000);
    ESP.restart();
  }

  Serial.print(F("[WiFi] Da ket noi! IP: "));
  Serial.println(WiFi.localIP());
}

// -------------------- Upload ảnh (HTTPS) --------------------
bool uploadFrameMultipart(camera_fb_t *fb) {
  if (!fb || fb->len == 0) return false;

  // Sử dụng con trỏ để giải phóng RAM triệt để cho SSL
  WiFiClientSecure *client = new WiFiClientSecure;
  if (!client) {
    Serial.println(F("[API] Khong du RAM cho SSL Client"));
    return false;
  }
  client->setInsecure(); // Bỏ qua kiểm tra chứng chỉ SSL Let's Encrypt

  HTTPClient http;
  http.setReuse(false);
  http.setTimeout(HTTP_TIMEOUT_MS);

  String url = "https://" + String(API_HOST) + UPLOAD_PATH;

  if (!http.begin(*client, url)) {
    Serial.println(F("[API] HTTP begin failed"));
    delete client;
    return false;
  }

  const char *boundary = "----ESP32CAMBoundary7MA4YWxk";
  String head = "--" + String(boundary) + "\r\nContent-Disposition: form-data; name=\"image\"; filename=\"cam.jpg\"\r\nContent-Type: image/jpeg\r\n\r\n";
  String tail = "\r\n--" + String(boundary) + "--\r\n";
  size_t totalLen = head.length() + fb->len + tail.length();

  uint8_t *body = (uint8_t *)heap_caps_malloc(totalLen, MALLOC_CAP_8BIT);
  if (!body) {
    Serial.println(F("[API] Malloc body failed"));
    http.end();
    delete client;
    return false;
  }

  memcpy(body, head.c_str(), head.length());
  memcpy(body + head.length(), fb->buf, fb->len);
  memcpy(body + head.length() + fb->len, tail.c_str(), tail.length());

  http.addHeader("Content-Type", "multipart/form-data; boundary=" + String(boundary));
  http.addHeader("X-API-KEY", API_KEY);
  http.addHeader("Connection", "keep-alive");

  int code = http.POST(body, totalLen);
  Serial.printf("[API] POST Result: %d (Size: %u bytes)\n", code, (unsigned int)totalLen);

  if (code > 0) {
    String response = http.getString();
    Serial.println("[SERVER] " + response);
  }

  free(body);
  http.end();
  delete client; 
  return (code >= 200 && code < 300);
}

// ===================== SETUP / LOOP =================
void setup() {
  // Tắt bảo vệ Brownout để tránh reset khi dòng điện không ổn định
  WRITE_PERI_REG(RTC_CNTL_BROWN_OUT_REG, 0);

  Serial.begin(115200);
  Serial.println("\n--- KHOI DONG ESP32-CAM ---");

  pinMode(WIFI_RESET_PIN, INPUT_PULLUP);

  // 1. KẾT NỐI WIFI TRƯỚC (QUAN TRỌNG: để tránh sụt áp lúc khởi động)
  connectWiFi();

  // 2. CHỈ KHỞI TẠO CAM SAU KHI CÓ WIFI
  if (!initCamera()) {
    Serial.println(F("Camera Fail! Kiem tra lai phan cung."));
    // Khởi động lại sau 10s nếu hỏng cam
    delay(10000);
    ESP.restart();
  }

  lastUploadMs = millis();
}

void loop() {
  // Kiểm tra nút Reset WiFi (GPIO0)
  if (digitalRead(WIFI_RESET_PIN) == LOW) {
    delay(3000); // Giữ 3s
    if (digitalRead(WIFI_RESET_PIN) == LOW) {
      Serial.println(F("[WiFi] Resetting settings..."));
      wm.resetSettings();
      ESP.restart();
    }
  }

  // Tự động kết nối lại nếu mất WiFi
  if (WiFi.status() != WL_CONNECTED) {
    Serial.println(F("[WiFi] Mat ket noi, dang thu lai..."));
    WiFi.reconnect();
    delay(5000);
    return;
  }

  // Gửi ảnh theo chu kỳ
  if (millis() - lastUploadMs >= UPLOAD_INTERVAL_MS) {
    lastUploadMs = millis();
    
    camera_fb_t *fb = esp_camera_fb_get();
    if (fb) {
      bool ok = uploadFrameMultipart(fb);
      if (!ok) {
        // Nếu upload lỗi liên tục, có thể giảm framesize hoặc restart
        Serial.println(F("[API] Upload failed, retrying next cycle..."));
      }
      esp_camera_fb_return(fb);
    } else {
      Serial.println(F("[CAM] Capture failed"));
    }
  }

  yield(); // Nhường quyền xử lý cho hệ thống WiFi
}