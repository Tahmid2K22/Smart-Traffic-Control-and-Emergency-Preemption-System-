/*
 * ESP32 Four-Way Traffic Light — Firebase Realtime Database control.
 * Simple version: Wi-Fi + RTDB only (no Bluetooth). Library: ArduinoJson.
 *
 * ── CONFIGURE BEFORE FLASHING ──────────────────────────────────────────────
 * 1. WIFI_SSID / WIFI_PASSWORD      — your 2.4 GHz Wi-Fi
 * 2. DB_URL                         — Firebase console > Realtime Database URL
 * 3. DB_SECRET                      — Project settings > Service accounts >
 *                                     Database secrets (legacy token)
 * 4. INTERSECTION_ID                — any id you like (also used by the app)
 *
 * How it stays cheap on Firebase:
 *  - The board holds ONE persistent SSE stream on the command node.
 *    Commands arrive instantly. No polling, no extra reads.
 *  - The app writes only when a button is pressed.
 *  - The board writes status only when it changes, plus a small
 *    heartbeat every STATUS_INTERVAL_MS (default 5 s).
 *
 * Data model (Realtime Database):
 *   traffic/<INTERSECTION_ID>/command = {
 *     "action": "auto" | "manual" | "green" | "allred" | "set",
 *     "direction": "north|east|south|west",   // green + set
 *     "color": "green|yellow|red",            // set only (police preemption)
 *     "green_sec": 30, "yellow_sec": 3, "all_red_sec": 2,  // auto only
 *     "id": <millisecond timestamp from the app>  // dedup counter
 *   }
 *   traffic/<INTERSECTION_ID>/status  = {
 *     "mode": "auto",              // always auto now
 *     "phase": "green|yellow|all_red",
 *     "lights": {"north":"red","east":"green","south":"red","west":"red"},
 *     "updated": <unix seconds>,
 *     "seq": <counter>
 *   }
 *
 * Safety rules: boot and reconnect start with an all-red clearance, then the
 * board always runs the AUTO cycle (N-E-S-W); at most one direction is ever
 * non-red; direction changes always run yellow -> all-red -> green; police
 * preemption only overrides one colour temporarily; commands older than the
 * last processed one are ignored.
 *
 * Bench prototype only. Not certified for real roads or mains wiring.
 */

#include <Arduino.h>
#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <time.h>
#include <ArduinoJson.h>

// ── User config ─────────────────────────────────────────────────────────────
#define WIFI_SSID        "Redmi 12"   // your Wi-Fi name
#define WIFI_PASSWORD    "1theke80"   // your Wi-Fi password
#define DB_URL           "https://e-ambulance-system-001-default-rtdb.firebaseio.com"
#define DB_SECRET        ""          // legacy database secret; empty = open bench rules
#define INTERSECTION_ID  "khulna_royal_mor"

#define STATUS_INTERVAL_MS  5000

// ── Traffic light GPIO wiring ───────────────────────────────────────────────
// 12 LEDs total (4 directions x red/yellow/green), active-HIGH (through a
// current-limiting resistor, e.g. 220R, to each LED's anode).
//
//   Direction | Red  | Yellow | Green
//   ----------+------+--------+------
//   North     | GPIO25 | GPIO26 | GPIO27
//   East      | GPIO14 | GPIO32 | GPIO33
//   South     | GPIO18 | GPIO19 | GPIO21
//   West      | GPIO22 | GPIO23 | GPIO13
//
static const uint8_t LED_PINS[4][3] = {
  {25, 26, 27},   // north  {red, yellow, green}
  {14, 32, 33},   // east   {red, yellow, green}
  {18, 19, 21},   // south  {red, yellow, green}
  {22, 23, 13},   // west   {red, yellow, green}
};
static const char* const DIR_NAMES[4]   = {"north", "east", "south", "west"};
static const char* const LIGHT_NAMES[3] = {"red", "yellow", "green"};

static const char* DB_HOST = DB_URL + 8;  // strip "https://"

// Path suffix: append "?auth=<secret>" only when a secret is configured.
// With the open bench rules (docs/rtdb.traffic.rules.json) none is needed.
static void makePath(const char* node, char* out, size_t cap) {
  if (DB_SECRET[0] != 0) {
    snprintf(out, cap, "/traffic/%s/%s.json?auth=%s",
             INTERSECTION_ID, node, DB_SECRET);
  } else {
    snprintf(out, cap, "/traffic/%s/%s.json", INTERSECTION_ID, node);
  }
}

