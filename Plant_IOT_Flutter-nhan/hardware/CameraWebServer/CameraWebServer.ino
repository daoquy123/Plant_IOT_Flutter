/*
 * ESP32-CAM (AI-Thinker) - server-relay streaming + on-demand capture.
 * Stream path: POST /api/camera/frame (raw JPEG)
 * Capture path: poll /api/camera/command then POST /api/camera/upload (multipart)
 */

#include "esp_camera.h"
#include <WiFi.h>
#include <WiFiManager.h>
#include <WiFiClientSecure.h>
#include <HTTPClient.h>
#include <ArduinoJson.h>

#include "soc/soc.h"
#include "soc/rtc_cntl_reg.h"

// ===================== USER CONFIG =====================
static const char *API_KEY = "a90cfc28468dc7b73eda44573bebb3a6d39981c92f449a9fc3cda4e56e113ce0";
static const char *API_HOST = "five-small-snowflake.site";
static const uint16_t HTTPS_PORT = 443;

static const char *STREAM_PATH = "/api/camera/frame";
static const char *COMMAND_PATH = "/api/camera/command";
static const char *UPLOAD_PATH = "/api/camera/upload";

static const int WIFI_RESET_PIN = 0;
static const unsigned long WIFI_RESET_HOLD_MS = 3000;
static const unsigned long STREAM_INTERVAL_MS = 400;   // 2-5 FPS target
static const unsigned long COMMAND_POLL_MS = 2500;     // poll capture command every 2-3s
static const unsigned long WIFI_RETRY_MS = 5000;
static const uint32_t HTTP_TIMEOUT_MS = 15000;

// Stream profile (lightweight for RAM/CPU/bandwidth)
static const framesize_t STREAM_SIZE = FRAMESIZE_QVGA;
static const int STREAM_QUALITY = 14;

// Capture profile (high quality on demand only)
static const framesize_t CAPTURE_SIZE = FRAMESIZE_UXGA;
static const int CAPTURE_QUALITY = 9;

WiFiManager wm;
unsigned long lastStreamMs = 0;
unsigned long lastCommandPollMs = 0;
unsigned long lastWiFiRetryMs = 0;
unsigned long resetPressStartMs = 0;

// ----- AI-Thinker ESP32-CAM pins -----
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

String buildUrl(const char *path) {
  return String("https://") + API_HOST + path;
}

void applyStreamProfile() {
  sensor_t *s = esp_camera_sensor_get();
  if (!s) return;
  s->set_framesize(s, STREAM_SIZE);
  s->set_quality(s, STREAM_QUALITY);
}

void applyCaptureProfile() {
  sensor_t *s = esp_camera_sensor_get();
  if (!s) return;
  s->set_framesize(s, CAPTURE_SIZE);
  s->set_quality(s, CAPTURE_QUALITY);
}

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
  config.xclk_freq_hz = 10000000;
  config.pixel_format = PIXFORMAT_JPEG;
  config.frame_size = STREAM_SIZE;
  config.jpeg_quality = STREAM_QUALITY;
  config.fb_count = psramFound() ? 2 : 1;
  config.grab_mode = CAMERA_GRAB_LATEST;

  esp_err_t err = esp_camera_init(&config);
  if (err != ESP_OK) {
    Serial.printf("[CAM] init failed: 0x%x\n", err);
    return false;
  }

  applyStreamProfile();
  return true;
}

void connectWiFi() {
  WiFi.mode(WIFI_STA);
  WiFi.setSleep(false);

  wm.setConnectTimeout(60);
  wm.setConfigPortalTimeout(180);
  wm.setMinimumSignalQuality(15);

  Serial.println(F("[WiFi] Auto connecting..."));
  if (!wm.autoConnect("ESP32_Config")) {
    Serial.println(F("[WiFi] Failed, restart..."));
    delay(2000);
    ESP.restart();
  }

  Serial.print(F("[WiFi] Connected IP: "));
  Serial.println(WiFi.localIP());
}

void checkWiFiResetButton() {
  if (digitalRead(WIFI_RESET_PIN) == LOW) {
    if (resetPressStartMs == 0) {
      resetPressStartMs = millis();
    } else if (millis() - resetPressStartMs >= WIFI_RESET_HOLD_MS) {
      Serial.println(F("[WiFi] Reset settings requested"));
      wm.resetSettings();
      delay(300);
      ESP.restart();
    }
  } else {
    resetPressStartMs = 0;
  }
}

bool postStreamFrame(camera_fb_t *fb) {
  if (!fb || fb->len == 0) return false;
  if (fb->len > 200 * 1024) {
    Serial.printf("[STREAM] Frame too large: %u bytes\n", (unsigned int)fb->len);
    return false;
  }

  WiFiClientSecure client;
  client.setInsecure();

  HTTPClient http;
  http.setTimeout(HTTP_TIMEOUT_MS);
  if (!http.begin(client, buildUrl(STREAM_PATH))) {
    return false;
  }

  http.addHeader("Content-Type", "image/jpeg");
  http.addHeader("X-API-KEY", API_KEY);
  int code = http.sendRequest("POST", fb->buf, fb->len);
  http.end();

  if (code < 200 || code >= 300) {
    Serial.printf("[STREAM] POST /frame failed: %d\n", code);
    return false;
  }
  return true;
}

