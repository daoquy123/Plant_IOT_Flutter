/*
 * ESP32 — DHT11 + soil + rain + pump + stepper (shade) + 3 buttons + LCD I2C
 * Realtime MQTT + HTTP for pump session & plant health check.
 *
 * Libraries:
 *   - WiFiManager
 *   - PubSubClient
 *   - ArduinoJson v6+
 *   - DHT sensor library
 *   - Stepper
 */

#include <WiFi.h>
#include <WiFiManager.h>
#include <PubSubClient.h>
#include <ArduinoJson.h>
#include <Wire.h>
#include <math.h>
#include <HTTPClient.h>
#include "DHT.h"
#include <Stepper.h>

// ===================== USER CONFIG =====================
static const char *API_KEY = "a90cfc28468dc7b73eda44573bebb3a6d39981c92f449a9fc3cda4e56e113ce0";
static const char *DEVICE_ID = "esp32_garden_main";
static const char *SERVER_URL = "http://103.116.38.192";
static const int WIFI_RESET_PIN = 0;

static const char *MQTT_HOST = "103.116.38.192";
static const uint16_t MQTT_PORT = 1883;
static const char *MQTT_TOPIC_SENSOR = "garden/sensor";
static const char *MQTT_TOPIC_RELAY_STATE = "garden/relay/state";
static const char *MQTT_TOPIC_RELAY_SET = "garden/relay/set";

static const unsigned long SENSOR_SAMPLE_INTERVAL_MS = 2000;
static const unsigned long LCD_REFRESH_INTERVAL_MS = 1000;
static const unsigned long WIFI_RESET_HOLD_MS = 3000;
static const unsigned long WIFI_RETRY_INTERVAL_MS = 5000;
static const unsigned long MQTT_RETRY_INTERVAL_MS = 3000;
static const unsigned long STEPPER_STEP_INTERVAL_MS = 3;
static const unsigned long BTN_DEBOUNCE_MS = 50;
static const unsigned long HEALTH_DISPLAY_MS = 30000;
static const unsigned long PUMP_RELAY_SETTLE_MS = 600;
static const int PUMP_SESSION_SECONDS = 30;
static const char *HEALTH_CHECK_MODEL = "resnet";
static const int SHADE_TRAVEL_STEPS = 2048 * 9;
static const float TEMP_DELTA = 0.5f;
static const float HUMIDITY_DELTA = 2.0f;
static const int SOIL_DELTA = 50;
static const int RAIN_DELTA = 50;

// ===== HARDWARE =====
#define DHTPIN 4
#define DHTTYPE DHT11
#define SOIL_PIN 34
#define RAIN_PIN 35
#define PUMP_PIN 18

#define BTN_SHADE_PIN 19
#define BTN_PUMP_PIN 21
#define BTN_HEALTH_PIN 22

#define LCD_I2C_ADDR 0x27
#define LCD_I2C_ADDR_ALT 0x3F
#define LCD_COLS 16
#define LCD_ROWS 2
#define LCD_SDA_PIN 25
#define LCD_SCL_PIN 26

// Minimal PCF8574 HD44780 driver (tránh lỗi thư viện LiquidCrystal_I2C trên ESP32).
class LcdI2c {
 public:
  void begin(uint8_t addr) {
    _addr = addr;
    delay(50);
    write4bits(0x03, CMD_MODE);
    delay(5);
    write4bits(0x03, CMD_MODE);
    delayMicroseconds(150);
    write4bits(0x03, CMD_MODE);
    delayMicroseconds(150);
    write4bits(0x02, CMD_MODE);
    delayMicroseconds(150);
    command(0x28);
    command(0x0C);
    command(0x01);
    delay(3);
    command(0x06);
  }

  void clear() {
    command(0x01);
    delay(3);
  }

  void backlight(bool on) {
    _backlight = on ? BACKLIGHT : 0;
    Wire.beginTransmission(_addr);
    Wire.write(_backlight);
    Wire.endTransmission();
  }

