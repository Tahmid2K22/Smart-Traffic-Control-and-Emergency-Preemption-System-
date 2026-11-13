#define TRAFFIC_LIGHT_HOST_TEST
#include "../../traffic_light_firmware/traffic_light_firmware.ino"

#include <cstdlib>
#include <functional>
#include <iostream>
#include <limits>
#include <stdexcept>
#include <string>
#include <vector>

using namespace traffic;

static unsigned checks = 0;
#define CHECK(expr) do { ++checks; if (!(expr)) throw std::runtime_error( \
  std::string(__FILE__) + ":" + std::to_string(__LINE__) + ": " #expr); } while (false)

static Command command(const std::string& cmd = "STATUS") {
  Command c;
  c.version = 2;
  c.cmd = cmd;
  c.requestId = "request-1";
  c.intersection = "khulna_vgx3_g39";
  c.pass = "host-test-secret";
  c.role = "traffic_police";
  c.uid = "officer-uid";
  c.direction = "north";
  c.light = "green";
  c.greenSec = 5;
  c.yellowSec = 3;
  c.allRedSec = 2;
  return c;
}

static void invariant(const Controller& c) {
  unsigned nonRed = 0, green = 0, yellow = 0;
  for (int d = 0; d < 4; ++d) {
    const Light l = c.light(static_cast<Direction>(d));
    nonRed += l != Light::Red;
    green += l == Light::Green;
    yellow += l == Light::Yellow;
  }
  CHECK(nonRed <= 1);
  CHECK(green <= 1);
  CHECK((c.phase() == Phase::AllRed) == (nonRed == 0));
  CHECK((c.phase() == Phase::Green) == (green == 1));
  CHECK((c.phase() == Phase::Yellow) == (yellow == 1));
  CHECK(c.light(Direction::None) == Light::Red);
}

struct Rig {
  Controller c;
  uint32_t now;
  explicit Rig(uint32_t start = 0, const std::string& id = "khulna_vgx3_g39")
      : c(id, "host-test-secret", start), now(start) { invariant(c); }
  void advance(uint32_t ms) { now += ms; c.tick(now); invariant(c); }
  bool send(const Command& cmd) { bool ok = c.execute(cmd, now); invariant(c); return ok; }
  void green(const std::string& d = "north") {
    Command cmd = command("SET"); cmd.direction = d;
    CHECK(send(cmd));
    CHECK(c.phase() == Phase::AllRed);
    advance(1999); CHECK(c.phase() == Phase::AllRed);
    advance(1); CHECK(c.phase() == Phase::Green);
  }
};

static void boot_and_status() {
  Rig r;
  CHECK(r.c.mode() == Mode::Manual);
  CHECK(r.c.phase() == Phase::AllRed);
  CHECK(!r.c.busy()); CHECK(!r.c.auth()); CHECK(r.c.seq() == 0);
  r.advance(500000); CHECK(r.c.phase() == Phase::AllRed);
  Command c = command(); c.intersection = "not-the-controller";
  CHECK(r.send(c)); CHECK(r.c.auth()); CHECK(r.c.ack() == c.requestId);
  CHECK(r.c.error().empty()); CHECK(r.c.uptime() == 500);
  const uint32_t seq = r.c.seq();
  r.c.heartbeat(r.now); CHECK(r.c.seq() == seq + 1);
  CHECK(r.c.intersection() == "khulna_vgx3_g39");
  CHECK(std::string(name(Direction::West)) == "west");
  CHECK(std::string(name(Mode::Auto)) == "auto");
  CHECK(std::string(name(Phase::AllRed)) == "all_red");
  CHECK(std::string(name(Light::Red)) == "red");
}