bool pollCaptureCommand() {
  WiFiClientSecure client;
  client.setInsecure();

  HTTPClient http;
  http.setTimeout(HTTP_TIMEOUT_MS);
  if (!http.begin(client, buildUrl(COMMAND_PATH))) {
    return false;
  }
  http.addHeader("X-API-KEY", API_KEY);

  int code = http.GET();
  if (code != HTTP_CODE_OK) {
    http.end();
    return false;
  }

  String payload = http.getString();
  http.end();

  DynamicJsonDocument doc(512);
  DeserializationError err = deserializeJson(doc, payload);
  if (err) {
    return false;
  }

  JsonVariant command = doc["command"];
  if (command.isNull()) {
    return false;
  }

  const char *type = command["type"] | "";
  return strcmp(type, "capture") == 0;
}

bool uploadCaptureMultipart(camera_fb_t *fb) {
  if (!fb || fb->len == 0) return false;

  static const char *boundary = "----ESP32CamCaptureBoundary";
  String head = String("--") + boundary +
                "\r\nContent-Disposition: form-data; name=\"image\"; filename=\"capture.jpg\"\r\n"
                "Content-Type: image/jpeg\r\n\r\n";
  String tail = String("\r\n--") + boundary + "--\r\n";
  const size_t totalLen = head.length() + fb->len + tail.length();

  WiFiClientSecure client;
  client.setInsecure();
  if (!client.connect(API_HOST, HTTPS_PORT)) {
    Serial.println(F("[CAPTURE] TLS connect failed"));
    return false;
  }

  client.printf("POST %s HTTP/1.1\r\n", UPLOAD_PATH);
  client.printf("Host: %s\r\n", API_HOST);
  client.println("Connection: close");
  client.printf("X-API-KEY: %s\r\n", API_KEY);
  client.printf("Content-Type: multipart/form-data; boundary=%s\r\n", boundary);
  client.printf("Content-Length: %u\r\n\r\n", (unsigned int)totalLen);

  client.write((const uint8_t *)head.c_str(), head.length());
  client.write(fb->buf, fb->len);
  client.write((const uint8_t *)tail.c_str(), tail.length());

  String statusLine = client.readStringUntil('\n');
  client.stop();

  bool ok = statusLine.indexOf(" 200 ") > 0 || statusLine.indexOf(" 201 ") > 0;
  if (!ok) {
    Serial.printf("[CAPTURE] Upload failed: %s\n", statusLine.c_str());
  }
  return ok;
}

void runOnDemandCapture() {
  applyCaptureProfile();
  delay(120); // allow sensor to settle after profile switch

  camera_fb_t *fb = esp_camera_fb_get();
  if (!fb) {
    Serial.println(F("[CAPTURE] fb_get failed"));
    applyStreamProfile();
    return;
  }

  bool ok = uploadCaptureMultipart(fb);
  esp_camera_fb_return(fb);

  applyStreamProfile();
  Serial.printf("[CAPTURE] Completed (%d)\n", (int)ok);
}

void setup() {
  WRITE_PERI_REG(RTC_CNTL_BROWN_OUT_REG, 0);

  Serial.begin(115200);
  Serial.println("\n--- ESP32-CAM relay streaming mode ---");

  pinMode(WIFI_RESET_PIN, INPUT_PULLUP);
  connectWiFi();

  if (!initCamera()) {
    Serial.println(F("[CAM] Init failed, restart in 10s"));
    delay(10000);
    ESP.restart();
  }

  lastStreamMs = millis();
  lastCommandPollMs = millis();
}

void loop() {
  checkWiFiResetButton();

  if (WiFi.status() != WL_CONNECTED) {
    unsigned long now = millis();
    if (now - lastWiFiRetryMs >= WIFI_RETRY_MS) {
      lastWiFiRetryMs = now;
      Serial.println(F("[WiFi] Disconnected, reconnecting..."));
      WiFi.reconnect();
    }
    delay(50);
    return;
  }

  unsigned long now = millis();

  if (now - lastStreamMs >= STREAM_INTERVAL_MS) {
    lastStreamMs = now;
    camera_fb_t *fb = esp_camera_fb_get();
    if (fb) {
      postStreamFrame(fb);
      esp_camera_fb_return(fb);
    } else {
      Serial.println(F("[STREAM] fb_get failed"));
    }
  }

  if (now - lastCommandPollMs >= COMMAND_POLL_MS) {
    lastCommandPollMs = now;
    if (pollCaptureCommand()) {
      runOnDemandCapture();
    }
  }

  yield();
}