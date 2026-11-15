// Host test for the portable core inside traffic_light_firmware.ino.
#define TRAFFIC_HOST_TEST
#include "../../traffic_light_firmware/traffic_light_firmware.ino"

#include <iostream>
#include <stdexcept>
#include <string>

static unsigned checks = 0;
#define CHECK(expr) do { ++checks; if (!(expr)) throw std::runtime_error( \
  std::string(__LINE__ + 0 ? "line " : "") + std::to_string(__LINE__) + ": " #expr); } while (false)

static Cmd make(const char* cmd, const char* req = "r1") {
  Cmd c; memset(&c, 0, sizeof(c));
  c.version = 2;
  snprintf(c.cmd, sizeof(c.cmd), "%s", cmd);
  snprintf(c.req, sizeof(c.req), "%s", req);
  snprintf(c.inter, sizeof(c.inter), "%s", INTERSECTION_ID);
  snprintf(c.uid, sizeof(c.uid), "officer");
  c.green = 5; c.yellow = 3; c.allRed = 2;
  return c;
}
static Cmd setCmd(const char* dir, const char* light) {
  Cmd c = make("SET");
  snprintf(c.dir, sizeof(c.dir), "%s", dir);
  snprintf(c.light, sizeof(c.light), "%s", light);
  return c;
}
static bool run(const Cmd& c, uint32_t now, const char** err = nullptr) {
  const char* e = "";
  const bool ok = coreExecute(c, now, &e);
  if (err) *err = e;
  return ok;
}
static void invariant() {
  int nonRed = 0;
  for (int d = 0; d < 4; ++d) if (lightFor(d) != 0) ++nonRed;
  CHECK(nonRed <= 1);
}
static void advance(uint32_t& now, uint32_t ms) {
  for (uint32_t t = 0; t < ms; t += 10) { now += 10; coreTick(now); invariant(); }
}

static void bootAndAuto() {
  uint32_t now = 1000;
  coreReset(now);
  CHECK(mode == MODE_AUTO);
  for (int d = 0; d < 4; ++d) CHECK(lightFor(d) == 0);
  advance(now, 3100);                       // fresh all-red, then North green
  CHECK(lightFor(0) == 2);
  advance(now, 30000 + 5000 + 3000 + 100);  // North green+yellow+all-red -> East
  CHECK(lightFor(1) == 2);
  for (int i = 0; i < 2; ++i) advance(now, 38000);  // South, West
  CHECK(lightFor(3) == 2 || lightFor(3) == 1 || lightFor(0) == 2);
}

static void manualTransfer() {
  uint32_t now = 5000;
  coreReset(now);
  CHECK(run(make("MANUAL"), now));
  for (int d = 0; d < 4; ++d) CHECK(lightFor(d) == 0);
  CHECK(run(setCmd("east", "green"), now));
  const char* err = "";
  CHECK(!run(setCmd("west", "green"), now, &err) && !strcmp(err, "busy"));
  advance(now, 3100);
  CHECK(lightFor(1) == 2);
  CHECK(run(setCmd("south", "green"), now));
  CHECK(lightFor(1) == 1);                  // old direction yellow first
  advance(now, 5100);
  for (int d = 0; d < 4; ++d) CHECK(lightFor(d) == 0);   // then all red
  advance(now, 3100);
  CHECK(lightFor(2) == 2);
}

static void emergencyStop() {
  uint32_t now = 9000;
  coreReset(now);
  CHECK(run(make("MANUAL"), now));
  CHECK(run(setCmd("north", "green"), now));
  advance(now, 3100);
  CHECK(run(setCmd("east", "green"), now));
  CHECK(busy());
  CHECK(run(make("ALL_RED"), now));         // allowed while busy
  for (int d = 0; d < 4; ++d) CHECK(lightFor(d) == 0);
  CHECK(!busy());
  advance(now, 10000);
  for (int d = 0; d < 4; ++d) CHECK(lightFor(d) == 0);   // manual never goes green by itself
}

static void validation() {
  uint32_t now = 20000;
  coreReset(now);
  const char* err = "";
  Cmd bad = setCmd("up", "green");
  CHECK(!run(bad, now, &err) && !strcmp(err, "invalid_direction"));
  bad = setCmd("north", "blue");
  CHECK(!run(bad, now, &err) && !strcmp(err, "invalid_light"));
  bad = make("AUTO"); bad.green = 4;
  CHECK(!run(bad, now, &err) && !strcmp(err, "invalid_timing"));
  bad = make("AUTO"); bad.allRed = 61;
  CHECK(!run(bad, now, &err) && !strcmp(err, "invalid_timing"));
  bad = make("NOPE");
  CHECK(!run(bad, now, &err) && !strcmp(err, "unknown_command"));
  bad = make("STATUS"); bad.version = 1;
  CHECK(!run(bad, now, &err) && !strcmp(err, "invalid_version"));
  CHECK(run(make("MANUAL"), now));
  bad = setCmd("north", "yellow");
  CHECK(!run(bad, now, &err) && !strcmp(err, "inactive_yellow"));
  CHECK(run(make("STATUS"), now));
  invariant();
}