static void fresh_clearance_and_transfer() {
  Rig r;
  r.advance(100000); // Long-idle all red does not count as fresh clearance.
  r.green();
  Command c = command("SET"); c.direction = "east";
  CHECK(r.send(c)); CHECK(r.c.phase() == Phase::Yellow);
  CHECK(r.c.light(Direction::North) == Light::Yellow);
  CHECK(r.c.target() == Direction::East);
  r.advance(2999); CHECK(r.c.light(Direction::North) == Light::Yellow);
  r.advance(1); CHECK(r.c.phase() == Phase::AllRed); CHECK(r.c.busy());
  r.advance(1999); CHECK(r.c.phase() == Phase::AllRed);
  r.advance(1); CHECK(r.c.light(Direction::East) == Light::Green);
  CHECK(!r.c.busy()); CHECK(r.c.target() == Direction::East);
  // Reasserting the active green never creates a second green/clearance.
  CHECK(r.send(c)); CHECK(r.c.light(Direction::East) == Light::Green);
}

static void red_and_yellow_semantics() {
  for (const std::string color : {"red", "yellow"}) {
    Rig r; r.green("south");
    Command c = command("SET"); c.direction = "south"; c.light = color;
    CHECK(r.send(c)); CHECK(r.c.light(Direction::South) == Light::Yellow);
    CHECK(r.c.target() == Direction::None);
    r.advance(3000); CHECK(r.c.phase() == Phase::AllRed); CHECK(r.c.busy());
    r.advance(2000); CHECK(!r.c.busy()); CHECK(r.c.phase() == Phase::AllRed);
    r.advance(10000); CHECK(r.c.phase() == Phase::AllRed);
  }
  Rig r;
  Command c = command("SET"); c.light = "yellow";
  CHECK(!r.send(c)); CHECK(r.c.error() == "inactive_yellow"); CHECK(!r.c.auth());
  r.green(); c.direction = "west";
  CHECK(!r.send(c)); CHECK(r.c.error() == "inactive_yellow");
  CHECK(r.c.light(Direction::North) == Light::Green);
  c.light = "red"; CHECK(r.send(c));
  CHECK(r.c.light(Direction::North) == Light::Green);
  CHECK(r.c.mode() == Mode::Manual);
}

static void busy_and_emergency_cancellation() {
  for (const std::string stop : {"ALL_RED", "MANUAL"}) {
    for (int stage = 0; stage < 3; ++stage) {
      Rig r;
      if (stage != 0) {
        r.green(); Command transfer = command("SET"); transfer.direction = "east";
        CHECK(r.send(transfer));
        if (stage == 2) r.advance(3000);
      } else CHECK(r.send(command("SET")));
      CHECK(r.c.busy());
      const auto phase = r.c.phase(); const auto target = r.c.target();
      for (const std::string cmd : {"SET", "AUTO"}) {
        Command c = command(cmd); c.direction = "west";
        CHECK(!r.send(c)); CHECK(r.c.error() == "busy");
        CHECK(r.c.phase() == phase); CHECK(r.c.target() == target);
      }
      CHECK(r.send(command("STATUS"))); CHECK(r.c.busy());
      CHECK(r.send(command(stop))); CHECK(r.c.phase() == Phase::AllRed);
      CHECK(r.c.mode() == Mode::Manual); CHECK(!r.c.busy());
      CHECK(r.c.target() == Direction::None);
      r.advance(10000); CHECK(r.c.phase() == Phase::AllRed);
      r.green("west");
    }
  }
}

