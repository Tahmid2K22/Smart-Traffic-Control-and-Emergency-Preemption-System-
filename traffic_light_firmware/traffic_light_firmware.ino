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
 *     "action": "auto" | "manual" | "green" | "allred" | "set"
 *             | "ambulance" | "release",
 *     "direction": "north|east|south|west",   // green + set + ambulance
 *     "color": "green|yellow|red",            // set only (police preemption)
 *     "green_sec": 3, "yellow_sec": 3, "all_red_sec": 3,  // auto only
 *     "id": <millisecond timestamp from the app>  // dedup counter
 *   }
 *   traffic/<INTERSECTION_ID>/status  = {
 *     "mode": "auto",              // always auto now
 *     "phase": "green|yellow|all_red",
 *     "lights": {"north":"red","east":"green","south":"red","west":"red"},
 *     "priority": "ambulance" | "",  // ambulance preemption latched
 *     "updated": <unix seconds>,
 *     "seq": <counter>
 *   }
 *
 * Emergency escape (ambulance preemption): the driver requests it from the app
 * only while within ~1 km of the junction and only on an active trip. The
 * board latches that approach green (others red) and holds it until:
 *   1. the app sends "release" — automatic when the ambulance leaves the 1 km
 *      ring, or manually by the driver / a traffic officer, or
 *   2. the AMB_MAX_HOLD_MS watchdog fires (phone died, network gone).
 * While latched, police clicks and mode toggles are ignored.
 *
 * Safety rules: boot and reconnect start with an all-red clearance, then the
 * board always runs the AUTO cycle (N-E-S-W); at most one direction is ever
 * non-red; direction changes always run yellow -> all-red -> green; police
 * preemption only overrides one colour temporarily; commands older than the
 * last processed one are ignored.
 *
 * No Wi-Fi = no waiting. The AUTO cycle is started BEFORE Wi-Fi is attempted,
 * so a board with a missing or dead access point still cycles normally. Wi-Fi
 * is retried in the background, every socket call is time-bounded, and a
 * board that is associated but has no internet cannot stall the cycle either.
 * An escape can only arrive while the network is up — without it the board
 * simply stays in AUTO.
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
#define INTERSECTION_ID  "khulna_durbar_bangla"

#define STATUS_INTERVAL_MS  5000

// ── Network policy — the lights never wait on the network ───────────────────
// Wi-Fi gets a short, BOUNDED window at boot; if it is not up the AUTO cycle
// starts anyway and Wi-Fi is retried from loop(). Every socket operation is
// time-bounded too, so a board that is associated but has no internet (dead
// router, captive portal) cannot freeze the lights inside connect()/TLS.
#define WIFI_BOOT_WAIT_MS      8000UL  // max boot wait before AUTO runs alone
#define NET_CONNECT_TIMEOUT_MS 2000    // TCP connect budget (ms)
#define NET_HANDSHAKE_SEC      4       // TLS handshake budget (SECONDS)
#define NET_IO_TIMEOUT_MS      1000    // HTTP / SSE header read budget (ms)
#define STREAM_RETRY_MS        5000    // back-off after a FAILED connect
#define STREAM_RECONNECT_MS    1000    // retry after a LIVE stream dropped
#define NTP_VALID_EPOCH_SEC    1600000000LL  // time() below this = not synced

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
static uint32_t greenMs = 3000, yellowMs = 3000, allRedMs = 3000;
static uint32_t seq = 0;
static long long lastCmdId = 0;
static bool     statusDirty = true;

static WiFiClientSecure streamClient;
static bool     streamUp = false;
static char     lineBuf[600];
static size_t   lineLen = 0;
static char     sseData[600];
static bool     sseHasData = false;

// ── Emergency escape (ambulance preemption) ──────────────────────────────────
// Highest priority: the ambulance's approach is held green with every other
// direction red, frozen until the app sends "release" — automatically when
// the ambulance leaves the ~1 km ring, or manually by the driver or a
// traffic officer — or until the watchdog below fires (phone died / network
// gone). Police clicks and mode toggles are ignored while it is latched.
//
// The board has no GPS, so the 1 km range check lives in the app; the board
// only ever acts on the "ambulance" / "release" commands it receives.
#define AMB_MAX_HOLD_MS 90000UL   // watchdog: never hold a green forever
static bool     ambActive   = false;  // green frozen for the ambulance
static bool     ambTransfer = false;  // safe transfer (auto timers) in flight
static int8_t   ambQueued   = -1;     // arrived mid-transition: apply when free
static int8_t   ambDir      = -1;
static uint32_t ambStart    = 0;