static void manualTimeoutReturnsToAuto() {
  uint32_t now = 40000;
  coreReset(now);
  CHECK(run(make("MANUAL"), now));
  advance(now, MANUAL_TIMEOUT_MS + 200);
  CHECK(mode == MODE_AUTO);
  advance(now, 3500);
  CHECK(lightFor(0) == 2);
}

static void millisRollover() {
  uint32_t now = 0xFFFFFF00u;
  coreReset(now);
  advance(now, 3300);                       // crosses 2^32
  CHECK(lightFor(0) == 2);
}

static void statusJson() {
  uint32_t now = 100;
  coreReset(now);
  char out[512];
  const size_t n = buildStatus(out, sizeof(out), "request-1", "", true);
  CHECK(n > 0 && n < 512);
  CHECK(std::string(out).find("\"v\":2") == 1);
  CHECK(std::string(out).find("\"phase\":\"all_red\"") != std::string::npos);
  char tiny[16];
  CHECK(buildStatus(tiny, sizeof(tiny), "x", "", true) == 0);
}

static void timestamps() {
  CHECK(parseRfc3339Ms("1970-01-01T00:00:00Z") == 0);
  CHECK(parseRfc3339Ms("2023-11-14T22:13:20Z") == 1700000000000LL);
  CHECK(parseRfc3339Ms("2023-11-14T22:13:20.123456Z") == 1700000000123LL);
  CHECK(parseRfc3339Ms("2023-11-14T22:13:20.5Z") == 1700000000500LL);
  CHECK(parseRfc3339Ms("2023-11-14 22:13:20Z") == -1);
  CHECK(parseRfc3339Ms("2023-11-14T22:13:20+06:00") == -1);
  CHECK(parseRfc3339Ms("") == -1);
}

static void packetFraming() {
  // No NUL terminator: only the declared packet bytes may be inspected.
  const char packet[] = {'{', '}', 'x'};
  CHECK(singleObjectFrame(packet, 2));
  CHECK(!singleObjectFrame(packet, sizeof(packet)));
  CHECK(!singleObjectFrame(packet, 0));
  const char embeddedNul[] = {'{', '}', '\0'};
  CHECK(!singleObjectFrame(embeddedNul, sizeof(embeddedNul)));
  const char* valid[] = {"{}", " \n{}\t", "{\"cmd\":\"STATUS\"}",
                         "{\"nested\":[{\"x\":\"}\\\"{\"}]}"};
  for (const char* frame : valid) CHECK(singleObjectFrame(frame, strlen(frame)));
  const char* invalid[] = {"", "[]", "{}{}", "{} trailing", "{", "{\"x\":\"bad\nvalue\"}"};
  for (const char* frame : invalid) CHECK(!singleObjectFrame(frame, strlen(frame)));
  char maximum[511];
  memset(maximum, ' ', sizeof(maximum));
  maximum[0] = '{'; maximum[1] = '}';
  CHECK(singleObjectFrame(maximum, sizeof(maximum)));
}

static void ids() {
  CHECK(validId("khulna_royal_mor", 32));
  CHECK(!validId("", 32));
  CHECK(!validId("bad id", 32));
  CHECK(!validId("123456789012345678901234567890123", 32));
}

int main() {
  struct { const char* name; void (*fn)(); } tests[] = {
    {"boot and AUTO cycle", bootAndAuto},
    {"manual transfer through yellow and all-red", manualTransfer},
    {"emergency stop while busy", emergencyStop},
    {"command validation", validation},
    {"manual timeout returns to AUTO", manualTimeoutReturnsToAuto},
    {"millis rollover", millisRollover},
    {"status JSON bounds", statusJson},
    {"RFC3339 parsing", timestamps},
    {"ID validation", ids},
    {"length-delimited BLE packet framing", packetFraming},
  };
  try {
    for (auto& t : tests) { t.fn(); std::cout << "PASS " << t.name << "\n"; }
  } catch (const std::exception& e) {
    std::cerr << "FAIL: " << e.what() << "\n";
    return 1;
  }
  std::cout << sizeof(tests) / sizeof(tests[0]) << " suites passed; " << checks << " checks\n";
  return 0;
}
