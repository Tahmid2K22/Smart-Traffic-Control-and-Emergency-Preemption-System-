# Four-way ESP32 traffic-light prototype

**Bench prototype only. Not public-road certified. Do not connect to real traffic signals or mains. No hardware was flashed as part of this implementation.**

## Scope and configuration

- `traffic_light_firmware/traffic_light_firmware.ino`: self-contained sketch with the portable, single-owner nonblocking controller, packet-framing guard, classic ESP32 Arduino BLE, ArduinoJson 6/7, bounded FreeRTOS queue, GPIO and status adapter. No separate project header is required.
- `test/firmware/four_way_controller_test.cpp`: standalone host tests that include the same sketch with `TRAFFIC_LIGHT_HOST_TEST` defined to exclude ESP32-specific code.

The existing BLE device name, passcode value and service/characteristic UUIDs are preserved. This firmware replaces the old single-lamp protocol; legacy `RED`, `YELLOW`, `GREEN`, and `red_sec` commands are **not** supported. The Dart BLE service, protocol model and police control screen now use this same v2 contract. Legacy firmware is rejected rather than receiving ambiguous single-lamp commands.

Set `INTERSECTION_ID` in the sketch to the **Firestore document ID**, not the name, Plus Code or direction-specific light ID. Its default is `UNCONFIGURED`: boot remains all red, authenticated `STATUS` discovery works, and every control is rejected with `unconfigured`.

Choose the actual deployed intersection, using the existing directory IDs:

| Intersection | Firestore document ID |
| --- | --- |
| VGX3+G39, Khulna | `khulna_vgx3_g39` |
| Moylapota Mor | `khulna_moylapota_mor` |
| Royal Mor | `khulna_royal_mor` |
| Shibbari Mor | `khulna_shibbari_mor` |

**Deployment constraint:** IDs must be 1–32 ASCII letters, digits, `_` or `-`. All four seed IDs qualify. This additional configuration bound keeps every status below 512 bytes even with an escaped 32-byte request ID. Overlong IDs fail the compile-time check; other invalid IDs leave all red with BLE disabled. Renaming a Firestore ID requires updating firmware configuration; firmware never writes Firestore.

## Wiring and electrical safety

The active-high pin map is for **classic ESP32 only**, not ESP32-C3/S2/S3 or arbitrary module variants. Other chip targets are explicitly rejected. Confirm these pins are exposed and unused on the specific board.

| Direction | Red | Yellow | Green |
| --- | --- | --- | --- |
| North | GPIO 25 | GPIO 26 | GPIO 27 |
| East | GPIO 14 | GPIO 32 | GPIO 33 |
| South | GPIO 18 | GPIO 19 | GPIO 21 |
| West | GPIO 22 | GPIO 23 | GPIO 13 |

These avoid classic ESP32 strapping pins, GPIO 6–11 flash pins, input-only GPIO 34–39, and UART0 GPIO 1/3. GPIO 13/14 overlap JTAG: do not use JTAG simultaneously. Check conflicts with SPI, I2C and other attached hardware. North retains the original 25/26/27 wiring.

- GPIO is **3.3 V logic**, not a lamp power source, and is not 5 V tolerant. Never exceed the board/module datasheet's per-pin or total current limits.
- For a small indicator LED, use one current-limiting resistor per LED; calculate `(3.3 V - LED forward voltage) / desired current`. Use only a few mA (for example 2–4 mA) rather than treating a GPIO maximum rating as an operating target.
- Use appropriately rated transistor/MOSFET drivers for low-voltage loads, separate load power, and flyback protection for coils. Relay modules must have verified 3.3 V-compatible inputs and proper electrical isolation. Active-low relay boards are **not** directly compatible with this active-high adapter.
- **Never directly wire GPIO, breadboards, or this prototype to mains or real signal equipment.** Isolation, enclosure, fusing, certified load switching and qualified electrical design are separate requirements.
- Software all-red is not a hardware fail-safe. Power loss, reset, pin initialization, driver failure, welded relays and a hung CPU require independent hardware interlocks/watchdogs and a validated failure design. Pin startup levels and switching skew must be measured, not assumed safe.

The writer disables all yellow/green outputs before changing reds and enabling a new non-red output. Unchanged snapshots do not rewrite GPIO, so heartbeat/rejection events do not pulse an active lamp. This does not provide atomic electrical switching or prove actual lamp state: there is no output feedback.

## BLE transport

| Item | Value |
| --- | --- |
| Device name | `ESP32-TrafficLight` |
| Service | `12345678-1234-1234-1234-123456789abc` |
| Command, WRITE with response | `12345678-1234-1234-1234-123456789001` |
| Status, READ + NOTIFY | `12345678-1234-1234-1234-123456789002` |