// Network throttles — a dead connection must never become a busy-loop of
// blocking connect() calls (see the network policy defines above).
static uint32_t lastStreamAttemptMs = 0;
static uint32_t lastStatusAttemptMs = 0;
static uint32_t streamRetryMs = 0;   // 0 lets the very first attempt run at once

static void applyAmbulance(int d);
static void releaseAmbulance();

// Bounded socket setup: without these a board whose Wi-Fi is up but has no
// internet can sit inside connect()/TLS for tens of seconds and stall the
// lights mid-change.
static void configureTls(NetworkClientSecure& client) {
  client.setInsecure();                                // bench prototype
  client.setConnectionTimeout(NET_CONNECT_TIMEOUT_MS); // TCP connect, ms
  client.setHandshakeTimeout(NET_HANDSHAKE_SEC);       // TLS handshake, SECONDS
  client.setTimeout(NET_IO_TIMEOUT_MS);                // reads, ms
}

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

// ── Ambulance preemption (emergency escape) ──────────────────────────────────
// Give the ambulance's approach green as safely as possible: from all-red
// idle it is instant; if another arm is green the normal yellow -> all-red
// -> green transfer runs first, and ambTransfer keeps the AUTO timers alive
// until the target arm is reached — then the cycle freezes on it.
static void applyAmbulance(int d) {
  ambActive = true;
  ambQueued = -1;
  ambDir = d;
  ambStart = millis();
  if (phase == PH_GREEN && active == d) {
    ambTransfer = false;          // already green for this arm: just hold it
    statusDirty = true;
  } else if (phase == PH_GREEN) {
    ambTransfer = true;           // another arm is green: transfer, then hold
    startTransfer(d);
  } else if (busy()) {
    ambQueued = d;                // clearance in flight: apply once it settles
  } else {
    ambTransfer = false;          // all-red idle: instant green, others red
    active = d;
    phase = PH_GREEN;
    phaseStart = millis();
    pending = -1;
    applyOutputs();
    statusDirty = true;
  }
  Serial.printf("[traffic] ambulance preemption: %s green\n", DIR_NAMES[d]);
}

// End the latch — called when the app sends "release": automatically after
// the ambulance leaves the ~1 km ring, or manually by the driver or a
// traffic officer. The normal AUTO cycle resumes from all-red.
static void releaseAmbulance() {
  if (!ambActive && ambQueued < 0 && !ambTransfer) return;  // nothing held
  Serial.printf("[traffic] ambulance released (%s): AUTO cycle resumes\n",
                ambDir >= 0 ? DIR_NAMES[ambDir] : "-");
  ambActive = false;
  ambQueued = -1;
  ambTransfer = false;
  ambDir = -1;
  if (phase == PH_GREEN) {
    startTransfer(0);             // yellow -> all-red -> north, E, S, W, ...
  } else {
    // Yellow or all-red already in flight (possibly toward the ambulance
    // arm): steer it to north instead; the AUTO timers take it from there.
    pending = 0;
    statusDirty = true;
  }
}