// ── Signal state ────────────────────────────────────────────────────────────
// The board is ALWAYS in AUTO mode: it boots straight into the cycle (starting
// from an all-red clearance) and keeps cycling even with no app connected.
// Police commands only preempt colours temporarily; the cycle resumes after.
enum Phase : uint8_t { PH_ALL_RED, PH_GREEN, PH_YELLOW };

static Phase    phase    = PH_ALL_RED;
static int8_t   active   = -1;   // direction that is green/yellow, -1 none
static int8_t   pending  = -1;   // direction that becomes green next, -1 idle
static uint32_t phaseStart = 0, lastStatusMs = 0;
static uint32_t greenMs = 30000, yellowMs = 3000, allRedMs = 2000;
static uint32_t seq = 0;
static long long lastCmdId = 0;
static bool     statusDirty = true;

static WiFiClientSecure streamClient;
static bool     streamUp = false;
static char     lineBuf[600];
static size_t   lineLen = 0;
static char     sseData[600];
static bool     sseHasData = false;

static bool busy() { return phase == PH_YELLOW || (phase == PH_ALL_RED && pending >= 0); }

static int dirIndex(const char* s) {
  for (int i = 0; i < 4; ++i) if (!strcmp(s, DIR_NAMES[i])) return i;
  return -1;
}

static void applyOutputs() {
  for (int d = 0; d < 4; ++d) {
    int light = 0;  // red
    if (d == active) light = (phase == PH_GREEN) ? 2 : (phase == PH_YELLOW ? 1 : 0);
    for (int l = 0; l < 3; ++l) digitalWrite(LED_PINS[d][l], l == light ? HIGH : LOW);
  }
}

// ── State changes ───────────────────────────────────────────────────────────
static void goAllRedIdle() {
  active = -1;
  pending = -1;
  phase = PH_ALL_RED;
  applyOutputs();
  statusDirty = true;
}

static void startTransfer(int next) {
  if (phase == PH_GREEN) {
    phase = PH_YELLOW;         // current green gets yellow first
  } else {
    phase = PH_ALL_RED;        // idle: fresh all-red clearance
  }
  phaseStart = millis();
  pending = next;
  applyOutputs();
  statusDirty = true;
}

static void executeAction(const JsonObject& cmd) {
  const char* action = cmd["action"] | "";
  const char* dir = cmd["direction"] | "";
  long long id = cmd["id"] | 0LL;
  if (action[0] == 0 || id == 0) return;
  if (id <= lastCmdId) return;  // stale or replayed command
  lastCmdId = id;
  Serial.printf("[traffic] command: %s %s (id=%lld)\n", action, dir, id);

  if (!strcmp(action, "allred") || !strcmp(action, "manual")) {
    // Force all-red now, then the cycle resumes from the next direction.
    goAllRedIdle();
    pending = (active >= 0) ? (active + 1) % 4 : 0;
    return;
  }
  if (!strcmp(action, "auto")) {
    // (Re)start the AUTO cycle from an all-red clearance. Durations have no
    // upper limit; non-positive or missing values keep the current/default.
    if (busy()) return;        // never interrupt a change mid-way
    long g = cmd["green_sec"] | 30L;
    long y = cmd["yellow_sec"] | 3L;
    long a = cmd["all_red_sec"] | 2L;
    if (g < 1) g = 30;
    if (y < 1) y = 3;
    if (a < 1) a = 2;
    greenMs = g * 1000UL;
    yellowMs = y * 1000UL;
    allRedMs = a * 1000UL;
    startTransfer(0);          // all-red clearance, then north, E, S, W, ...
    return;
  }
  if (!strcmp(action, "green")) {
    // Preempt: give one direction green (safe transfer), cycle resumes after.
    if (busy()) return;
    int d = dirIndex(dir);
    if (d < 0) return;
    if (phase == PH_GREEN && d == active) return;  // already green: no-op
    startTransfer(d);
    return;
  }
  if (!strcmp(action, "set")) {
    // Police preemption: force one direction to a specific colour.
    // Safety unchanged: at most one direction is ever non-red. The AUTO
    // cycle always resumes after the preempted state ends.
    int d = dirIndex(dir);
    if (d < 0) return;
    const char* color = cmd["color"] | "";
    if (!strcmp(color, "green")) {
      if (busy()) return;
      if (phase == PH_GREEN && d == active) return;  // already green
      startTransfer(d);            // yellow/all-red clearance, then green
      return;
    }
    if (!strcmp(color, "yellow")) {
      // Only the active direction may be switched to yellow while it is
      // green; from all-red idle any direction can start a yellow.
      if (busy()) return;
      if (phase == PH_GREEN && d != active) return;
      active = d;
      phase = PH_YELLOW;
      phaseStart = millis();
      pending = -1;                // yellow ends into all-red, then resume
      applyOutputs();
      statusDirty = true;
      return;
    }
    if (!strcmp(color, "red")) {
      // A red direction is already red (no-op); taking the active one
      // down ends into all-red clearance, then the cycle resumes.
      if (active == d) {
        goAllRedIdle();
        pending = (d + 1) % 4;
      }
      return;
    }
  }
}

