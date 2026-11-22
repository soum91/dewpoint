/*
  DewPoint Bridge
  ESP32 firmware that listens to a Govee H5102 (or H5101/H5104/H5174/H5177/H5075) over
  Bluetooth and exposes it to Apple Home as a temperature, humidity and battery accessory.

  Libraries: HomeSpan 2.x, NimBLE-Arduino 2.x. Board core: arduino-esp32 3.x.

  First boot:
    1. Join Wi-Fi "HomeSpan-Setup" (password: homespan), enter your 2.4 GHz Wi-Fi and a setup code.
    2. Home app > + > Add Accessory > More options > "DewPoint Bridge".
  The bridge locks onto the strongest Govee sensor heard during the first 30 seconds and remembers it.
  Serial CLI (115200 baud): type @G to forget the locked sensor and pick again.
*/

#include "HomeSpan.h"
#include <NimBLEDevice.h>
#include <Preferences.h>

// ---- Optional config -------------------------------------------------------------
// Set to your sensor's exact Bluetooth name (shown in the DewPoint app, e.g. "GVH5102_9A4C")
// to skip auto-pick. Leave empty for auto.
#define SENSOR_NAME ""
// How long to listen before auto-picking the strongest sensor (ms).
#define PICK_WINDOW_MS 30000
// Mark the accessory as not responding if nothing is heard for this long (ms).
#define STALE_MS (10UL * 60UL * 1000UL)
// Minimum time between pushes to Home for each value (ms).
#define PUSH_INTERVAL_MS 15000
// -----------------------------------------------------------------------------------

static portMUX_TYPE dataMux = portMUX_INITIALIZER_UNLOCKED;
static volatile float gTemp = 0;
static volatile float gHum = 0;
static volatile int gBatt = 100;
static volatile uint32_t gSeq = 0;
static volatile uint32_t gLastHeardMs = 0;

static Preferences prefs;
static char lockedAddr[18] = "";   // MAC of the sensor we bridge (written once, before `locked` is set)
static char lockedName[32] = "";
static volatile bool locked = false;
static char bestAddr[18] = "";     // auto-pick candidate, guarded by dataMux
static char bestName[32] = "";
static volatile int bestRssi = -127;
static uint32_t bootMs = 0;

// ---- Govee advertisement parsing ---------------------------------------------------

static bool decodePacked(uint8_t a, uint8_t b, uint8_t c, float &t, float &h) {
  int32_t base = ((int32_t)a << 16) | ((int32_t)b << 8) | c;
  if (base == 0xFFFFFF) return false;
  bool neg = base & 0x800000;
  int32_t v = base & 0x7FFFFF;
  t = (float)(v / 1000) / 10.0f;
  if (neg) t = -t;
  h = (float)(v % 1000) / 10.0f;
  return t >= -40 && t <= 100 && h >= 0 && h <= 100;
}

// md = raw manufacturer data (2-byte little-endian company id + payload)
static bool parseGovee(const std::string &name, const std::string &md, float &t, float &h, int &batt) {
  if (md.size() < 3) return false;
  const uint8_t *b = (const uint8_t *)md.data();
  uint16_t company = b[0] | (b[1] << 8);
  const uint8_t *p = b + 2;
  size_t n = md.size() - 2;

  bool goveeName = name.rfind("GV", 0) == 0 || name.rfind("Govee", 0) == 0;
  if (!goveeName) return false;
  bool is5075 = name.find("H5072") != std::string::npos || name.find("H5075") != std::string::npos;

  if (n == 6 && (is5075 || company == 0xEC88)) {
    if (p[4] & 0x80) return false;
    batt = p[4] & 0x7F;
    return decodePacked(p[1], p[2], p[3], t, h);
  }
  if (n == 6) {  // H5100/H5101/H5102/H5104/H5174/H5177
    if (p[5] & 0x80) return false;
    batt = p[5] & 0x7F;
    return decodePacked(p[2], p[3], p[4], t, h);
  }
  return false;
}

// ---- BLE scanning --------------------------------------------------------------------

class ScanCallbacks : public NimBLEScanCallbacks {
  void onResult(const NimBLEAdvertisedDevice *dev) override {
    if (dev->getManufacturerDataCount() == 0) return;
    std::string name = dev->getName();
    float t, h; int batt;
    if (!parseGovee(name, dev->getManufacturerData(), t, h, batt)) return;

    std::string addr = dev->getAddress().toString();

    if (!locked) {
      // Still choosing: explicit name wins, otherwise track the strongest signal.
      int rssi = dev->getRSSI();
      bool take = strlen(SENSOR_NAME) > 0 ? (name == SENSOR_NAME) : (rssi > bestRssi);
      if (take) {
        portENTER_CRITICAL(&dataMux);
        strlcpy(bestAddr, addr.c_str(), sizeof(bestAddr));
        strlcpy(bestName, name.c_str(), sizeof(bestName));
        bestRssi = strlen(SENSOR_NAME) > 0 ? 0 : rssi;
        portEXIT_CRITICAL(&dataMux);
      }
      return;
    }
    if (strcasecmp(addr.c_str(), lockedAddr) != 0) return;

    portENTER_CRITICAL(&dataMux);
    gTemp = t; gHum = h; gBatt = batt;
    gSeq = gSeq + 1;
    gLastHeardMs = millis();
    portEXIT_CRITICAL(&dataMux);
  }

  void onScanEnd(const NimBLEScanResults &results, int reason) override {
    NimBLEDevice::getScan()->start(0, false, true);  // keep scanning forever
  }
};

static ScanCallbacks scanCallbacks;