static void executeAction(const JsonObject& cmd) {
  const char* action = cmd["action"] | "";
  const char* dir = cmd["direction"] | "";
  long long id = cmd["id"] | 0LL;
  if (action[0] == 0 || id == 0) return;
  if (id == lastCmdId) return;  // exact replay only
  lastCmdId = id;
  Serial.printf("[traffic] command: %s %s (id=%lld)\n", action, dir, id);

  // Emergency escape: highest priority. "release" is what ends the latch —
  // sent automatically when the ambulance leaves the ~1 km ring, or manually
  // by the driver / a traffic officer.
  if (!strcmp(action, "release")) {
    releaseAmbulance();
    return;
  }
  if (!strcmp(action, "ambulance")) {
    int d = dirIndex(dir);
    if (d < 0) return;
    ambDir = d;
    if (busy()) {                       // mid-change: apply once it settles
      ambQueued = d;
      Serial.println("[traffic] ambulance queued (busy)");
      return;
    }
    applyAmbulance(d);
    return;
  }
  // While the ambulance latch is held, every other command is ignored —
  // including police clicks and mode toggles.
  if (ambActive || ambQueued >= 0) {
    Serial.println("[traffic] ambulance priority: command ignored");
    return;
  }

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
    long g = cmd["green_sec"] | 3L;
    long y = cmd["yellow_sec"] | 3L;
    long a = cmd["all_red_sec"] | 3L;
    if (g < 1) g = 3;
    if (y < 1) y = 3;
    if (a < 1) a = 3;
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
// Returns true when the PUT was actually written. The caller throttles this
// to once per STATUS_INTERVAL_MS so a dead network can never stall the cycle.
// Publishing is skipped until NTP has synced: without it `updated` reads
// 1970 and every client would treat the heartbeat as decades stale.
static bool publishStatus() {
  if (WiFi.status() != WL_CONNECTED) return false;

  // Publish even before NTP syncs: the app tracks liveness by receive time,
  // not by the board's clock, so a 0 timestamp no longer makes the board look
  // offline. NTP (when it arrives) just makes `updated` human-readable.
  long long nowSec = (long long)time(nullptr);
  if (nowSec < NTP_VALID_EPOCH_SEC) nowSec = 0;

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
  body += "},\"priority\":\"";
  body += (ambActive || ambTransfer || ambQueued >= 0) ? "ambulance" : "";
  body += "\",\"updated\":";
  body += nowSec;
  body += ",\"seq\":";
  body += (uint32_t)++seq;
  body += '}';

  WiFiClientSecure client;
  configureTls(client);
  if (!client.connect(DB_HOST, 443)) return false;
  client.printf("PUT %s HTTP/1.1\r\nHost: %s\r\nContent-Type: application/json\r\n"
                "Content-Length: %d\r\nConnection: close\r\n\r\n%s",
                path, DB_HOST, body.length(), body.c_str());
  // Drain just the status line; the socket is discarded right after.
  String statusLine = client.readStringUntil('\n');
  client.stop();
  (void)statusLine;
  return true;
}

// ── SSE stream (one persistent connection to the command node) ──────────────
static bool streamStart() {
  streamClient.stop();
  lineLen = 0;
  sseHasData = false;

  configureTls(streamClient);
  if (!streamClient.connect(DB_HOST, 443)) {
    Serial.println("[traffic] stream: connect failed (no network?)");
    return false;
  }

  char path[160];
  makePath("command", path, sizeof(path));
  streamClient.printf("GET %s HTTP/1.1\r\nHost: %s\r\n"
                      "Accept: text/event-stream\r\nConnection: keep-alive\r\n\r\n",
                      path, DB_HOST);

  // Read response headers — bounded so a half-open socket cannot hang here.
  bool ok = false;
  const uint32_t headerDeadline = millis() + NET_IO_TIMEOUT_MS * 3UL;
  while (streamClient.connected() && (int32_t)(millis() - headerDeadline) < 0) {
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
  Serial.printf("[traffic] sse data: %s (id=%lld, lastCmdId=%lld)\\n", sseData, id, lastCmdId);
  if (id == 0) { Serial.println("[traffic] ignoring: id==0"); return; }
  static bool firstPutSeen = false;
  if (!firstPutSeen) {
    firstPutSeen = true;
    long long nowSec = (long long)time(nullptr);
    if (nowSec < 1700000000LL || id < nowSec * 1000 - 60000) {
      Serial.println("[traffic] ignoring pre-boot command; starting AUTO cycle");
      if (!ambActive && !ambTransfer && ambQueued < 0) startTransfer(0);
      return;
    }
  }
  if (id == lastCmdId) {
    Serial.printf("[traffic] ignoring: exact replay (id %lld == lastCmdId)\\n", id);
    return;
  }
  JsonObject data = doc["data"].as<JsonObject>();
  if (data.isNull()) return;
  executeAction(data);
}

static void streamLoop() {
  if (!streamUp) {
    // connect() can block for NET_CONNECT_TIMEOUT_MS, so it is rate-limited:
    // a failed attempt backs off STREAM_RETRY_MS, while a live stream that
    // dropped retries after STREAM_RECONNECT_MS so commands resume quickly.
    const uint32_t now = millis();
    if (now - lastStreamAttemptMs < streamRetryMs) return;
    lastStreamAttemptMs = now;
    if (!streamStart()) {
      streamRetryMs = STREAM_RETRY_MS;
      return;
    }
    streamRetryMs = STREAM_RECONNECT_MS;
  }

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

  // Lights first: the AUTO cycle starts BEFORE Wi-Fi is even attempted, so a
  // board with a missing or dead access point never waits — it just cycles.
  applyOutputs();    // boot: all red
  startTransfer(0);  // all-red clearance, then the N-E-S-W cycle

  // Wi-Fi gets a short, BOUNDED window. Never block forever: on timeout the
  // cycle keeps running and loop() retries the connection in the background.
  // An emergency escape can only arrive with a network up; without one the
  // board simply stays in AUTO.
  WiFi.mode(WIFI_STA);
  WiFi.setAutoReconnect(true);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  Serial.print("[traffic] connecting Wi-Fi");
  const uint32_t wifiDeadline = millis() + WIFI_BOOT_WAIT_MS;
  while (WiFi.status() != WL_CONNECTED && (int32_t)(millis() - wifiDeadline) < 0) {
    delay(250);
    Serial.print('.');
  }
  if (WiFi.status() == WL_CONNECTED) {
    Serial.printf(" ok, %s\n", WiFi.localIP().toString().c_str());
    // NTP for absolute timestamps in status — must come AFTER Wi-Fi is up,
    // otherwise the SNTP UDP socket races the lwIP stack and can assert-crash.
    configTime(6 * 3600, 0, "pool.ntp.org", "time.nist.gov");  // GMT+6 Dhaka
  } else {
    Serial.println(" no Wi-Fi yet: AUTO cycle already running, "
                   "retrying in the background");
  }

  // No command needed: the board ALWAYS starts in AUTO mode. A newer stored
  // command (e.g. custom durations) still applies once the stream connects.
  publishStatus();  // no-op until Wi-Fi AND NTP are both up
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

  // Emergency-escape bookkeeping — runs regardless of the network, so a
  // latch always times out even if Wi-Fi died while it was held.
  if (ambQueued >= 0 && !busy()) {
    int d = ambQueued;
    applyAmbulance(d);
  }
  if (ambTransfer && !busy()) {
    // The transfer finished: the ambulance's arm is green — freeze on it.
    ambTransfer = false;
    statusDirty = true;
  }
  if (ambActive && now - ambStart >= AMB_MAX_HOLD_MS) {
    Serial.println("[traffic] ambulance max-hold timeout: releasing");
    releaseAmbulance();
  }

  // Phase timing: green -> yellow -> all-red -> (next green in auto).
  // While the ambulance latch is held the cycle is FROZEN — except during a
  // transfer or a queued request, where the AUTO timers are exactly what
  // safely carries the change over to the ambulance's arm.
  const bool frozen = ambActive && !ambTransfer && ambQueued < 0;
  if (!frozen && phase == PH_GREEN && now - phaseStart >= greenMs) {
    phase = PH_YELLOW;
    phaseStart = now;
    applyOutputs();
    statusDirty = true;
  } else if (!frozen && phase == PH_YELLOW && now - phaseStart >= yellowMs) {
    phase = PH_ALL_RED;
    phaseStart = now;
    // Never let the normal cycle overwrite an ambulance target: if a transfer
    // to the ambulance's arm (or a queued request) is in flight, the all-red
    // phase must end on THAT arm, not on the next direction of the cycle.
    if (ambTransfer || ambQueued >= 0) {
      pending = (ambQueued >= 0) ? ambQueued : ambDir;
    } else if (active >= 0) {
      pending = (active + 1) % 4;  // N E S W cycle resumes
    }
    applyOutputs();
    statusDirty = true;
  } else if (!frozen && phase == PH_ALL_RED && pending >= 0 &&
             now - phaseStart >= allRedMs) {
    active = pending;
    pending = -1;
    phase = PH_GREEN;
    phaseStart = now;
    applyOutputs();
    statusDirty = true;
  }

  // Status upload: only when it changed or on the heartbeat, never while a
  // change is in flight (a slow connect must not stretch a yellow), and at
  // most once per interval so a dead network cannot stall the cycle. A failed
  // attempt leaves statusDirty set and simply retries on the next window.
  if (WiFi.status() == WL_CONNECTED &&
      !busy() &&
      (statusDirty || now - lastStatusMs >= STATUS_INTERVAL_MS) &&
      now - lastStatusAttemptMs >= STATUS_INTERVAL_MS) {
    lastStatusAttemptMs = now;
    if (publishStatus()) {
      statusDirty = false;
      lastStatusMs = now;
    }
  }
}