  void setCursor(uint8_t col, uint8_t row) {
    static const uint8_t rowOffsets[] = {0x00, 0x40, 0x14, 0x54};
    if (row >= LCD_ROWS) row = LCD_ROWS - 1;
    command(0x80 | (rowOffsets[row] + col));
  }

  bool print(const char *text) {
    if (!text) return true;
    while (*text) {
      if (!writeData(*text++)) return false;
    }
    return true;
  }

  bool printLine(uint8_t row, const char *text) {
    char buf[LCD_COLS + 1];
    padLine(text, buf);
    setCursor(0, row);
    return print(buf);
  }

 private:
  static const uint8_t BACKLIGHT = 0x08;
  static const uint8_t ENABLE = 0x04;
  static const uint8_t CMD_MODE = 0x00;
  static const uint8_t DATA_MODE = 0x01;

  uint8_t _addr = LCD_I2C_ADDR;
  uint8_t _backlight = BACKLIGHT;

  static void padLine(const char *src, char *dst) {
    uint8_t i = 0;
    while (i < LCD_COLS && src && src[i]) {
      dst[i] = src[i];
      i++;
    }
    while (i < LCD_COLS) {
      dst[i++] = ' ';
    }
    dst[LCD_COLS] = '\0';
  }

  bool pulseEnable(uint8_t data, uint8_t mode) {
    Wire.beginTransmission(_addr);
    Wire.write(data | mode | _backlight | ENABLE);
    if (Wire.endTransmission() != 0) return false;
    delayMicroseconds(1);
    Wire.beginTransmission(_addr);
    Wire.write(data | mode | _backlight);
    if (Wire.endTransmission() != 0) return false;
    delayMicroseconds(50);
    return true;
  }

  bool write4bits(uint8_t value, uint8_t mode) {
    if (!pulseEnable(value & 0xF0, mode)) return false;
    return pulseEnable((value << 4) & 0xF0, mode);
  }

  bool command(uint8_t value) {
    if (!write4bits(value, CMD_MODE)) return false;
    if (value == 0x01 || value == 0x02) {
      delay(2);
    }
    return true;
  }

  bool writeData(uint8_t value) {
    return write4bits(value, DATA_MODE);
  }
};

const int stepsPerRevolution = 2048;
Stepper myStepper(stepsPerRevolution, 13, 14, 12, 27);
DHT dht(DHTPIN, DHTTYPE);
LcdI2c lcd;

const bool REVERSE_SHADE_DIRECTION = false;
// Relay 1 kênh: HIGH = bật relay = máy bơm chạy. Đổi false nếu module active-LOW.
const bool PUMP_ACTIVE_HIGH = true;

enum LcdMode : uint8_t {
  LCD_MODE_DEFAULT = 0,
  LCD_MODE_PROCESSING,
  LCD_MODE_HEALTH,
  LCD_MODE_ERROR,
};

struct DebouncedButton {
  int pin;
  bool stableState;
  bool lastReading;
  unsigned long lastChangeMs;
};

bool isCoverOpen = false;
unsigned long lastSensorMs = 0;
unsigned long lastLcdRefreshMs = 0;
unsigned long resetPressStart = 0;
unsigned long lastWiFiRetryMs = 0;
unsigned long lastMqttRetryMs = 0;
unsigned long lastStepperStepMs = 0;
unsigned long healthDisplayUntilMs = 0;
unsigned long errorDisplayUntilMs = 0;

bool wantShadeOpen = false;
bool wantPumpOn = false;
bool hasPublishedSensor = false;
bool pumpRequestPending = false;
bool relayApplyPending = false;
volatile bool healthTaskRunning = false;
volatile bool pumpSessionTaskRunning = false;
volatile bool lcdUpdatePending = false;
unsigned long pumpRelayChangedMs = 0;

