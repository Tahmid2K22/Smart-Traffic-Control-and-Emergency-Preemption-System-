/* Four-way BLE safety prototype. See docs/traffic_light_firmware.md.
 * Classic ESP32 only; NOT certified for public roads or mains wiring.
 * BLE callbacks only enqueue packets/lifecycle flags. loop() owns the controller,
 * JSON parsing, status characteristic, and all GPIO writes.
 */
#include <cstddef>
#include <cstdint>
#include <string>

namespace traffic {

enum class Direction { North, East, South, West, None };
enum class Light { Red, Yellow, Green };
enum class Mode { Manual, Auto };
enum class Phase { Green, Yellow, AllRed };

inline const char* name(Direction d) {
  switch (d) {
    case Direction::North: return "north";
    case Direction::East: return "east";
    case Direction::South: return "south";
    case Direction::West: return "west";
    default: return "";
  }
}
inline const char* name(Light l) {
  return l == Light::Green ? "green" : l == Light::Yellow ? "yellow" : "red";
}
inline const char* name(Mode m) { return m == Mode::Auto ? "auto" : "manual"; }
inline const char* name(Phase p) {
  return p == Phase::Green ? "green" : p == Phase::Yellow ? "yellow" : "all_red";
}
inline Direction direction(const std::string& s) {
  for (int i = 0; i < 4; ++i)
    if (s == name(static_cast<Direction>(i))) return static_cast<Direction>(i);
  return Direction::None;
}

// Framing only, not a JSON parser. ArduinoJson validates syntax afterwards.
// Reject trailing documents/junk and raw NULs instead of accepting a prefix.
inline bool singleObjectFrame(const char* data, size_t size) {
  bool started = false, closed = false, quoted = false, escaped = false;
  unsigned depth = 0;
  for (size_t i = 0; i < size; ++i) {
    const unsigned char c = static_cast<unsigned char>(data[i]);
    const bool whitespace = c == ' ' || c == '\t' || c == '\r' || c == '\n';
    if (!c) return false;
    if (!started) {
      if (whitespace) continue;
      if (c != '{') return false;
      started = true;
      depth = 1;
      continue;
    }
    if (closed) { if (!whitespace) return false; continue; }
    if (quoted) {
      if (c < 0x20) return false;
      if (escaped) escaped = false;
      else if (c == '\\') escaped = true;
      else if (c == '"') quoted = false;
    } else {
      if (c == '"') quoted = true;
      else if (c == '{' || c == '[') ++depth;
      else if (c == '}' || c == ']') {
        if (!depth) return false;
        if (--depth == 0) { if (c != '}') return false; closed = true; }
      } else if (c < 0x20 && !whitespace) return false;
    }
  }
  return started && closed && !quoted;
}

struct Command {
  int version = 0;
  std::string cmd, requestId, intersection, pass, role, uid, direction, light;
  int greenSec = 0, yellowSec = 0, allRedSec = 0;
};

// All methods are called by one owner (the Arduino loop), never BLE callbacks.
// Unsigned elapsed arithmetic supports millis() rollover. Call at least once
// per 2^32 milliseconds; each late tick advances at most one safety phase.
class Controller {
 public:
  static constexpr uint32_t ManualTimeoutMs = 120000;

  Controller(std::string intersection, std::string pass, uint32_t now = 0)
      : intersection_(intersection), pass_(pass), lastNow_(now),
        phaseStart_(now), lastControl_(now) {}