static void startBLE() {
  NimBLEDevice::init("");
  NimBLEScan *scan = NimBLEDevice::getScan();
  scan->setScanCallbacks(&scanCallbacks, true);  // want duplicates: every advert is a new reading
  scan->setActiveScan(true);                      // some models put data in the scan response
  scan->setInterval(160);                         // leave radio time for Wi-Fi
  scan->setWindow(80);
  scan->setMaxResults(0);                         // don't store results, just callbacks
  scan->start(0, false, true);
}

// ---- HomeKit services ------------------------------------------------------------------

static bool isStale() {
  uint32_t last = gLastHeardMs;
  return last == 0 || (millis() - last) > STALE_MS;
}

struct GoveeTemperature : Service::TemperatureSensor {
  SpanCharacteristic *temp, *active;
  uint32_t seen = 0;
  GoveeTemperature() : Service::TemperatureSensor() {
    temp = new Characteristic::CurrentTemperature(20.0);
    temp->setRange(-40, 100);
    active = new Characteristic::StatusActive(0);
  }
  void loop() override {
    bool stale = isStale();
    if (active->getVal() == (int)stale) active->setVal(!stale);
    if (stale || gSeq == seen || temp->timeVal() < PUSH_INTERVAL_MS) return;
    portENTER_CRITICAL(&dataMux);
    float t = gTemp; seen = gSeq;
    portEXIT_CRITICAL(&dataMux);
    if (fabs(temp->getVal<float>() - t) >= 0.05f) temp->setVal(t);
  }
};

struct GoveeHumidity : Service::HumiditySensor {
  SpanCharacteristic *hum, *active;
  uint32_t seen = 0;
  GoveeHumidity() : Service::HumiditySensor() {
    hum = new Characteristic::CurrentRelativeHumidity(50.0);
    active = new Characteristic::StatusActive(0);
  }
  void loop() override {
    bool stale = isStale();
    if (active->getVal() == (int)stale) active->setVal(!stale);
    if (stale || gSeq == seen || hum->timeVal() < PUSH_INTERVAL_MS) return;
    portENTER_CRITICAL(&dataMux);
    float h = gHum; seen = gSeq;
    portEXIT_CRITICAL(&dataMux);
    if (fabs(hum->getVal<float>() - h) >= 0.5f) hum->setVal(h);
  }
};

struct GoveeBattery : Service::BatteryService {
  SpanCharacteristic *level, *low;
  uint32_t seen = 0;
  GoveeBattery() : Service::BatteryService() {
    level = new Characteristic::BatteryLevel(100);
    new Characteristic::ChargingState(2);  // not chargeable
    low = new Characteristic::StatusLowBattery(0);
  }
  void loop() override {
    if (isStale() || gSeq == seen || level->timeVal() < 60000) return;
    int b = gBatt; seen = gSeq;
    if (level->getVal() != b) level->setVal(b);
    int isLow = b <= 15 ? 1 : 0;
    if (low->getVal() != isLow) low->setVal(isLow);
  }
};

// ---- CLI ---------------------------------------------------------------------------------

static void forgetSensor(const char *) {
  prefs.remove("addr");
  prefs.remove("name");
  Serial.println("*** Forgot locked sensor. Rebooting to pick again...");
  delay(500);
  ESP.restart();
}

static void showSensor(const char *) {
  Serial.printf("Locked sensor: %s (%s)\n", locked ? lockedName : "none", locked ? lockedAddr : "-");
  Serial.printf("Last: %.1f C  %.1f%%  batt %d%%  heard %lus ago\n",
                (float)gTemp, (float)gHum, (int)gBatt,
                gLastHeardMs ? (unsigned long)((millis() - gLastHeardMs) / 1000) : 0UL);
}

// ---- Arduino -------------------------------------------------------------------------------

void setup() {
  Serial.begin(115200);
  prefs.begin("dewpoint", false);
  strlcpy(lockedAddr, prefs.getString("addr", "").c_str(), sizeof(lockedAddr));
  strlcpy(lockedName, prefs.getString("name", "").c_str(), sizeof(lockedName));
  locked = strlen(lockedAddr) > 0;
  bootMs = millis();

  homeSpan.enableAutoStartAP();
  homeSpan.setSketchVersion("1.0.0");
  homeSpan.begin(Category::Bridges, "DewPoint Bridge", "dewpoint");

  new SpanUserCommand('G', "- forget the locked Govee sensor and pick again", forgetSensor);
  new SpanUserCommand('g', "- show the locked Govee sensor and last reading", showSensor);

  new SpanAccessory();
    new Service::AccessoryInformation();
      new Characteristic::Identify();

  new SpanAccessory();
    new Service::AccessoryInformation();
      new Characteristic::Identify();
      new Characteristic::Name("Govee Thermometer");
      new Characteristic::Manufacturer("Govee");
      new Characteristic::Model("H5102");
    new GoveeTemperature();
    new GoveeHumidity();
    new GoveeBattery();

  startBLE();
  if (locked) Serial.printf("Bridging %s (%s)\n", lockedName, lockedAddr);
  else Serial.println("No sensor locked yet; listening for the strongest Govee sensor...");
}

void loop() {
  homeSpan.poll();

  if (!locked && (millis() - bootMs > PICK_WINDOW_MS || strlen(SENSOR_NAME) > 0)) {
    portENTER_CRITICAL(&dataMux);
    bool have = bestAddr[0] != 0;
    if (have) {
      strlcpy(lockedAddr, bestAddr, sizeof(lockedAddr));
      strlcpy(lockedName, bestName, sizeof(lockedName));
    }
    portEXIT_CRITICAL(&dataMux);
    if (have) {
      locked = true;
      prefs.putString("addr", lockedAddr);
      prefs.putString("name", lockedName);
      Serial.printf("Locked onto %s (%s), RSSI %d\n", lockedName, lockedAddr, (int)bestRssi);
    }
  }
}