struct SensorCache {
  float temp = NAN;
  float humidity = NAN;
  int soil = 0;
  int rain = 0;
  bool fresh = false;
} sensorCache;
bool lcdReady = false;
char lcdLine1[17] = "";
char lcdLine2[17] = "";
char lastLcdLine1[17] = "";
char lastLcdLine2[17] = "";

float lastPublishedTemp = NAN;
float lastPublishedHumidity = NAN;
int lastPublishedSoil = -1;
int lastPublishedRain = -1;

LcdMode lcdMode = LCD_MODE_DEFAULT;
char healthLine1[17] = "";
char healthLine2[17] = "";
char errorLine1[17] = "Loi xu ly";
char errorLine2[17] = "";

volatile long stepperRemaining = 0;
int stepperDirection = 1;
bool stepperRunning = false;

DebouncedButton btnShade = {BTN_SHADE_PIN, true, true, 0};
DebouncedButton btnPump = {BTN_PUMP_PIN, true, true, 0};
DebouncedButton btnHealth = {BTN_HEALTH_PIN, true, true, 0};

WiFiManager wm;
WiFiClient wifiClient;
PubSubClient mqttClient(wifiClient);

// -------------------- LCD helpers ---------------------
void copyLcdText(char *dst, size_t dstSize, const String &text) {
  String clipped = text;
  if (clipped.length() >= (int)dstSize) {
    clipped = clipped.substring(0, dstSize - 1);
  }
  clipped.toCharArray(dst, dstSize);
}

void scanI2cBus() {
  Serial.println(F("[LCD] I2C scan:"));
  uint8_t found = 0;
  for (uint8_t addr = 1; addr < 127; addr++) {
    Wire.beginTransmission(addr);
    if (Wire.endTransmission() == 0) {
      Serial.printf("  - 0x%02X\n", addr);
      found++;
    }
  }
  if (found == 0) {
    Serial.println(F("  (khong thay thiet bi — kiem tra SDA/SCL)"));
  }
}

bool probeLcdAddress(uint8_t addr) {
  Wire.beginTransmission(addr);
  return Wire.endTransmission() == 0;
}

bool initLcdHardware() {
  Wire.begin(LCD_SDA_PIN, LCD_SCL_PIN);
  Wire.setClock(100000);
  Wire.setTimeOut(50);
  delay(100);
  scanI2cBus();

  uint8_t addr = LCD_I2C_ADDR;
  if (!probeLcdAddress(addr) && probeLcdAddress(LCD_I2C_ADDR_ALT)) {
    addr = LCD_I2C_ADDR_ALT;
    Serial.printf("[LCD] Dung dia chi thay the 0x%02X\n", addr);
  }

  if (!probeLcdAddress(addr)) {
    Serial.println(F("[LCD] Khong tim thay module I2C"));
    return false;
  }

  lcd.begin(addr);
  lcd.backlight(true);
  lcd.clear();
  delay(50);
  lcdReady = true;
  Serial.printf("[LCD] Khoi tao OK tai 0x%02X\n", addr);
  return true;
}

void requestLcdUpdate() {
  lcdUpdatePending = true;
}

// Khớp công thức app Flutter: ADC cao = khô hơn → % thấp hơn.
int adcToPercent(int raw) {
  const int maxAdc = 4095;
  if (raw < 0) raw = 0;
  if (raw > maxAdc) raw = maxAdc;
  return (int)round((1.0f - (float)raw / (float)maxAdc) * 100.0f);
}

bool isRelaySettling() {
  return pumpRelayChangedMs > 0 &&
         (millis() - pumpRelayChangedMs) < PUMP_RELAY_SETTLE_MS;
}