// ── Status upload (PUT; only when changed or on heartbeat) ──────────────────
static void publishStatus() {
  if (WiFi.status() != WL_CONNECTED) return;

  char path[160];
  makePath("status", path, sizeof(path));

  String body = "{\"mode\":\"auto\",\"phase\":\"";
  body += phase == PH_GREEN ? "green" : (phase == PH_YELLOW ? "yellow" : "all_red");
  body += "\",\"lights\":{";
  for (int d = 0; d < 4; ++d) {
    int light = 0;
    if (d == active) light = (phase == PH_GREEN) ? 2 : (phase == PH_YELLOW ? 1 : 0);
    if (d) body += ',';
    body += '"';
    body += DIR_NAMES[d];
    body += "\":\"";
    body += LIGHT_NAMES[light];
    body += '"';
  }
  body += "},\"updated\":";
  body += (long long)time(nullptr);
  body += ",\"seq\":";
  body += (uint32_t)++seq;
  body += '}';

  WiFiClientSecure client;
  client.setInsecure();  // bench prototype; pin a CA cert for production
  if (!client.connect(DB_HOST, 443)) return;
  client.printf("PUT %s HTTP/1.1\r\nHost: %s\r\nContent-Type: application/json\r\n"
                "Content-Length: %d\r\nConnection: close\r\n\r\n%s",
                path, DB_HOST, body.length(), body.c_str());
  // Drain just the status line; the socket is discarded right after.
  String statusLine = client.readStringUntil('\n');
  client.stop();
  (void)statusLine;
}

// ── SSE stream (one persistent connection to the command node) ──────────────
static bool streamStart() {
  streamClient.stop();
  lineLen = 0;
  sseHasData = false;

  streamClient.setInsecure();  // bench prototype; pin a CA cert for production
  if (!streamClient.connect(DB_HOST, 443)) {
    Serial.println("[traffic] stream: TLS connect failed");
    return false;
  }

  char path[160];
  makePath("command", path, sizeof(path));
  streamClient.printf("GET %s HTTP/1.1\r\nHost: %s\r\n"
                      "Accept: text/event-stream\r\nConnection: keep-alive\r\n\r\n",
                      path, DB_HOST);

  // Read response headers.
  bool ok = false;
  while (streamClient.connected()) {
    String line = streamClient.readStringUntil('\n');
    line.trim();
    if (line.isEmpty()) break;
    if (line.startsWith("HTTP/") && line.indexOf(" 200 ") >= 0) ok = true;
  }
  if (!ok) {
    Serial.println("[traffic] stream: bad HTTP response");
    streamClient.stop();
    return false;
  }

  Serial.println("[traffic] stream: listening for commands");

  // The current command value is delivered as the first "put" event;
  // lastCmdId dedup decides whether it is a replay or a real command.
  streamUp = true;
  return true;
}

// Firebase RTDB EventSource sends plain raw SSE bytes: no Content-Length and
// no chunked transfer encoding, just "event:/data:" lines until disconnect.
static int nextByte() {
  if (!streamClient.connected()) return -1;
  if (streamClient.available() == 0) return -2;  // alive, nothing to read yet
  return streamClient.read();
}

static void sseDispatch() {
  if (!sseHasData) return;
  sseHasData = false;
  if (!strcmp(sseData, "null") || sseData[0] == 0) return;

  JsonDocument doc;
  DeserializationError err = deserializeJson(doc, sseData);
  if (err) {
    Serial.printf("[traffic] parse failed: %s\n", err.c_str());
    return;
  }
  long long id = doc["data"]["id"] | 0LL;  // 0LL: ids are 13-digit timestamps
  if (id == 0) return;
  // The connect-time "put" replays whatever command node value is stored.
  // A freshly booted board must start all-red, so ignore commands that were
  // created before boot (older than 60 s ago). Newer ones still execute.
  static bool firstPutSeen = false;
  if (!firstPutSeen) {
    firstPutSeen = true;
    long long nowSec = (long long)time(nullptr);
    if (nowSec < 1700000000LL || id < nowSec * 1000 - 60000) {
      lastCmdId = id;  // remember it so a reconnect replay is skipped too
      Serial.println("[traffic] ignoring pre-boot command (staying all-red)");
      return;
    }
  }
  JsonObject data = doc["data"].as<JsonObject>();
  if (data.isNull()) return;
  executeAction(data);
}

