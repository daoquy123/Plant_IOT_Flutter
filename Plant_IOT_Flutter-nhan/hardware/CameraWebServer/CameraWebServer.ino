/*
 * ESP32-CAM (AI-Thinker) - event-driven capture.
 * Event-driven capture:
 *   - subscribe MQTT garden/camera/command
 *   - upload only when a capture command arrives
 */

#include "esp_camera.h"
#include <WiFi.h>
#include <WiFiManager.h>
#include <PubSubClient.h>
#include <ArduinoJson.h>

#include "soc/soc.h"
#include "soc/rtc_cntl_reg.h"

// ===================== USER CONFIG =====================
static const char *API_KEY = "a90cfc28468dc7b73eda44573bebb3a6d39981c92f449a9fc3cda4e56e113ce0";
static const char *API_HOST = "103.116.38.192";
static const uint16_t HTTP_PORT = 80;

static const char *UPLOAD_PATH = "/api/camera/upload";
static const char *MQTT_HOST = "103.116.38.192";
static const uint16_t MQTT_PORT = 1883;
static const char *MQTT_CLIENT_ID = "esp32_cam_main";
static const char *MQTT_TOPIC_COMMAND = "garden/camera/command";
static const char *MQTT_TOPIC_STATUS = "garden/camera/status";

// IMPORTANT: GPIO0 is used by XCLK on AI-Thinker ESP32-CAM, so do not reuse it as runtime button input.
// Set to -1 to disable WiFi reset button logic for camera firmware.
static const int WIFI_RESET_PIN = -1;
static const unsigned long WIFI_RESET_HOLD_MS = 3000;
static const unsigned long WIFI_RETRY_MS = 5000;
static const unsigned long MQTT_RETRY_MS = 3000;
static const uint32_t HTTP_TIMEOUT_MS = 15000;

// Idle profile (lightweight for RAM while waiting for MQTT commands)
static const framesize_t STREAM_SIZE = FRAMESIZE_QVGA;
static const int STREAM_QUALITY = 14;

// Capture profile (high quality on demand only)
static const framesize_t CAPTURE_SIZE = FRAMESIZE_UXGA;
static const int CAPTURE_QUALITY = 9;

WiFiManager wm;
unsigned long lastWiFiRetryMs = 0;
unsigned long lastMqttRetryMs = 0;
unsigned long resetPressStartMs = 0;
bool captureRequested = false;
char pendingRequestId[64] = "";
WiFiClient mqttWifiClient;
PubSubClient mqttClient(mqttWifiClient);

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
  return String("http://") + API_HOST + path;
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
  if (WIFI_RESET_PIN < 0) return;

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

bool uploadCaptureMultipart(camera_fb_t *fb) {
  if (!fb || fb->len == 0) return false;

  static const char *boundary = "----ESP32CamCaptureBoundary";
  String head = String("--") + boundary +
                "\r\nContent-Disposition: form-data; name=\"image\"; filename=\"capture.jpg\"\r\n"
                "Content-Type: image/jpeg\r\n\r\n";
  String tail = String("\r\n--") + boundary + "--\r\n";
  const size_t totalLen = head.length() + fb->len + tail.length();

  WiFiClient client;
  if (!client.connect(API_HOST, HTTP_PORT)) {
    Serial.println(F("[CAPTURE] HTTP connect failed"));
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

void publishCameraStatus(const char *status, const char *requestId = "") {
  if (!mqttClient.connected()) return;

  DynamicJsonDocument doc(256);
  doc["device_id"] = MQTT_CLIENT_ID;
  doc["status"] = status;
  if (requestId && requestId[0] != '\0') {
    doc["request_id"] = requestId;
  }
  doc["timestamp"] = millis();

  String json;
  serializeJson(doc, json);
  mqttClient.publish(MQTT_TOPIC_STATUS, json.c_str(), false);
}

void onMqttMessage(char *topic, byte *payload, unsigned int length) {
  if (String(topic) != MQTT_TOPIC_COMMAND) return;

  DynamicJsonDocument doc(512);
  DeserializationError err = deserializeJson(doc, payload, length);
  if (err) {
    Serial.printf("[MQTT] Command JSON parse error: %s\n", err.c_str());
    return;
  }

  const char *type = doc["type"] | "";
  if (strcmp(type, "capture") != 0) return;

  const char *requestId = doc["request_id"] | "";
  strlcpy(pendingRequestId, requestId, sizeof(pendingRequestId));
  captureRequested = true;
  Serial.printf("[MQTT] Capture requested: %s\n", pendingRequestId);
  publishCameraStatus("capture_accepted", pendingRequestId);
}

void ensureMqttConnected() {
  if (WiFi.status() != WL_CONNECTED) return;
  if (mqttClient.connected()) return;

  unsigned long now = millis();
  if (now - lastMqttRetryMs < MQTT_RETRY_MS) return;
  lastMqttRetryMs = now;

  Serial.println(F("[MQTT] Connecting..."));
  bool ok = mqttClient.connect(
    MQTT_CLIENT_ID,
    MQTT_CLIENT_ID,
    API_KEY,
    MQTT_TOPIC_STATUS,
    1,
    true,
    "{\"device_id\":\"esp32_cam_main\",\"status\":\"offline\"}"
  );

  if (!ok) {
    Serial.printf("[MQTT] Connect failed, rc=%d\n", mqttClient.state());
    return;
  }

  Serial.println(F("[MQTT] Connected"));
  mqttClient.subscribe(MQTT_TOPIC_COMMAND, 1);
  mqttClient.publish(
    MQTT_TOPIC_STATUS,
    "{\"device_id\":\"esp32_cam_main\",\"status\":\"online\"}",
    true
  );
}

bool runOnDemandCapture(const char *requestId) {
  applyCaptureProfile();
  delay(120); // allow sensor to settle after profile switch

  camera_fb_t *fb = esp_camera_fb_get();
  if (!fb) {
    Serial.println(F("[CAPTURE] fb_get failed"));
    applyStreamProfile();
    return false;
  }

  bool ok = uploadCaptureMultipart(fb);
  esp_camera_fb_return(fb);

  applyStreamProfile();
  Serial.printf("[CAPTURE] Completed (%d)\n", (int)ok);
  publishCameraStatus(ok ? "capture_uploaded" : "capture_upload_failed", requestId);
  return ok;
}

void setup() {
  WRITE_PERI_REG(RTC_CNTL_BROWN_OUT_REG, 0);

  Serial.begin(115200);
  Serial.println("\n--- ESP32-CAM MQTT capture mode ---");

  if (WIFI_RESET_PIN >= 0) {
    pinMode(WIFI_RESET_PIN, INPUT_PULLUP);
  }
  connectWiFi();

  if (!initCamera()) {
    Serial.println(F("[CAM] Init failed, restart in 10s"));
    delay(10000);
    ESP.restart();
  }

  mqttClient.setServer(MQTT_HOST, MQTT_PORT);
  mqttClient.setCallback(onMqttMessage);
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

  ensureMqttConnected();
  mqttClient.loop();

  if (captureRequested) {
    captureRequested = false;
    char requestId[64];
    strlcpy(requestId, pendingRequestId, sizeof(requestId));
    pendingRequestId[0] = '\0';
    publishCameraStatus("capture_started", requestId);
    runOnDemandCapture(requestId);
  }

  yield();
}