void buildDefaultLcdLines(char *line1, char *line2) {
  float humidity = sensorCache.fresh ? sensorCache.humidity : dht.readHumidity();
  float temp = sensorCache.fresh ? sensorCache.temp : dht.readTemperature();
  int soilPct = adcToPercent(sensorCache.fresh ? sensorCache.soil : analogRead(SOIL_PIN));
  int rainPct = adcToPercent(sensorCache.fresh ? sensorCache.rain : analogRead(RAIN_PIN));

  int tVal = isnan(temp) ? -1 : (int)round(temp);
  int hVal = isnan(humidity) ? -1 : (int)round(humidity);

  if (tVal < 0 && hVal < 0) {
    snprintf(line1, 17, "T:--C H:--%%");
  } else if (tVal < 0) {
    snprintf(line1, 17, "T:--C H:%d%%", hVal);
  } else if (hVal < 0) {
    snprintf(line1, 17, "T:%dC H:--%%", tVal);
  } else {
    snprintf(line1, 17, "T:%dC H:%d%%", tVal, hVal);
  }

  snprintf(line2, 17, "Dat:%d%% Mua:%d%%", soilPct, rainPct);
}

void composeLcdLines() {
  if (lcdMode == LCD_MODE_PROCESSING) {
    strncpy(lcdLine1, "Dang xu ly", sizeof(lcdLine1));
    lcdLine1[sizeof(lcdLine1) - 1] = '\0';
    lcdLine2[0] = '\0';
    return;
  }
  if (lcdMode == LCD_MODE_HEALTH) {
    strncpy(lcdLine1, healthLine1, sizeof(lcdLine1));
    strncpy(lcdLine2, healthLine2, sizeof(lcdLine2));
    lcdLine1[sizeof(lcdLine1) - 1] = '\0';
    lcdLine2[sizeof(lcdLine2) - 1] = '\0';
    return;
  }
  if (lcdMode == LCD_MODE_ERROR) {
    strncpy(lcdLine1, errorLine1, sizeof(lcdLine1));
    strncpy(lcdLine2, errorLine2, sizeof(lcdLine2));
    lcdLine1[sizeof(lcdLine1) - 1] = '\0';
    lcdLine2[sizeof(lcdLine2) - 1] = '\0';
    return;
  }
  buildDefaultLcdLines(lcdLine1, lcdLine2);
}

void flushLcdIfNeeded(bool force) {
  if (!lcdReady) return;
  if (isRelaySettling()) return;

  composeLcdLines();
  if (!force && strncmp(lcdLine1, lastLcdLine1, sizeof(lcdLine1)) == 0 &&
      strncmp(lcdLine2, lastLcdLine2, sizeof(lcdLine2)) == 0) {
    return;
  }

  if (!lcd.printLine(0, lcdLine1) || !lcd.printLine(1, lcdLine2)) {
    Serial.println(F("[LCD] I2C write failed — skip update"));
    return;
  }
  strncpy(lastLcdLine1, lcdLine1, sizeof(lastLcdLine1));
  strncpy(lastLcdLine2, lcdLine2, sizeof(lastLcdLine2));
}

void setHealthDisplay(const String &line1, const String &line2) {
  copyLcdText(healthLine1, sizeof(healthLine1), line1);
  copyLcdText(healthLine2, sizeof(healthLine2), line2);
  lcdMode = LCD_MODE_HEALTH;
  healthDisplayUntilMs = millis() + HEALTH_DISPLAY_MS;
  requestLcdUpdate();
}

void setErrorDisplay(const String &line1, const String &line2) {
  copyLcdText(errorLine1, sizeof(errorLine1), line1);
  copyLcdText(errorLine2, sizeof(errorLine2), line2);
  lcdMode = LCD_MODE_ERROR;
  errorDisplayUntilMs = millis() + 10000;
  requestLcdUpdate();
}

void updateLcdModeTimer() {
  unsigned long now = millis();
  if (lcdMode == LCD_MODE_HEALTH && healthDisplayUntilMs > 0 && now >= healthDisplayUntilMs) {
    lcdMode = LCD_MODE_DEFAULT;
    healthDisplayUntilMs = 0;
    requestLcdUpdate();
  }
  if (lcdMode == LCD_MODE_ERROR && errorDisplayUntilMs > 0 && now >= errorDisplayUntilMs) {
    lcdMode = LCD_MODE_DEFAULT;
    errorDisplayUntilMs = 0;
    requestLcdUpdate();
  }
}

