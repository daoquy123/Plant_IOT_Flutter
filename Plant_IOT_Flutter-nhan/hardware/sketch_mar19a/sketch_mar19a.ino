/*
 * ESP32 — DHT11 + soil + rain + pump + stepper (shade)
 * Realtime MQTT architecture (no HTTP polling).
 *
 * Libraries:
 *   - WiFiManager
 *   - PubSubClient
 *   - ArduinoJson v6+
 */

#include <WiFi.h>
#include <WiFiManager.h>
#include <PubSubClient.h>
#include <ArduinoJson.h>
#include <Wire.h>
#include "DHT.h"
#include <Stepper.h>

// ===================== USER CONFIG =====================
static const char *API_KEY = "a90cfc28468dc7b73eda44573bebb3a6d39981c92f449a9fc3cda4e56e113ce0";
static const char *DEVICE_ID = "esp32_garden_main";
static const int WIFI_RESET_PIN = 0;

// MQTT broker config (use your server IP/domain)
static const char *MQTT_HOST = "five-small-snowflake.site";
static const uint16_t MQTT_PORT = 1883;
static const char *MQTT_TOPIC_SENSOR = "garden/sensor";
static const char *MQTT_TOPIC_RELAY_STATE = "garden/relay/state";

static const unsigned long SENSOR_INTERVAL_MS = 60000;
static const unsigned long WIFI_RESET_HOLD_MS = 3000;
static const unsigned long WIFI_RETRY_INTERVAL_MS = 5000;
static const unsigned long MQTT_RETRY_INTERVAL_MS = 3000;
static const unsigned long STEPPER_STEP_INTERVAL_MS = 3;
static const int SHADE_TRAVEL_STEPS = 2048 * 9;

// ===== HARDWARE (giữ như project cũ) =====
#define DHTPIN 4
#define DHTTYPE DHT11
#define SOIL_PIN 34
#define RAIN_PIN 35
#define PUMP_PIN 18

const int stepsPerRevolution = 2048;
// NOTE: If shade motor rotates wrong direction, try reversing pin order:
// Current: Stepper(stepsPerRevolution, 13, 14, 12, 27);
// Reverse: Stepper(stepsPerRevolution, 27, 12, 14, 13);
Stepper myStepper(stepsPerRevolution, 13, 12, 14, 27);
DHT dht(DHTPIN, DHTTYPE);

const bool REVERSE_SHADE_DIRECTION = false;

bool isCoverOpen = false;
unsigned long lastSensorMs = 0;
unsigned long resetPressStart = 0;
unsigned long lastWiFiRetryMs = 0;
unsigned long lastMqttRetryMs = 0;
unsigned long lastStepperStepMs = 0;

bool wantShadeOpen = false;
bool wantPumpOn = false;

// Non-blocking stepper state
volatile long stepperRemaining = 0;
int stepperDirection = 1;
bool stepperRunning = false;

WiFiManager wm;
WiFiClient wifiClient;
PubSubClient mqttClient(wifiClient);

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

void applyPumpOutput() {
  digitalWrite(PUMP_PIN, wantPumpOn ? LOW : HIGH);
}

void startShadeMove(bool open) {
  if (open == isCoverOpen) return;

  // Prevent command churn while already moving.
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
    isCoverOpen = (stepperDirection > 0) ? !REVERSE_SHADE_DIRECTION : REVERSE_SHADE_DIRECTION;
    if (REVERSE_SHADE_DIRECTION) {
      isCoverOpen = !isCoverOpen;
    }
    // More reliable state after full move:
    isCoverOpen = wantShadeOpen;
    Serial.printf("[SHADE] Done. isCoverOpen=%d\n", (int)isCoverOpen);
  }
}

void applyShadeOutput() {
  if (wantShadeOpen != isCoverOpen) {
    startShadeMove(wantShadeOpen);
  }
}

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
  applyPumpOutput();
  applyShadeOutput();
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
    DEVICE_ID, // username (optional, can be ignored by broker)
    API_KEY,   // password
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

void publishSensorData() {
  float h = dht.readHumidity();
  float t = dht.readTemperature();
  int soil = analogRead(SOIL_PIN);
  int rain = analogRead(RAIN_PIN);

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
    Serial.printf("[MQTT] Published sensor: %s\n", json.c_str());
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
  mqttClient.setServer(MQTT_HOST, MQTT_PORT);
  mqttClient.setCallback(onMqttMessage);

applyPumpOutput();
applyShadeOutput();
}

void loop() {
  checkWiFiResetButton();
  ensureWiFiConnected();
  ensureMqttConnected();
  mqttClient.loop();
  updateStepper();

  if (WiFi.status() != WL_CONNECTED || !mqttClient.connected()) return;

  unsigned long now = millis();

  if (now - lastSensorMs >= SENSOR_INTERVAL_MS) {
    lastSensorMs = now;
    publishSensorData();
  }

  yield();
}
