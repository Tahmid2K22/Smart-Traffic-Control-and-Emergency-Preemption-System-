#ifndef TRAFFIC_LIGHT_CONTROLLER_H
#define TRAFFIC_LIGHT_CONTROLLER_H

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
#endif