  bool configured() const {
    // Bound configuration so even maximally escaped 32-byte request IDs fit
    // in the <512-byte status envelope. These are Firestore document IDs,
    // not display names; all four documented seed IDs satisfy this rule.
    if (intersection_.empty() || intersection_ == "UNCONFIGURED" ||
        intersection_.size() > 32) return false;
    for (char c : intersection_)
      if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
            (c >= '0' && c <= '9') || c == '_' || c == '-')) return false;
    return true;
  }

  bool execute(const Command& c, uint32_t now) {
    clock(now);
    // Complete validation before changing authorization, timing or outputs.
    if (c.requestId.empty() || c.requestId.size() > 32)
      return reject("", "invalid_request_id");
    if (c.version != 2) return reject(c.requestId, "invalid_version");
    if (c.pass != pass_ || c.role != "traffic_police" || c.uid.empty())
      return reject(c.requestId, "unauthorized");
    if (c.cmd != "STATUS") {
      if (!configured()) return reject(c.requestId, "unconfigured");
      if (c.intersection != intersection_)
        return reject(c.requestId, "intersection_mismatch");
    }
    const bool set = c.cmd == "SET";
    const bool automatic = c.cmd == "AUTO";
    if (!set && !automatic && c.cmd != "ALL_RED" && c.cmd != "MANUAL" &&
        c.cmd != "STATUS") return reject(c.requestId, "unknown_command");
    Direction requested = traffic::direction(c.direction);
    if (set && requested == Direction::None)
      return reject(c.requestId, "invalid_direction");
    if (set && c.light != "red" && c.light != "yellow" && c.light != "green")
      return reject(c.requestId, "invalid_light");
    if (automatic && (c.greenSec < 5 || c.greenSec > 300 ||
                      c.yellowSec < 3 || c.yellowSec > 60 ||
                      c.allRedSec < 2 || c.allRedSec > 60))
      return reject(c.requestId, "invalid_timing");
    if ((set || automatic) && busy()) return reject(c.requestId, "busy");
    if (set && c.light == "yellow" &&
        (phase_ != Phase::Green || active_ != requested))
      return reject(c.requestId, "inactive_yellow");

    auth_ = true;
    ack_ = c.requestId;
    error_.clear();
    if (c.cmd != "STATUS") {
      lastControl_ = now;
      manualArmed_ = true;
      if (c.cmd == "ALL_RED" || c.cmd == "MANUAL") {
        safeIdle(now);
      } else if (automatic) {
        greenMs_ = static_cast<uint32_t>(c.greenSec) * 1000;
        yellowMs_ = static_cast<uint32_t>(c.yellowSec) * 1000;
        allRedMs_ = static_cast<uint32_t>(c.allRedSec) * 1000;
        mode_ = Mode::Auto;
        transfer(Direction::North, now);
      } else {
        mode_ = Mode::Manual;
        if (c.light == "green") {
          if (phase_ != Phase::Green || active_ != requested)
            transfer(requested, now);
        } else if (phase_ == Phase::Green && active_ == requested) {
          transfer(Direction::None, now);
        }
        // Red on an inactive direction is an output no-op, but switches to
        // manual and starts the inactivity timer like every accepted control.
      }
    }
    ++seq_;
    return true;
  }

  void tick(uint32_t now) {
    clock(now);
    if (mode_ == Mode::Manual && manualArmed_ &&
        elapsed(now, lastControl_) >= ManualTimeoutMs) {
      safeIdle(now);
      manualArmed_ = false;
      ++seq_;
      return;
    }
    if (phase_ == Phase::Green && mode_ == Mode::Auto &&
        elapsed(now, phaseStart_) >= greenMs_) {
      transfer(static_cast<Direction>((static_cast<int>(active_) + 1) % 4), now);
      ++seq_;
    } else if (phase_ == Phase::Yellow &&
               elapsed(now, phaseStart_) >= yellowMs_) {
      active_ = Direction::None;
      phase_ = Phase::AllRed;
      phaseStart_ = now;
      clearance_ = true;
      ++seq_;
    } else if (phase_ == Phase::AllRed && clearance_ &&
               elapsed(now, phaseStart_) >= allRedMs_) {
      clearance_ = false;
      active_ = pending_;
      pending_ = Direction::None;
      if (active_ != Direction::None) phase_ = Phase::Green;
      phaseStart_ = now;
      ++seq_;
    }
  }

  void disconnect(uint32_t now) {
    clock(now);
    safeIdle(now);
    manualArmed_ = false;
    auth_ = false;
    ack_.clear();
    error_.clear();
    ++seq_;
  }

  // Transport errors acknowledge any recoverable valid ID without executing
  // commands. They do not authorize a session or renew control timeouts.
  bool reject(const std::string& id, const std::string& error) {
    ack_ = id.size() <= 32 ? id : "";
    error_ = error;
    ++seq_;
    return false;
  }
  void heartbeat(uint32_t now) { clock(now); ++seq_; }

  Light light(Direction d) const {
    if (d == Direction::None || d != active_) return Light::Red;
    return phase_ == Phase::Green ? Light::Green : Light::Yellow;
  }
  bool busy() const { return phase_ == Phase::Yellow || clearance_; }
  Mode mode() const { return mode_; }
  Phase phase() const { return phase_; }
  Direction target() const {
    return phase_ == Phase::Green ? active_ : pending_;
  }
  bool auth() const { return auth_; }
  uint32_t seq() const { return seq_; }
  uint64_t uptime() const { return uptimeMs_ / 1000; }
  const std::string& intersection() const { return intersection_; }
  const std::string& ack() const { return ack_; }
  const std::string& error() const { return error_; }

 private:
  static uint32_t elapsed(uint32_t now, uint32_t since) { return now - since; }
  void clock(uint32_t now) {
    uptimeMs_ += elapsed(now, lastNow_);
    lastNow_ = now;
  }
  void safeIdle(uint32_t now) {
    mode_ = Mode::Manual;
    phase_ = Phase::AllRed;
    active_ = pending_ = Direction::None;
    clearance_ = false;
    phaseStart_ = now;
  }
  void transfer(Direction next, uint32_t now) {
    pending_ = next;
    phaseStart_ = now;
    if (phase_ == Phase::Green) {
      phase_ = Phase::Yellow;
    } else {
      phase_ = Phase::AllRed;
      active_ = Direction::None;
      clearance_ = true;
    }
  }

  std::string intersection_, pass_, ack_, error_;
  uint32_t lastNow_, phaseStart_, lastControl_;
  uint64_t uptimeMs_ = 0;
  uint32_t greenMs_ = 30000, yellowMs_ = 3000, allRedMs_ = 2000, seq_ = 0;
  Direction active_ = Direction::None, pending_ = Direction::None;
  Mode mode_ = Mode::Manual;
  Phase phase_ = Phase::AllRed;
  bool clearance_ = false, auth_ = false, manualArmed_ = false;
};

}  // namespace traffic