The server requests MTU **517**. The central must also negotiate it before exchanging full JSON packets; setting the server MTU alone does not force the client's MTU. Notifications have at most `MTU - 3` bytes. Do not assume the default MTU 23 can carry this protocol. No application-level fragmentation/reassembly is provided.

Each command is one complete UTF-8 JSON object, **1–511 bytes**. Empty/oversized packets, arrays, concatenated documents, trailing non-whitespace, raw NUL bytes, invalid JSON, excessive nesting and wrongly typed fields are rejected. String fields cannot contain decoded NULs. Unknown extra fields are ignored. Integers must be JSON integers, not strings, booleans or fractional numbers; timing values are validated, never clamped.

Subscribe before writing, use writes with response, and send **one outstanding request at a time**. A GATT write response confirms transport receipt, not command acceptance. Match the status `ack` and inspect `error`. Successful acknowledgements mean the transition was accepted, not that the target has already become green. Follow `lights`, `phase` and `target` for progress. Request IDs are correlation IDs, not replay protection or a deduplication cache.

### Queue and connection ownership

BLE callbacks only copy packets into an eight-entry `xQueue` or update critical-section-protected connection/epoch metadata. JSON parsing, authorization, state transitions, characteristic writes and GPIO belong exclusively to `loop()`. No callback directly changes controller state or outputs.

Disconnect/reconnect increments a session epoch. At the next loop service, all directions become red, mode becomes manual, auto and pending transfers stop, authorization clears, and previous-session packets are discarded. Even a disconnect followed by reconnect between two loop iterations invalidates old queued controls. Advertising resumes from the loop after disconnect.

Queue overflow also fails closed: invalidate queued controls, go all-red manual, clear authorization, and publish `queue_full` with the first overflowing packet's ID if recoverable. Additional writes arriving while the overflow latch is set are dropped. Discarded/connection-lost packets cannot each receive a guaranteed acknowledgement in a bounded transport. On missing acknowledgements, read status, reconnect if necessary, reauthorize, and only then issue a new explicit control; never blindly assume success or replay queued commands. Overflow handling is deliberately stronger than an ordinary validation rejection.

The loop services bounded batches and yields one FreeRTOS tick, not a signal-phase delay. Disconnect handling has scheduler/loop latency; this is not an independent instantaneous hardware interlock.

## Protocol version 2

Every command requires these exact field types:

| Field | Requirement |
| --- | --- |
| `v` | Integer `2` |
| `cmd` | Case-sensitive supported command string |
| `request_id` | Nonempty string, at most 32 UTF-8 bytes |
| `intersection` | String matching configured ID for controls; may be empty/mismatched for discovery `STATUS` |
| `pass` | Existing configured shared passcode |
| `role` | Exactly `traffic_police` |
| `uid` | Nonempty string |

`STATUS` may query before the intersection is configured or matched, but **still requires passcode, role and UID**, as well as a valid version/request ID and an `intersection` string. It reports the firmware's own intersection ID. Only a fully validated, accepted command sets session `auth` true. Rejection does not turn an unauthorized session into an authorized one, nor revoke a previously authorized session. Every command is checked again even if session `auth` is already true.

Example envelope (substitute the existing configured passcode; do not introduce a new value):

```json
{"v":2,"cmd":"SET","request_id":"officer-42-1","intersection":"khulna_vgx3_g39","pass":"<existing-passcode>","role":"traffic_police","uid":"officer-42","direction":"east","light":"green"}
```

### Commands

| `cmd` | Additional fields | Behavior |
| --- | --- | --- |
| `SET` | `direction`: `north/east/south/west`; `light`: `red/yellow/green` | Valid accepted controls select manual mode; see transition rules below |
| `ALL_RED` | None | Immediate all-red manual, cancels auto and pending transfer, even while busy |
| `MANUAL` | None | Stops auto, immediate all-red manual, cancels pending transfer, even while busy |
| `AUTO` | Integer `green_sec` 5–300, `yellow_sec` 3–60, `all_red_sec` 2–60 | Safe entry, then sequential north/east/south/west cycling |
| `STATUS` | None | Authenticated query; no output/mode/timing change and **does not renew manual inactivity** |

All required AUTO timing fields must be present and in range. Defaults at boot are green 30 s, yellow 3 s, all-red 2 s. A successful AUTO command installs its timing configuration; yellow and all-red durations also apply to subsequent manual transfers until reboot or another accepted AUTO configuration. Rejected configuration never changes timings.

### Transition and timeout rules