static void validation_and_rejection_atomicity() {
  using Mutation = std::function<void(Command&)>;
  const std::vector<std::pair<Mutation, std::string>> bad = {
    {[](Command& c) { c.version = 1; }, "invalid_version"},
    {[](Command& c) { c.pass = "wrong"; }, "unauthorized"},
    {[](Command& c) { c.role = "admin"; }, "unauthorized"},
    {[](Command& c) { c.uid.clear(); }, "unauthorized"},
    {[](Command& c) { c.intersection.clear(); }, "intersection_mismatch"},
    {[](Command& c) { c.intersection = "other"; }, "intersection_mismatch"},
    {[](Command& c) { c.cmd = "GREEN"; }, "unknown_command"},
    {[](Command& c) { c.direction = "NORTH"; }, "invalid_direction"},
    {[](Command& c) { c.direction.clear(); }, "invalid_direction"},
    {[](Command& c) { c.light = "blue"; }, "invalid_light"},
    {[](Command& c) { c.requestId.clear(); }, "invalid_request_id"},
    {[](Command& c) { c.requestId = std::string(33, 'x'); }, "invalid_request_id"},
  };
  for (const auto& entry : bad) {
    Rig r; Command c = command("SET"); entry.first(c);
    CHECK(!r.send(c)); CHECK(r.c.error() == entry.second);
    CHECK(!r.c.auth()); CHECK(r.c.mode() == Mode::Manual);
    CHECK(r.c.phase() == Phase::AllRed); CHECK(!r.c.busy());
    CHECK(r.c.ack() == (c.requestId.size() <= 32 ? c.requestId : ""));
    r.advance(100000); CHECK(r.c.phase() == Phase::AllRed);
  }
  Rig r; r.green();
  r.advance(119999 - 2000);
  Command c = command("SET"); c.pass = "wrong";
  CHECK(!r.send(c)); CHECK(r.c.auth()); // Reject does not revoke a valid session.
  CHECK(r.c.light(Direction::North) == Light::Green);
  r.advance(1); CHECK(r.c.phase() == Phase::AllRed); // No timeout refresh.
  CHECK(r.send(command())); CHECK(r.c.error().empty());
  Command id32 = command(); id32.requestId = std::string(32, 'q');
  CHECK(r.send(id32)); CHECK(r.c.ack() == id32.requestId);
}

static void timing_validation_and_configuration() {
  for (int field = 0; field < 3; ++field) {
    const int low[] = {5, 3, 2}, high[] = {300, 60, 60};
    for (int value : {std::numeric_limits<int>::min(), -1, 0, low[field] - 1,
                      high[field] + 1, std::numeric_limits<int>::max()}) {
      Rig r;
      Command c = command("AUTO");
      int* fields[] = {&c.greenSec, &c.yellowSec, &c.allRedSec};
      *fields[field] = value;
      CHECK(!r.send(c)); CHECK(r.c.error() == "invalid_timing");
      CHECK(!r.c.auth()); CHECK(!r.c.busy());
      // Invalid timing never changes the original 3s yellow / 2s clearance.
      r.green(); c = command("SET"); c.direction = "east"; CHECK(r.send(c));
      r.advance(2999); CHECK(r.c.phase() == Phase::Yellow);
      r.advance(1); r.advance(1999); CHECK(r.c.phase() == Phase::AllRed);
      r.advance(1); CHECK(r.c.light(Direction::East) == Light::Green);
    }
  }
  Rig max;
  Command c = command("AUTO"); c.greenSec = 300; c.yellowSec = 60; c.allRedSec = 60;
  CHECK(max.send(c)); max.advance(59999); CHECK(max.c.phase() == Phase::AllRed);
  max.advance(1); CHECK(max.c.light(Direction::North) == Light::Green);
  max.advance(299999); CHECK(max.c.phase() == Phase::Green);
  max.advance(1); CHECK(max.c.phase() == Phase::Yellow);
  max.advance(59999); CHECK(max.c.phase() == Phase::Yellow);
  max.advance(1); CHECK(max.c.phase() == Phase::AllRed);
  max.advance(60000); CHECK(max.c.light(Direction::East) == Light::Green);
  CHECK(max.send(command("MANUAL"))); // Configured clearance persists in manual.
  CHECK(max.send(command("SET"))); max.advance(59999);
  CHECK(max.c.phase() == Phase::AllRed); max.advance(1);
  CHECK(max.c.phase() == Phase::Green);
}

