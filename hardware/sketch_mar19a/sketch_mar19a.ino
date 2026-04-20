/*
 * ESP32 — DHT11 + soil + rain + pump + stepper (màn che)
 * WiFi: WiFiManager — AP SSID "ESP32_Config" when không có WiFi đã lưu.
 *
 * Libraries (Arduino Library Manager):
 *   - WiFiManager by tzapu (hoặc tablatronix fork cho ESP32)
 *   - ArduinoJson by Benoit Blanchon v6+
 *
 * Backend: POST /api/sensors , GET /api/relay/status
 * Header: X-API-KEY (must match server .env API_KEY)
 */

#include <WiFi.h>
#include <WiFiManager.h>
#include <WiFiClientSecure.h>
#include <HTTPClient.h>
#include <ArduinoJson.h>
#include <Wire.h>
#include "DHT.h"
#include <Stepper.h>

// ===================== USER CONFIG =====================
/** MUST match Node server API_KEY (≥32 chars recommended) */
static const char *API_KEY = "a90cfc28468dc7b73eda44573bebb3a6d39981c92f449a9fc3cda4e56e113ce0";

static const char *API_HOST = "five-small-snowflake.site";
static const uint16_t HTTPS_PORT = 443;

/** Nhận diện thiết bị trên server (optional) */
static const char *DEVICE_ID = "esp32_garden_main";

/** GPIO0 = nút BOOT: giữ ~3s để xóa WiFi và vào lại portal cấu hình */
static const int WIFI_RESET_PIN = 0;

static const unsigned long SENSOR_INTERVAL_MS = 60000;
static const unsigned long RELAY_POLL_INTERVAL_MS = 5000;
static const unsigned long WIFI_RESET_HOLD_MS = 3000;

static const int HTTP_RETRIES = 1;
static const uint32_t HTTP_TIMEOUT_MS = 20000;

// ===== HARDWARE (giữ như project cũ) =====
#define DHTPIN 4
#define DHTTYPE DHT11
#define SOIL_PIN 34
#define RAIN_PIN 35
#define PUMP_PIN 18

const int stepsPerRevolution = 2048;
Stepper myStepper(stepsPerRevolution, 13, 14, 12, 27);
DHT dht(DHTPIN, DHTTYPE);

bool isCoverOpen = false;

WiFiManager wm;

// Timing (no delay() in loop)
unsigned long lastSensorMs = 0;
unsigned long lastRelayMs = 0;
unsigned long resetPressStart = 0;

// Last known relay desire from server (relay_id 1 = shade, 2 = pump — backend convention)
bool wantShadeOpen = false;
bool wantPumpOn = false;

// -------------------- HTTPS helper --------------------
String buildBaseUrl(const char *path) {
  return String("https://") + API_HOST + path;
}

// -------------------- WiFiManager ---------------------
void connectWiFi() {
  wm.setConfigPortalTimeout(180);

  Serial.println(F("[WiFi] Starting portal if needed — AP: ESP32_Config"));

  bool ok = wm.autoConnect("ESP32_Config");

  if (!ok) {
    Serial.println(F("[WiFi] Failed, restarting..."));
    delay(2000);
    ESP.restart();
  }

  Serial.println(F("[WiFi] Connected!"));
  Serial.print(F("  IP: "));
  Serial.println(WiFi.localIP());
}

void checkWiFiResetButton() {
  if (digitalRead(WIFI_RESET_PIN) == LOW) {
    if (resetPressStart == 0) resetPressStart = millis();
    else if (millis() - resetPressStart >= WIFI_RESET_HOLD_MS) {
      Serial.println(F("[WiFi] Reset requested — clearing credentials"));
      wm.resetSettings();
      delay(300);
      ESP.restart();
    }
  } else {
    resetPressStart = 0;
  }
}

// -------------------- API: sensors --------------------
bool sendSensorDataOnce() {
  float h = dht.readHumidity();
  float t = dht.readTemperature();
  int soil = analogRead(SOIL_PIN);
  int rain = analogRead(RAIN_PIN);

  DynamicJsonDocument doc(512);
  
  // Fix 1: Proper Null handling for ArduinoJson
  if (isnan(t)) doc["temperature"] = JsonVariant(); 
  else doc["temperature"] = t;

  if (isnan(h)) doc["humidity"] = JsonVariant();
  else doc["humidity"] = h;

  doc["soil_moisture"] = soil;
  doc["rain"] = rain;
  doc["device_id"] = DEVICE_ID;

  String json;
  serializeJson(doc, json);

  WiFiClientSecure client;
  client.setInsecure();

  HTTPClient http;
  http.setTimeout(HTTP_TIMEOUT_MS);

  if (!http.begin(client, buildBaseUrl("/api/sensors"))) {
    Serial.println(F("[HTTP] begin failed"));
    return false;
  }

  http.addHeader("Content-Type", "application/json");
  http.addHeader("X-API-KEY", API_KEY);

  int code = http.POST(json);
  Serial.printf("[API] POST /api/sensors -> %d\n", code);

  // Fix 2: Correct error reporting for ESP32
  if (code < 0) {
    Serial.printf("[HTTP] Failed, error: %s\n", http.errorToString(code).c_str());
  }

  http.end();
  return code >= 200 && code < 300;
}