- Boot: all red, manual, `auth: false`, no pending direction.
- At most **one non-red direction** exists: green or yellow, never both across directions. All other directions remain red.
- Idle all-red → requested green: start a **fresh** configured all-red interval (at least 2 s), regardless of how long the controller was previously idle.
- Active green → different green: old direction yellow for configured time (at least 3 s), all four red for configured time (at least 2 s), then requested direction green.
- `SET` the already-active green: output no-op, selects manual and renews manual timeout.
- `SET yellow`: accepted only for the active green direction; it goes yellow, then completes all-red clearance, then remains all-red idle. Inactive yellow is rejected.
- `SET red` on active green: the same yellow → all-red clearance → safe-idle path, **not** an immediate green-to-red shortcut.
- `SET red` on an inactive direction: output no-op, but selects manual and renews its timeout; if auto had an active green, that green remains under manual timeout. Use `MANUAL`/`ALL_RED` when immediate all-red is intended.
- Yellow and pending/timed all-red clearance are **busy**. Reject all `SET` and `AUTO` requests during them, including requests that might otherwise look like no-ops. Only authorized `STATUS`, `ALL_RED` and `MANUAL` are allowed while busy.
- AUTO from an active green first gives that direction yellow and all-red, then starts **north**. AUTO from idle starts a fresh all-red interval before north. AUTO continues N → E → S → W → N, with green/yellow/all-red each time; it does not start a green immediately or skip a direction.
- In manual mode, **120 seconds since the last accepted control** forces immediate all-red manual, cancels pending work, and never unexpectedly starts auto. STATUS, malformed packets and rejected controls do not refresh this timer. Session authorization remains until disconnect/overflow; it is not permission to bypass command checks.
- AUTO does not use the manual inactivity timer; it runs only while the BLE session remains connected. Disconnect stops it. There is no separate connected-client heartbeat timeout in this version.
- Emergency all-red, manual stop, disconnect and manual inactivity intentionally bypass yellow and stop immediately. They never lead to an automatic green.

The portable controller uses unsigned 32-bit elapsed arithmetic through `millis()` rollover and an accumulated 64-bit uptime. It must be serviced at least once per 2^32 milliseconds. A delayed loop advances **at most one phase** per tick and starts the next interval at the actual tick time; it does not catch up by skipping physical clearance. A suspended CPU cannot provide real-time safety and needs an independent watchdog/interlock.

### Status

Example snapshot:

```json
{"v":2,"intersection":"khulna_vgx3_g39","lights":{"north":"red","east":"green","south":"red","west":"red"},"mode":"manual","phase":"green","target":"east","uptime":42,"auth":true,"seq":17,"ack":"officer-42-1","error":""}
```

- `lights` always contains all four lowercase directions and `red/yellow/green` strings.
- `mode` is `manual` or `auto`; `phase` is `green`, `yellow` or `all_red`.
- `target` is the current green direction, the pending future-green direction during yellow/clearance, or `""` when no future green is scheduled (including yellow-to-idle).
- `uptime` is seconds since controller startup and continues across 32-bit millisecond rollover.
- `auth` is the local session authorization latch, **not** verified Firebase identity.
- `seq` is an unsigned 32-bit event counter; it wraps modulo 2^32 and resets on reboot. It increments for responses, transitions, session resets and heartbeats. Compare with wrap-aware logic, not an eternal increasing integer assumption.
- `ack` echoes the most recently processed valid request ID and persists through transitions/heartbeats. Successful acceptance has `error: ""`; rejection has a machine-readable error. Disconnect clears both. A bad/missing/overlong/unrecoverable request ID is reported as `ack: ""` rather than echoed outside the protocol bound.
- READ is updated on every processed command/rejection, transition, connection event and two-second heartbeat, **even while disconnected**. Notifications are attempted for connected subscribers. READ is public in this prototype, so discovery telemetry is not confidential.
- JSON is always below 512 bytes for valid deployment configuration; the requested MTU 517 can carry it in one notification. Internal serialization failure forces all-red manual, clears authorization and replaces READ with a bounded `status_failure` snapshot rather than a stale state.

Errors include `invalid_packet_size`, `malformed_json`, `invalid_fields`, `invalid_request_id`, `invalid_version`, `unauthorized`, `unconfigured`, `intersection_mismatch`, `unknown_command`, `invalid_direction`, `invalid_light`, `invalid_timing`, `busy`, `inactive_yellow`, `queue_full`, and `status_failure`. Error precedence is validation order, not a promise to expose every fault in one packet. Malformed JSON cannot reliably recover an ID. Ordinary rejection changes response metadata only, not outputs, mode, configured durations, pending transfers or the last-control deadline; independently due safety timers still run.

## Host validation

From the repository root in the MSYS2-compatible shell on this Windows machine (the ignored `build/` directory already exists):