static void discovery_and_unconfigured() {
  for (const std::string& id : std::vector<std::string>{
             "UNCONFIGURED", "", "bad/id", std::string(33, 'a')}) {
    Rig r(0, id); CHECK(!r.c.configured());
    Command c = command(); c.intersection.clear(); CHECK(r.send(c));
    CHECK(r.c.auth()); CHECK(r.c.intersection() == id);
    for (const std::string cmd : {"SET", "AUTO", "MANUAL", "ALL_RED"}) {
      c.cmd = cmd; c.intersection = id;
      CHECK(!r.send(c)); CHECK(r.c.error() == "unconfigured");
      CHECK(r.c.phase() == Phase::AllRed);
    }
    c = command(); c.role = "driver";
    CHECK(!r.send(c)); CHECK(r.c.error() == "unauthorized");
  }
  for (const std::string id : {"khulna_vgx3_g39", "khulna_moylapota_mor",
                               "khulna_royal_mor", "khulna_shibbari_mor"}) {
    Rig r(0, id); CHECK(r.c.configured());
    Command c = command("ALL_RED"); c.intersection = id; CHECK(r.send(c));
  }
}

static void disconnect_and_inactivity() {
  for (int stage = 0; stage < 4; ++stage) {
    Rig r; CHECK(r.send(command("AUTO")));
    if (stage >= 1) r.advance(2000);
    if (stage >= 2) r.advance(5000);
    if (stage >= 3) r.advance(3000);
    r.c.disconnect(r.now); invariant(r.c);
    CHECK(!r.c.auth()); CHECK(r.c.ack().empty()); CHECK(r.c.error().empty());
    CHECK(r.c.phase() == Phase::AllRed); CHECK(r.c.mode() == Mode::Manual);
    CHECK(r.c.target() == Direction::None); CHECK(!r.c.busy());
    r.advance(1000000); CHECK(r.c.phase() == Phase::AllRed);
    r.green("east");
  }
  Rig r; r.green();
  for (int i = 0; i < 5; ++i) {
    r.advance(20000); CHECK(r.send(command("STATUS")));
    CHECK(r.c.phase() == Phase::Green);
  }
  r.advance(17999); CHECK(r.c.phase() == Phase::Green);
  CHECK(r.send(command("STATUS")));
  r.advance(1); CHECK(r.c.phase() == Phase::AllRed);
  CHECK(r.c.mode() == Mode::Manual); CHECK(r.c.auth());
  r.advance(1000000); CHECK(r.c.phase() == Phase::AllRed);
  // An accepted control, unlike STATUS/rejection, refreshes manual inactivity.
  r.green(); r.advance(100000);
  Command red = command("SET"); red.direction = "west"; red.light = "red";
  CHECK(r.send(red)); r.advance(119999); CHECK(r.c.phase() == Phase::Green);
  r.advance(1); CHECK(r.c.phase() == Phase::AllRed);
}

static void auto_fairness_and_safe_start() {
  Rig r; r.green("west");
  CHECK(r.send(command("AUTO")));
  CHECK(r.c.light(Direction::West) == Light::Yellow);
  CHECK(r.c.target() == Direction::North);
  r.advance(3000); CHECK(r.c.phase() == Phase::AllRed);
  r.advance(2000);
  for (int cycle = 0; cycle < 100; ++cycle) {
    const auto d = static_cast<Direction>(cycle % 4);
    CHECK(r.c.light(d) == Light::Green); CHECK(r.c.mode() == Mode::Auto);
    r.advance(4999); CHECK(r.c.light(d) == Light::Green);
    r.advance(1); CHECK(r.c.light(d) == Light::Yellow);
    r.advance(2999); CHECK(r.c.light(d) == Light::Yellow);
    r.advance(1); CHECK(r.c.phase() == Phase::AllRed);
    r.advance(1999); CHECK(r.c.phase() == Phase::AllRed);
    r.advance(1);
  }
  Command red = command("SET"); red.direction = "west"; red.light = "red";
  CHECK(r.send(red)); CHECK(r.c.mode() == Mode::Manual);
  CHECK(r.c.light(Direction::North) == Light::Green);
  r.advance(5000); CHECK(r.c.light(Direction::North) == Light::Green);
}