// Host tests compile the same controller without ESP32 dependencies.
#ifndef TRAFFIC_LIGHT_HOST_TEST
#include <Arduino.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLE2902.h>
#include <ArduinoJson.h>
#include <freertos/FreeRTOS.h>
#include <freertos/queue.h>
#include <freertos/task.h>
#include <cstring>

#if !defined(CONFIG_IDF_TARGET_ESP32)
#error "Pin mapping is for classic ESP32 only; audit pins before porting."
#endif

// Existing device identity, shared passcode and UUID values are preserved.
static const char* DEVICE_NAME = "ESP32-TrafficLight";
static const char* PASSCODE    = "TRAFFIC_POLICE_SECURE_PASS_2024";
static const char* SERVICE_UUID = "12345678-1234-1234-1234-123456789abc";
static const char* CMD_UUID     = "12345678-1234-1234-1234-123456789001";
static const char* STATUS_UUID  = "12345678-1234-1234-1234-123456789002";

// Set to the actual Firestore document ID, never its display name.
static const char INTERSECTION_ID[] = "UNCONFIGURED";
static_assert(sizeof(INTERSECTION_ID) <= 33, "Use a document ID of at most 32 bytes");
// Rows N,E,S,W; columns red,yellow,green. Active-high driver inputs.
static const uint8_t PINS[4][3] = {
  {25, 26, 27}, {14, 32, 33}, {18, 19, 21}, {22, 23, 13}
};
static constexpr uint32_t STATUS_PERIOD_MS = 2000;
static constexpr size_t PACKET_BYTES = 512;
static constexpr UBaseType_t QUEUE_DEPTH = 8;