void sendSensorData() {
  for (int r = 0; r < HTTP_RETRIES; r++) {
    if (sendSensorDataOnce()) return;
    Serial.printf("[API] sensor retry %d/%d\n", r + 1, HTTP_RETRIES);
    delay(400); // chỉ trong nhánh lỗi, không chặn loop chính khi thành công
  }
  Serial.println(F("[API] sensor: all retries failed"));
}

// -------------------- API: relay status ---------------
bool fetchRelayStatusOnce() {
  WiFiClientSecure client;
  client.setInsecure();

  HTTPClient http;
  http.setTimeout(HTTP_TIMEOUT_MS);

  if (!http.begin(client, buildBaseUrl("/api/relay/status"))) {
    return false;
  }

  http.addHeader("X-API-KEY", API_KEY);

  int code = http.GET();
  Serial.printf("[API] GET /api/relay/status -> %d\n", code);

  if (code != HTTP_CODE_OK) {
    http.end();
    return false;
  }

  String payload = http.getString();
  http.end();

  DynamicJsonDocument doc(2048);
  DeserializationError err = deserializeJson(doc, payload);
  if (err) {
    Serial.println(err.c_str());
    return false;
  }

  if (!doc["relay_status"].is<JsonArray>()) {
    Serial.println(F("[API] relay_status not an array"));
    return false;
  }
  JsonArray arr = doc["relay_status"].as<JsonArray>();

  for (JsonObject row : arr) {
    int rid = row["relay_id"] | 0;
    bool st = false;
    if (row["state"].is<int>()) {
      st = row["state"].as<int>() != 0;
    } else if (row["state"].is<bool>()) {
      st = row["state"].as<bool>();
    }

    if (rid == 1) wantShadeOpen = st;
    if (rid == 2) wantPumpOn = st;
  }

  return true;
}

void fetchRelayStatus() {
  for (int r = 0; r < HTTP_RETRIES; r++) {
    if (fetchRelayStatusOnce()) return;
    Serial.printf("[API] relay retry %d/%d\n", r + 1, HTTP_RETRIES);
    delay(400);
  }
}

// -------------------- Actuators -----------------------
/**
 * Pump: code cũ — LOW = bật, HIGH = tắt.
 * Relay server: state true = bơm bật.
 */
void applyPumpOutput() {
  digitalWrite(PUMP_PIN, wantPumpOn ? LOW : HIGH);
}

/**
 * Stepper: relay_id 1 true = mở màn (giống cover true cũ).
 */
void applyShadeOutput() {
  static bool lastWant = false;
  if (wantShadeOpen == lastWant) return;
  lastWant = wantShadeOpen;

  if (wantShadeOpen && !isCoverOpen) {
    myStepper.step(-stepsPerRevolution * 9);
    isCoverOpen = true;
    Serial.println(F("[HW] Shade OPEN"));
  } else if (!wantShadeOpen && isCoverOpen) {
    myStepper.step(stepsPerRevolution * 9);
    isCoverOpen = false;
    Serial.println(F("[HW] Shade CLOSE"));
  }
}

// ===================== SETUP / LOOP =================
void setup() {
  Serial.begin(115200);
  delay(200);

  pinMode(WIFI_RESET_PIN, INPUT_PULLUP);
  pinMode(PUMP_PIN, OUTPUT);
  digitalWrite(PUMP_PIN, HIGH);

  myStepper.setSpeed(10);
  Wire.begin();
  dht.begin();

  connectWiFi();
}

void loop() {
  checkWiFiResetButton();

  if (WiFi.status() != WL_CONNECTED) {
    Serial.println(F("[WiFi] Lost — reconnecting"));
    WiFi.reconnect();
    unsigned long wait = millis();
    while (WiFi.status() != WL_CONNECTED && millis() - wait < 15000) {
      yield();
      delay(200);
    }
    if (WiFi.status() != WL_CONNECTED) {
      Serial.println(F("[WiFi] Still down, restart portal next boot or check AP"));
    }
    return;
  }

  unsigned long now = millis();

  if (now - lastSensorMs >= SENSOR_INTERVAL_MS) {
    lastSensorMs = now;
    sendSensorData();
  }

  if (now - lastRelayMs >= RELAY_POLL_INTERVAL_MS) {
    lastRelayMs = now;
    fetchRelayStatus();
    applyPumpOutput();
    applyShadeOutput();
  }

  yield();
}