static void late_ticks_and_rollover() {
  Rig r; r.green();
  Command c = command("SET"); c.direction = "south"; CHECK(r.send(c));
  r.advance(50000); CHECK(r.c.phase() == Phase::AllRed);
  // Never backdate all-red to the theoretical end of a delayed yellow phase.
  r.advance(1999); CHECK(r.c.phase() == Phase::AllRed);
  r.advance(1); CHECK(r.c.light(Direction::South) == Light::Green);

  Rig wrap(std::numeric_limits<uint32_t>::max() - 1000);
  wrap.green(); CHECK(wrap.now < 2000); CHECK(wrap.c.uptime() == 2);
  c.direction = "east"; CHECK(wrap.send(c));
  wrap.advance(2999); CHECK(wrap.c.phase() == Phase::Yellow);
  wrap.advance(1); wrap.advance(2000);
  CHECK(wrap.c.light(Direction::East) == Light::Green);
  CHECK(wrap.c.uptime() == 7);
  wrap.advance(114999); CHECK(wrap.c.phase() == Phase::Green);
  wrap.advance(1); CHECK(wrap.c.phase() == Phase::AllRed);

  Rig autoWrap(std::numeric_limits<uint32_t>::max() - 3000);
  CHECK(autoWrap.send(command("AUTO"))); autoWrap.advance(2000);
  autoWrap.advance(5000); CHECK(autoWrap.c.phase() == Phase::Yellow);
  autoWrap.advance(3000); autoWrap.advance(2000);
  CHECK(autoWrap.c.light(Direction::East) == Light::Green);
  autoWrap.advance(1000000); CHECK(autoWrap.c.phase() == Phase::Yellow);
  autoWrap.advance(3000); CHECK(autoWrap.c.phase() == Phase::AllRed);
  autoWrap.advance(2000); CHECK(autoWrap.c.light(Direction::South) == Light::Green);
}

static void transport_rejections_do_not_control() {
  Rig r; r.green(); r.advance(117999);
  for (const std::string error : {"malformed_json", "invalid_packet_size",
                                 "invalid_fields", "queue_full"}) {
    const uint32_t seq = r.c.seq();
    CHECK(!r.c.reject("recoverable-id", error)); invariant(r.c);
    CHECK(r.c.seq() == seq + 1); CHECK(r.c.ack() == "recoverable-id");
    CHECK(r.c.error() == error); CHECK(r.c.auth());
    CHECK(r.c.light(Direction::North) == Light::Green);
  }
  r.advance(1); CHECK(r.c.phase() == Phase::AllRed);
  CHECK(!r.c.reject(std::string(33, 'a'), "invalid_request_id"));
  CHECK(r.c.ack().empty());
}

static void status_envelope_budget() {
  // Conservative canonical JSON bound, including worst-case six-byte JSON
  // escaping per request-ID byte. ArduinoJson itself requires target tests.
  const std::string worst =
      "{\"v\":2,\"intersection\":\"" + std::string(32, 'i') +
      "\",\"lights\":{\"north\":\"yellow\",\"east\":\"red\",\"south\":\"red\","
      "\"west\":\"red\"},\"mode\":\"manual\",\"phase\":\"all_red\",\"target\":\"south\","
      "\"uptime\":18446744073709551,\"auth\":false,\"seq\":4294967295,\"ack\":\"" +
      std::string(32 * 6, 'x') + "\",\"error\":\"intersection_mismatch\"}";
  CHECK(worst.size() < 512);
}