static void streamLoop() {
  if (!streamUp && !streamStart()) return;  // retried on every loop pass

  while (true) {
    if (!streamClient.connected()) { streamUp = false; break; }
    int c = nextByte();
    if (c == -2) break;                // connection alive, no data right now
    if (c < 0) { streamUp = false; break; }  // socket closed: reconnect
    if (c == '\n') {
      lineBuf[lineLen] = 0;
      if (lineLen == 0) {
        sseDispatch();                        // blank line ends the event
      } else if (!strncmp(lineBuf, "data:", 5)) {
        const char* p = lineBuf + 5;
        while (*p == ' ') ++p;
        strncpy(sseData, p, sizeof(sseData) - 1);
        sseData[sizeof(sseData) - 1] = 0;
        sseHasData = true;
      }
      lineLen = 0;
    } else if (c != '\r') {
      if (lineLen + 1 < sizeof(lineBuf)) lineBuf[lineLen++] = (char)c;
      else lineLen = 0;                       // oversize line: drop it
    }
  }
  if (!streamClient.connected()) streamUp = false;
}

// ── Setup / loop ────────────────────────────────────────────────────────────
void setup() {
  for (auto& row : LED_PINS)
    for (int pin : row) {
      pinMode(pin, OUTPUT);
      digitalWrite(pin, LOW);
    }

  Serial.begin(115200);
  Serial.printf("\n[traffic] intersection=%s\n", INTERSECTION_ID);

  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  Serial.print("[traffic] connecting Wi-Fi");
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print('.');
  }
  Serial.printf(" ok, %s\n", WiFi.localIP().toString().c_str());

  // NTP for absolute timestamps in status — must come AFTER Wi-Fi is up,
  // otherwise the SNTP UDP socket races the lwIP stack and can assert-crash.
  configTime(6 * 3600, 0, "pool.ntp.org", "time.nist.gov");  // GMT+6 Dhaka

  applyOutputs();  // boot: all red
  publishStatus();

  // No command needed: the board ALWAYS starts in AUTO mode — all-red
  // clearance first, then the north/east/south/west cycle. A newer stored
  // command (e.g. custom durations) still applies when the stream connects.
  startTransfer(0);
}

void loop() {
  uint32_t now = millis();

  // Wi-Fi upkeep — non-blocking. The signal state machine below ALWAYS runs,
  // so AUTO keeps cycling even while Wi-Fi is down; status upload and the
  // command stream simply pause and resume when the network comes back.
  if (WiFi.status() != WL_CONNECTED) {
    streamUp = false;
    static uint32_t lastReconnectMs = 0;
    if (now - lastReconnectMs >= 5000) {
      lastReconnectMs = now;
      WiFi.reconnect();
    }
  } else {
    streamLoop();
    // Re-capture: a command processed inside streamLoop() may set phaseStart
    // to a value NEWER than the `now` captured at the top of this pass. With
    // unsigned arithmetic, `now - phaseStart` would wrap to ~4.29e9 and
    // falsely trigger a phase transition on the very same pass.
    now = millis();
  }

  // Phase timing: green -> yellow -> all-red -> (next green in auto).
  if (phase == PH_GREEN && now - phaseStart >= greenMs) {
    phase = PH_YELLOW;
    phaseStart = now;
    applyOutputs();
    statusDirty = true;
  } else if (phase == PH_YELLOW && now - phaseStart >= yellowMs) {
    phase = PH_ALL_RED;
    phaseStart = now;
    if (active >= 0) pending = (active + 1) % 4;  // N E S W cycle resumes
    applyOutputs();
    statusDirty = true;
  } else if (phase == PH_ALL_RED && pending >= 0 && now - phaseStart >= allRedMs) {
    active = pending;
    pending = -1;
    phase = PH_GREEN;
    phaseStart = now;
    applyOutputs();
    statusDirty = true;
  }

  // Upload status only when it changed, or once per heartbeat interval.
  if (statusDirty || now - lastStatusMs >= STATUS_INTERVAL_MS) {
    statusDirty = false;
    lastStatusMs = now;
    publishStatus();
  }
}