```sh
env PATH=/c/msys64/ucrt64/bin:/usr/bin:/bin C:/msys64/ucrt64/bin/g++.exe -std=c++11 -Wall -Wextra -Wpedantic -Werror -O2 test/firmware/four_way_controller_test.cpp -o build/four_way_controller_test.exe
env PATH=/c/msys64/ucrt64/bin:/usr/bin:/bin ./build/four_way_controller_test.exe
```

The explicit runtime PATH is needed by this compiler/linker and generated executable. It is scoped to these commands. On other hosts with GCC, use `g++` with the same source/flags and a suitable ignored output directory.

The tests exercise boot, authenticated discovery before configuration/matching, all four IDs, strict validation/acknowledgements, fresh clearance, transfers, active/inactive red/yellow semantics, busy rejection, emergency cancellation at every transitional stage, timing boundaries without clamping, disconnect at every auto phase, manual inactivity without STATUS/rejection renewal, safe auto entry and 100-direction fairness, late ticks, uint32 rollover, packet framing, and a deterministic 20,000-step adversarial trace with invariant checks after every operation.

The optimized build and a separate `-O0 -g -D_GLIBCXX_ASSERTIONS` debug build each passed **14 suites / 313,846 checks**. The status-envelope test conservatively bounds canonical JSON size, including worst-case request-ID escaping.

These tests execute the **portable controller/framing guard**, not ArduinoJson, ESP32 BLE/FreeRTOS, electrical outputs, MTU negotiation or physical timing. The Arduino adapter contains conditional support for ArduinoJson 6/7 and ESP32 core BLE `getValue()` return types (`std::string` in 2.x, `String` in 3.x), but **an ESP32 build has not been run: Arduino CLI is unavailable**. No ESP32 compile success, bench behavior, or hardware safety certification is implied by passing host tests.

For a later Arduino build, open `traffic_light_firmware/traffic_light_firmware.ino` directly in Arduino IDE, select a classic ESP32 board and install ArduinoJson 6 or 7. The sketch already resides in its matching folder and needs no separate controller header. Keep generated sketch/build artifacts outside source or under ignored `build/`. Compile both intended dependency combinations before any hardware work. Do not upload/flash as part of host testing.

## Flutter police control

`lib/services/ble_traffic_service.dart` checks the officer's verified/approved role and active intersection using a fresh server read before connecting or sending a command. An explicit `assignedIntersectionId` is preferred; legacy name/code/location assignments must resolve to exactly one active directory record. The firmware's configured intersection must match it.

On Android the app requests MTU 517 and refuses a connection below 515; other platforms must already negotiate at least 515. It subscribes and reads telemetry, rejects legacy/incompatible devices, then sends an authenticated `STATUS` handshake. Only matching, valid v2 snapshots can acknowledge commands. Notifications older than six seconds disable controls. A write response alone never produces success; the app waits up to ten seconds for the exact request ID, checks the controller error, and never automatically replays a timed-out command. A timeout means the outcome is unknown: refresh status before issuing another control.

Use **Four-way control** from the police dashboard, then scan and explicitly select the correct controller once per app session. Auto-reconnect only targets the previously verified BLE device for that assigned intersection, never simply the strongest nearby traffic controller. North/East/South/West heads show reported controller outputs (not sensor-verified lamp feedback). Directional controls wait for firmware clearance; **All Red** can cancel a transfer. Auto mode uses separate green, yellow and all-red durations, cycling one direction at a time. The old Firestore-only override icon was removed; an emergency alert does not silently operate physical lights.

The application does not update Firestore's directory light states from these BLE snapshots; the admin directory remains configuration, not a live signal monitor. No firmware upload or physical controller mapping was performed automatically.

## Security and release blockers

The shared passcode is carried in the command payload, and role/UID are caller-supplied strings. **Shared passcode plus caller role is not cryptographic Firebase authorization.** A modified client can spoof a role/UID, replay IDs, read public status, or cause denial of service. This sketch does not validate Firebase tokens or officer assignments, fetch Firestore policy, pair securely, enforce approval, or establish physical lamp feedback.

Before any controlled bench deployment, review secure BLE pairing/bonding and encrypted characteristics, device-specific rotated secrets, trusted short-lived **signed tokens** bound to device/intersection/role/UID/expiry/nonce with verified signatures and replay protection, assignment policy and access controls. Signed-token validation and key provisioning are separate security work, not provided here. Do not log command payloads or passcodes.

Hardware release additionally requires an independent conflict monitor/interlock, watchdog and power-loss strategy, measured electrical behavior, tests of disconnect/reconnect/queue floods/low MTU/malformed traffic on each dependency combination, feedback from actual outputs, and applicable professional safety certification. This firmware is not suitable for operating public-road signals.