static void strict_packet_framing() {
  for (const std::string raw : {"{}", " \r\n {\"a\":[{},[]]} \t",
                               "{\"text\":\"} [ {\"}",
                               "{\"text\":\"escaped \\\" quote\"}"})
    CHECK(singleObjectFrame(raw.data(), raw.size()));
  for (const std::string raw : {"", "  ", "[]", "null", "{}{}", "{} junk",
                               "{", "{\"a\":\"unterminated}", "{\"a\":\"raw\nline\"}"})
    CHECK(!singleObjectFrame(raw.data(), raw.size()));
  const std::string rawNul("{}\0junk", 7);
  CHECK(!singleObjectFrame(rawNul.data(), rawNul.size()));
  const std::string stringNul("{\"a\":\"\0\"}", 9);
  CHECK(!singleObjectFrame(stringNul.data(), stringNul.size()));
  // Framing deliberately delegates syntax/type checking to ArduinoJson.
  const std::string invalidSyntax = "{not-json}";
  CHECK(singleObjectFrame(invalidSyntax.data(), invalidSyntax.size()));
}

static void deterministic_adversarial_trace() {
  Rig r(std::numeric_limits<uint32_t>::max() - 100000);
  uint32_t rng = 0x12345678;
  for (int i = 0; i < 20000; ++i) {
    rng = rng * 1664525u + 1013904223u;
    r.advance(rng % 1001);
    Command c = command();
    switch ((rng >> 16) % 9) {
      case 0: c.cmd = "AUTO"; break;
      case 1: c.cmd = "ALL_RED"; break;
      case 2: c.cmd = "MANUAL"; break;
      case 3: c.pass = "wrong"; break;
      case 4: r.c.disconnect(r.now); invariant(r.c); continue;
      default:
        c.cmd = "SET";
        c.direction = name(static_cast<Direction>((rng >> 8) % 4));
        c.light = name(static_cast<Light>((rng >> 4) % 3));
    }
    const Phase phase = r.c.phase(); const Direction target = r.c.target();
    const Mode mode = r.c.mode(); const bool auth = r.c.auth();
    Light before[4];
    for (int d = 0; d < 4; ++d) before[d] = r.c.light(static_cast<Direction>(d));
    if (!r.send(c)) {
      CHECK(r.c.phase() == phase); CHECK(r.c.target() == target);
      CHECK(r.c.mode() == mode); CHECK(r.c.auth() == auth);
      for (int d = 0; d < 4; ++d)
        CHECK(r.c.light(static_cast<Direction>(d)) == before[d]);
    }
  }
}

int main() {
  const std::vector<std::pair<const char*, std::function<void()>>> tests = {
    {"boot and authenticated discovery", boot_and_status},
    {"fresh clearance and directional transfer", fresh_clearance_and_transfer},
    {"manual red and yellow semantics", red_and_yellow_semantics},
    {"busy rejection and emergency cancellation", busy_and_emergency_cancellation},
    {"validation and rejection atomicity", validation_and_rejection_atomicity},
    {"strict timing bounds and configured durations", timing_validation_and_configuration},
    {"unconfigured discovery and four deployment IDs", discovery_and_unconfigured},
    {"disconnect and manual inactivity", disconnect_and_inactivity},
    {"auto fairness and safe auto entry", auto_fairness_and_safe_start},
    {"late ticks and uint32 rollover", late_ticks_and_rollover},
    {"transport rejection does not renew control", transport_rejections_do_not_control},
    {"bounded status envelope", status_envelope_budget},
    {"strict packet framing", strict_packet_framing},
    {"20000-step adversarial trace", deterministic_adversarial_trace},
  };
  unsigned passed = 0;
  for (const auto& test : tests) {
    try { test.second(); ++passed; std::cout << "PASS " << test.first << '\n'; }
    catch (const std::exception& e) {
      std::cerr << "FAIL " << test.first << ": " << e.what() << '\n';
      return EXIT_FAILURE;
    }
  }
  std::cout << passed << " suites passed; " << checks << " checks\n";
  return EXIT_SUCCESS;
}