struct Packet {
  uint32_t epoch;
  uint16_t size;
  char bytes[PACKET_BYTES];
};
static QueueHandle_t commandQueue = nullptr;
static portMUX_TYPE ingressMux = portMUX_INITIALIZER_UNLOCKED;
// Protected ingress metadata is not controller/GPIO state. Epochs invalidate
// queued packets across reconnects, including disconnect+connect between loops.
static uint32_t ingressEpoch = 0;
static bool ingressConnected = false, lifecycleChanged = false, overflow = false;
static Packet overflowPacket;
static uint32_t loopEpoch = 0;
static bool connected = false;
static BLECharacteristic* statusChar = nullptr;
static traffic::Controller controller(INTERSECTION_ID, PASSCODE);
static uint32_t lastPush = 0;

static void applyOutputs() {
  static bool initialized = false;
  static traffic::Light applied[4];
  bool changed = !initialized;
  for (int d = 0; d < 4; ++d)
    if (applied[d] != controller.light(static_cast<traffic::Direction>(d))) changed = true;
  if (!changed) return;  // Rejections/heartbeats must not pulse active lamps.
  for (int d = 0; d < 4; ++d)
    applied[d] = controller.light(static_cast<traffic::Direction>(d));
  initialized = true;
  // Break before make, including the physical write ordering. No callback can
  // interleave a different desired state while these GPIO writes are in flight.
  for (int d = 0; d < 4; ++d) {
    digitalWrite(PINS[d][1], LOW);
    digitalWrite(PINS[d][2], LOW);
  }
  for (int d = 0; d < 4; ++d) {
    const traffic::Light light = controller.light(static_cast<traffic::Direction>(d));
    digitalWrite(PINS[d][0], light == traffic::Light::Red ? HIGH : LOW);
  }
  for (int d = 0; d < 4; ++d) {
    const traffic::Light light = controller.light(static_cast<traffic::Direction>(d));
    if (light == traffic::Light::Yellow) digitalWrite(PINS[d][1], HIGH);
    if (light == traffic::Light::Green) digitalWrite(PINS[d][2], HIGH);
  }
}

static void publishStatus(uint32_t now) {
  applyOutputs();
#if ARDUINOJSON_VERSION_MAJOR >= 7
  JsonDocument doc;
#else
  StaticJsonDocument<1536> doc;
#endif
  doc["v"] = 2;
  doc["intersection"] = INTERSECTION_ID;
  for (int d = 0; d < 4; ++d) {
    const auto dir = static_cast<traffic::Direction>(d);
    doc["lights"][traffic::name(dir)] = traffic::name(controller.light(dir));
  }
  doc["mode"] = traffic::name(controller.mode());
  doc["phase"] = traffic::name(controller.phase());
  doc["target"] = traffic::name(controller.target());
  doc["uptime"] = controller.uptime();
  doc["auth"] = controller.auth();
  doc["seq"] = controller.seq();
  doc["ack"] = controller.ack().c_str();
  doc["error"] = controller.error().c_str();
  char payload[PACKET_BYTES];
  size_t size;
  if (doc.overflowed() || measureJson(doc) >= sizeof(payload)) {
    // Fail closed, but still replace READ with a truthful, bounded snapshot.
    controller.disconnect(now);
    controller.reject("", "status_failure");
    applyOutputs();
    size = snprintf(payload, sizeof(payload),
        "{\"v\":2,\"intersection\":\"%s\",\"lights\":{\"north\":\"red\","
        "\"east\":\"red\",\"south\":\"red\",\"west\":\"red\"},\"mode\":\"manual\","
        "\"phase\":\"all_red\",\"target\":\"\",\"uptime\":%llu,\"auth\":false,"
        "\"seq\":%lu,\"ack\":\"\",\"error\":\"status_failure\"}",
        INTERSECTION_ID, static_cast<unsigned long long>(controller.uptime()),
        static_cast<unsigned long>(controller.seq()));
    Serial.println("[FAULT] Status serialization failed; outputs all red");
  } else {
    size = serializeJson(doc, payload, sizeof(payload));
  }
  if (statusChar) {
    // READ is refreshed even without a connected/subscribed client.
    statusChar->setValue(reinterpret_cast<uint8_t*>(payload), size);
    if (connected) statusChar->notify();
  }
  lastPush = now;
}