// -------------------- WiFiManager ---------------------
void connectWiFi() {
  WiFi.mode(WIFI_STA);
  WiFi.setSleep(false);
  wm.setConfigPortalTimeout(180);

  Serial.println(F("[WiFi] Starting WiFiManager..."));
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

void ensureWiFiConnected() {
  if (WiFi.status() == WL_CONNECTED) return;

  unsigned long now = millis();
  if (now - lastWiFiRetryMs < WIFI_RETRY_INTERVAL_MS) return;
  lastWiFiRetryMs = now;

  Serial.println(F("[WiFi] Disconnected, reconnecting..."));
  WiFi.reconnect();
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

// -------------------- Relay / shade / pump ------------
bool isPumpOutputOn() {
  const bool pinHigh = PUMP_ACTIVE_HIGH ? HIGH : LOW;
  return digitalRead(PUMP_PIN) == pinHigh;
}

void applyPumpOutput() {
  const bool wasOn = isPumpOutputOn();
  const bool pinHigh = PUMP_ACTIVE_HIGH ? wantPumpOn : !wantPumpOn;
  digitalWrite(PUMP_PIN, pinHigh ? HIGH : LOW);
  if (wasOn != wantPumpOn) {
    pumpRelayChangedMs = millis();
    yield();
  }
}

void processPendingRelayApply() {
  if (!relayApplyPending) return;
  relayApplyPending = false;
  applyPumpOutput();
  applyShadeOutput();
}

void startShadeMove(bool open) {
  if (open == isCoverOpen) return;
  if (stepperRunning) return;

  int openDir = REVERSE_SHADE_DIRECTION ? -1 : 1;
  int closeDir = -openDir;

  stepperDirection = open ? openDir : closeDir;
  stepperRemaining = SHADE_TRAVEL_STEPS;
  stepperRunning = true;

  Serial.printf("[SHADE] Start %s, steps=%ld, dir=%d\n",
                open ? "OPEN" : "CLOSE",
                stepperRemaining,
                stepperDirection);
}

void updateStepper() {
  if (!stepperRunning || stepperRemaining <= 0) return;

  unsigned long now = millis();
  if (now - lastStepperStepMs < STEPPER_STEP_INTERVAL_MS) return;
  lastStepperStepMs = now;

  myStepper.step(stepperDirection);
  stepperRemaining--;

  if (stepperRemaining <= 0) {
    stepperRunning = false;
    isCoverOpen = wantShadeOpen;
    Serial.printf("[SHADE] Done. isCoverOpen=%d\n", (int)isCoverOpen);
  }
}

void applyShadeOutput() {
  if (wantShadeOpen != isCoverOpen) {
    startShadeMove(wantShadeOpen);
  }
}

bool publishRelaySet(int relayId, bool state, const char *relayName) {
  if (!mqttClient.connected()) return false;

  DynamicJsonDocument doc(256);
  doc["relay_id"] = relayId;
  doc["state"] = state;
  doc["relay_name"] = relayName;
  doc["triggered_by"] = "esp32_button";
  doc["device_id"] = DEVICE_ID;

  String json;
  serializeJson(doc, json);
  bool ok = mqttClient.publish(MQTT_TOPIC_RELAY_SET, json.c_str(), false);
  Serial.printf("[MQTT] Publish relay/set: %s (%s)\n", json.c_str(), ok ? "ok" : "fail");
  return ok;
}

void handleShadeButton() {
  if (stepperRunning) {
    Serial.println(F("[BTN] Shade ignored — stepper running"));
    return;
  }

  wantShadeOpen = !wantShadeOpen;
  applyShadeOutput();
  publishRelaySet(1, wantShadeOpen, "Shade");
}

bool requestPumpSessionHttp() {
  if (WiFi.status() != WL_CONNECTED) return false;

  HTTPClient http;
  String url = String(SERVER_URL) + "/api/relay";
  http.begin(url);
  http.addHeader("Content-Type", "application/json");
  http.addHeader("X-API-KEY", API_KEY);

  DynamicJsonDocument body(256);
  body["action"] = "pump_start";
  body["triggered_by"] = "esp32_button";
  body["device_id"] = DEVICE_ID;
  body["duration_seconds"] = PUMP_SESSION_SECONDS;

  String payload;
  serializeJson(body, payload);

  int code = http.POST(payload);
  String response = http.getString();
  http.end();

  Serial.printf("[HTTP] pump_start -> %d: %s\n", code, response.c_str());
  return code == 202;
}

void pumpSessionTask(void *param) {
  (void)param;
  pumpSessionTaskRunning = true;

  bool ok = requestPumpSessionHttp();
  if (!ok) {
    Serial.println(F("[BTN] Pump session request failed"));
    setErrorDisplay("Bom that bai", "Thu lai sau");
  }

  pumpRequestPending = false;
  pumpSessionTaskRunning = false;
  vTaskDelete(nullptr);
}

void handlePumpButton() {
  if (wantPumpOn || pumpRequestPending || pumpSessionTaskRunning) {
    Serial.println(F("[BTN] Pump ignored — session active/pending"));
    return;
  }

  pumpRequestPending = true;
  xTaskCreate(
    pumpSessionTask,
    "pumpSession",
    8192,
    nullptr,
    1,
    nullptr
  );
}

void healthCheckTask(void *param) {
  (void)param;
  healthTaskRunning = true;

  bool success = false;
  String line1 = "Khong co ket qua";
  String line2 = "";

  if (WiFi.status() == WL_CONNECTED) {
    HTTPClient http;
    String url = String(SERVER_URL) + "/api/camera/health-check";
    http.begin(url);
    http.addHeader("Content-Type", "application/json");
    http.addHeader("X-API-KEY", API_KEY);
    http.setTimeout(60000);

    DynamicJsonDocument body(128);
    body["device_id"] = DEVICE_ID;
    body["model"] = HEALTH_CHECK_MODEL;
    String payload;
    serializeJson(body, payload);

    int code = http.POST(payload);
    String response = http.getString();
    http.end();

    if (code == 404) {
      Serial.println(F("[HTTP] health-check -> 404 (server chua co API — cap nhat camera.js + restart pm2)"));
    } else {
      Serial.printf("[HTTP] health-check -> %d: %.120s\n", code, response.c_str());
    }

    if (code == 200) {
      DynamicJsonDocument doc(2048);
      DeserializationError err = deserializeJson(doc, response);
      if (!err) {
        JsonObject lcdObj = doc["lcd"];
        if (!lcdObj.isNull()) {
          line1 = lcdObj["line1"] | line1;
          line2 = lcdObj["line2"] | line2;
        } else if (!doc["reply"].isNull()) {
          line1 = doc["reply"].as<String>();
        }
        success = true;
      }
    } else if (code == 409) {
      line1 = "Dang xu ly";
      line2 = "Vui long doi";
      success = true;
    }
  }

  if (success) {
    setHealthDisplay(line1, line2);
  } else {
    setErrorDisplay("Loi xu ly", "Kiem tra mang");
  }

  healthTaskRunning = false;
  vTaskDelete(nullptr);
}

void startHealthCheck() {
  if (healthTaskRunning) {
    Serial.println(F("[BTN] Health ignored — task running"));
    return;
  }

  lcdMode = LCD_MODE_PROCESSING;
  requestLcdUpdate();

  xTaskCreate(
    healthCheckTask,
    "healthCheck",
    12288,
    nullptr,
    1,
    nullptr
  );
}

void handleHealthButton() {
  if (healthTaskRunning) return;

  if (lcdMode == LCD_MODE_HEALTH) {
    healthDisplayUntilMs = millis() + HEALTH_DISPLAY_MS;
    return;
  }

  startHealthCheck();
}

// -------------------- Buttons -------------------------
bool updateDebouncedButton(DebouncedButton &btn) {
  bool reading = digitalRead(btn.pin) == HIGH;
  unsigned long now = millis();

  if (reading != btn.lastReading) {
    btn.lastChangeMs = now;
    btn.lastReading = reading;
  }

  if ((now - btn.lastChangeMs) < BTN_DEBOUNCE_MS) {
    return false;
  }

  if (reading == btn.stableState) {
    return false;
  }

  btn.stableState = reading;
  return btn.stableState == false;
}

void checkPhysicalButtons() {
  if (updateDebouncedButton(btnShade)) {
    handleShadeButton();
  }
  if (updateDebouncedButton(btnPump)) {
    handlePumpButton();
  }
  if (updateDebouncedButton(btnHealth)) {
    handleHealthButton();
  }
}

// -------------------- MQTT ----------------------------
void handleRelayStateArray(JsonArray arr) {
  for (JsonObject row : arr) {
    int rid = row["relay_id"] | 0;
    bool st = false;

    if (row["state"].is<int>()) st = row["state"].as<int>() != 0;
    else if (row["state"].is<bool>()) st = row["state"].as<bool>();

    if (rid == 1) wantShadeOpen = st;
    if (rid == 2) wantPumpOn = st;
  }

  Serial.printf("[MQTT] Desired state -> shade=%d, pump=%d\n", (int)wantShadeOpen, (int)wantPumpOn);
  relayApplyPending = true;
}

void onMqttMessage(char *topic, byte *payload, unsigned int length) {
  Serial.printf("[MQTT] Message on %s (%u bytes)\n", topic, length);

  DynamicJsonDocument doc(2048);
  DeserializationError err = deserializeJson(doc, payload, length);
  if (err) {
    Serial.printf("[MQTT] JSON parse error: %s\n", err.c_str());
    return;
  }

  if (String(topic) == MQTT_TOPIC_RELAY_STATE) {
    if (doc.is<JsonArray>()) {
      handleRelayStateArray(doc.as<JsonArray>());
      return;
    }
    if (doc["relay_status"].is<JsonArray>()) {
      handleRelayStateArray(doc["relay_status"].as<JsonArray>());
      return;
    }
    Serial.println(F("[MQTT] relay/state payload is not array"));
  }
}

void ensureMqttConnected() {
  if (WiFi.status() != WL_CONNECTED) return;
  if (mqttClient.connected()) return;

  unsigned long now = millis();
  if (now - lastMqttRetryMs < MQTT_RETRY_INTERVAL_MS) return;
  lastMqttRetryMs = now;

  Serial.println(F("[MQTT] Connecting..."));
  bool ok = mqttClient.connect(
    DEVICE_ID,
    DEVICE_ID,
    API_KEY,
    "garden/device/status",
    1,
    true,
    "{\"device_id\":\"esp32_garden_main\",\"status\":\"offline\"}"
  );

  if (!ok) {
    Serial.printf("[MQTT] Connect failed, rc=%d\n", mqttClient.state());
    return;
  }

  Serial.println(F("[MQTT] Connected"));
  mqttClient.subscribe(MQTT_TOPIC_RELAY_STATE, 1);
  mqttClient.publish(
    "garden/device/status",
    "{\"device_id\":\"esp32_garden_main\",\"status\":\"online\"}",
    true
  );
}

bool floatChanged(float previous, float current, float delta) {
  if (isnan(previous) && isnan(current)) return false;
  if (isnan(previous) != isnan(current)) return true;
  return fabs(previous - current) >= delta;
}

bool sensorChanged(float t, float h, int soil, int rain) {
  if (!hasPublishedSensor) return true;
  if (floatChanged(lastPublishedTemp, t, TEMP_DELTA)) return true;
  if (floatChanged(lastPublishedHumidity, h, HUMIDITY_DELTA)) return true;
  if (abs(lastPublishedSoil - soil) >= SOIL_DELTA) return true;
  if (abs(lastPublishedRain - rain) >= RAIN_DELTA) return true;
  return false;
}

void refreshSensorCache() {
  if (isRelaySettling()) return;

  sensorCache.humidity = dht.readHumidity();
  yield();
  sensorCache.temp = dht.readTemperature();
  yield();
  sensorCache.soil = analogRead(SOIL_PIN);
  sensorCache.rain = analogRead(RAIN_PIN);
  sensorCache.fresh = true;
}

void publishSensorDataIfChanged() {
  if (!sensorCache.fresh) return;

  const float h = sensorCache.humidity;
  const float t = sensorCache.temp;
  const int soil = sensorCache.soil;
  const int rain = sensorCache.rain;

  if (!sensorChanged(t, h, soil, rain)) return;

  DynamicJsonDocument doc(512);
  if (isnan(t)) doc["temperature"] = JsonVariant();
  else doc["temperature"] = t;
  if (isnan(h)) doc["humidity"] = JsonVariant();
  else doc["humidity"] = h;
  doc["soil_moisture"] = soil;
  doc["rain"] = rain;
  doc["device_id"] = DEVICE_ID;

  String json;
  serializeJson(doc, json);

  bool ok = mqttClient.publish(MQTT_TOPIC_SENSOR, json.c_str(), false);
  if (!ok) {
    Serial.println(F("[MQTT] Failed to publish sensor payload"));
  } else {
    hasPublishedSensor = true;
    lastPublishedTemp = t;
    lastPublishedHumidity = h;
    lastPublishedSoil = soil;
    lastPublishedRain = rain;
    Serial.printf("[MQTT] Published sensor: %s\n", json.c_str());
  }
}

// ===================== SETUP / LOOP =================
void setup() {
  Serial.begin(115200);
  delay(200);

  pinMode(WIFI_RESET_PIN, INPUT_PULLUP);
  pinMode(PUMP_PIN, OUTPUT);
  pinMode(BTN_SHADE_PIN, INPUT_PULLUP);
  pinMode(BTN_PUMP_PIN, INPUT_PULLUP);
  pinMode(BTN_HEALTH_PIN, INPUT_PULLUP);
  wantPumpOn = false;
  applyPumpOutput();

  myStepper.setSpeed(10);
  dht.begin();
  initLcdHardware();
  if (lcdReady) {
    lcd.printLine(0, "Khoi dong...");
    lcd.printLine(1, "");
  }

  connectWiFi();
  mqttClient.setServer(MQTT_HOST, MQTT_PORT);
  mqttClient.setCallback(onMqttMessage);
  mqttClient.setBufferSize(1024);

  applyPumpOutput();
  applyShadeOutput();
  requestLcdUpdate();
}

void loop() {
  checkWiFiResetButton();
  checkPhysicalButtons();
  processPendingRelayApply();
  ensureWiFiConnected();
  ensureMqttConnected();
  mqttClient.loop();
  updateStepper();
  updateLcdModeTimer();

  unsigned long now = millis();
  if (lcdUpdatePending) {
    lcdUpdatePending = false;
    flushLcdIfNeeded(true);
  } else if (lcdMode == LCD_MODE_DEFAULT && now - lastLcdRefreshMs >= LCD_REFRESH_INTERVAL_MS) {
    lastLcdRefreshMs = now;
    flushLcdIfNeeded(false);
  }

  if (WiFi.status() != WL_CONNECTED || !mqttClient.connected()) {
    yield();
    return;
  }

  if (now - lastSensorMs >= SENSOR_SAMPLE_INTERVAL_MS) {
    lastSensorMs = now;
    refreshSensorCache();
    publishSensorDataIfChanged();
    if (lcdMode == LCD_MODE_DEFAULT) {
      requestLcdUpdate();
    }
  }

  yield();
}