static bool stringField(JsonVariantConst value, std::string& out) {
  if (!value.is<const char*>()) return false;
  const JsonString s = value.as<JsonString>();
  // Embedded NULs must not turn a mismatched pass/id into a matching prefix.
  if (!s.c_str() || strlen(s.c_str()) != s.size()) return false;
  out.assign(s.c_str(), s.size());
  return true;
}

static bool decode(const Packet& packet, traffic::Command& c, const char*& error) {
  error = "malformed_json";
  if (packet.size == 0 || packet.size >= PACKET_BYTES) {
    error = "invalid_packet_size";
    return false;
  }
#if ARDUINOJSON_VERSION_MAJOR >= 7
  JsonDocument doc;
#else
  StaticJsonDocument<2048> doc;
#endif
  if (!traffic::singleObjectFrame(packet.bytes, packet.size)) return false;
  if (deserializeJson(doc, packet.bytes, packet.size,
                      DeserializationOption::NestingLimit(4)) || !doc.is<JsonObject>())
    return false;
  // Recover a valid ID even when another field has the wrong type.
  stringField(doc["request_id"], c.requestId);
  if (c.requestId.empty() || c.requestId.size() > 32) {
    c.requestId.clear();
    error = "invalid_request_id";
    return false;
  }
  error = "invalid_fields";
  if (!doc["v"].is<int>() || !stringField(doc["cmd"], c.cmd) ||
      !stringField(doc["intersection"], c.intersection) ||
      !stringField(doc["pass"], c.pass) || !stringField(doc["role"], c.role) ||
      !stringField(doc["uid"], c.uid)) return false;
  c.version = doc["v"].as<int>();
  if (c.cmd == "SET" && (!stringField(doc["direction"], c.direction) ||
                          !stringField(doc["light"], c.light))) return false;
  if (c.cmd == "AUTO") {
    if (!doc["green_sec"].is<int>() || !doc["yellow_sec"].is<int>() ||
        !doc["all_red_sec"].is<int>()) return false;
    c.greenSec = doc["green_sec"].as<int>();
    c.yellowSec = doc["yellow_sec"].as<int>();
    c.allRedSec = doc["all_red_sec"].as<int>();
  }
  return true;
}

class ServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer*) override {
    portENTER_CRITICAL(&ingressMux);
    ++ingressEpoch;
    ingressConnected = true;
    lifecycleChanged = true;
    portEXIT_CRITICAL(&ingressMux);
  }
  void onDisconnect(BLEServer*) override {
    portENTER_CRITICAL(&ingressMux);
    ++ingressEpoch;
    ingressConnected = false;
    lifecycleChanged = true;
    portEXIT_CRITICAL(&ingressMux);
  }
};

class CommandCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* characteristic) override {
    // auto supports core 2.x std::string and core 3.x Arduino String getValue().
    const auto raw = characteristic->getValue();
    Packet packet = {};
    packet.size = raw.length() >= PACKET_BYTES ? PACKET_BYTES : raw.length();
    if (packet.size < PACKET_BYTES)
      memcpy(packet.bytes, raw.c_str(), packet.size);
    portENTER_CRITICAL(&ingressMux);
    packet.epoch = ingressEpoch;
    if (ingressConnected && !overflow &&
        xQueueSend(commandQueue, &packet, 0) != pdTRUE) {
      overflow = true;
      overflowPacket = packet;
      // Invalidate queued controls immediately, including an in-flight decode.
      ++ingressEpoch;
    }
    portEXIT_CRITICAL(&ingressMux);
  }
};

static void serviceIngress(uint32_t now) {
  bool changed, fault;
  Packet failed = {};
  portENTER_CRITICAL(&ingressMux);
  changed = lifecycleChanged;
  fault = overflow;
  connected = ingressConnected;
  loopEpoch = ingressEpoch;
  lifecycleChanged = false;
  overflow = false;
  if (fault) failed = overflowPacket;
  portEXIT_CRITICAL(&ingressMux);
  if (changed || fault) {
    controller.disconnect(now);
    if (fault && failed.epoch + 1 == loopEpoch) {
      traffic::Command c;
      const char* ignored;
      decode(failed, c, ignored);
      controller.reject(c.requestId, "queue_full");
    }
    publishStatus(now);
    if (!connected) BLEDevice::startAdvertising();
  }
}

static bool currentPacket(const Packet& packet) {
  portENTER_CRITICAL(&ingressMux);
  const bool current = ingressConnected && !lifecycleChanged && !overflow &&
                       packet.epoch == ingressEpoch;
  portEXIT_CRITICAL(&ingressMux);
  return current;
}

void setup() {
  Serial.begin(115200);
  // First disable every output; then assert all reds before enabling BLE.
  for (int d = 0; d < 4; ++d) {
    for (int l = 0; l < 3; ++l) {
      digitalWrite(PINS[d][l], LOW);
      pinMode(PINS[d][l], OUTPUT);
    }
  }
  applyOutputs();
  // Invalid deployment IDs must not create an oversized status envelope.
  if (!controller.configured() && strcmp(INTERSECTION_ID, "UNCONFIGURED") != 0) {
    Serial.println("[FAULT] ID must be 1..32 ASCII letters/digits/_/-; all red");
    return;
  }
  commandQueue = xQueueCreate(QUEUE_DEPTH, sizeof(Packet));
  if (!commandQueue) {
    Serial.println("[FAULT] Queue allocation failed; all red, BLE disabled");
    return;
  }
  BLEDevice::init(DEVICE_NAME);
  BLEDevice::setMTU(517);
  BLEServer* server = BLEDevice::createServer();
  server->setCallbacks(new ServerCallbacks());
  BLEService* service = server->createService(SERVICE_UUID);
  BLECharacteristic* cmdChar = service->createCharacteristic(
      CMD_UUID, BLECharacteristic::PROPERTY_WRITE);
  cmdChar->setCallbacks(new CommandCallbacks());
  statusChar = service->createCharacteristic(
      STATUS_UUID, BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY);
  statusChar->addDescriptor(new BLE2902());
  controller.heartbeat(millis());
  publishStatus(millis());
  service->start();
  BLEAdvertising* adv = BLEDevice::getAdvertising();
  adv->addServiceUUID(SERVICE_UUID);
  adv->setScanResponse(true);
  BLEDevice::startAdvertising();
}

void loop() {
  if (!statusChar) {
    vTaskDelay(1);  // Setup fault: remain all red, no commands accepted.
    return;
  }
  serviceIngress(millis());
  uint32_t now = millis();
  const uint32_t before = controller.seq();
  controller.tick(now);
  if (controller.seq() != before) publishStatus(now);

  Packet packet;
  // A bounded batch prevents writes from starving timers/disconnect handling.
  for (UBaseType_t i = 0; i < QUEUE_DEPTH &&
       xQueueReceive(commandQueue, &packet, 0) == pdTRUE; ++i) {
    serviceIngress(millis());
    if (!connected || packet.epoch != loopEpoch) continue;
    traffic::Command command;
    const char* error;
    const bool valid = decode(packet, command, error);
    if (!currentPacket(packet)) continue;
    now = millis();
    // A packet parse can straddle a deadline; safety timers take priority.
    const uint32_t seq = controller.seq();
    controller.tick(now);
    if (controller.seq() != seq) publishStatus(now);
    if (valid) controller.execute(command, now);
    else controller.reject(command.requestId, error);
    publishStatus(now);
  }
  serviceIngress(millis());
  now = millis();
  if (static_cast<uint32_t>(now - lastPush) >= STATUS_PERIOD_MS) {
    controller.heartbeat(now);
    publishStatus(now);
  }
  // Yield one scheduler tick for BLE/idle tasks, never sleep for a phase.
  // No wait loop or phase catch-up: every clearance runs in real time.
  vTaskDelay(1);
}

#endif  // TRAFFIC_LIGHT_HOST_TEST
