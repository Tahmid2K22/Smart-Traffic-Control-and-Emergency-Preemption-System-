# Simple traffic-light control over Firebase Realtime Database

Prototype setup for `traffic_light_firmware/traffic_light_firmware.ino` and the
app's **Cloud signal control** page. Bench prototype only — the rules below are
open on purpose; tighten them before any real deployment.

## 1. Firebase console (one-time)

1. Realtime Database → **Create database** (any region; note the URL, e.g.
   `https://e-ambulance-system-001-default-rtdb.firebaseio.com`).
2. Rules → paste `docs/rtdb.traffic.rules.json` → publish.
3. *(Optional, only if you tighten the rules later)* Project settings →
   Service accounts → Database secrets → copy the legacy secret.

The open bench rules need no secret: verified working (read + write on
`/traffic` without auth).

## 2. ESP32 sketch

Fill in the four defines at the top of
`traffic_light_firmware/traffic_light_firmware.ino`:

```
WIFI_SSID, WIFI_PASSWORD, DB_URL
```

(`DB_SECRET` stays empty with the open bench rules.)

Flash (Arduino IDE or `arduino-cli compile/upload`, FQBN `esp32:esp32:esp32`).
The board prints its IP on the serial monitor (115200).

## 3. App

Police dashboard → **Cloud signal control**. The page shows live status
(listening, no polling) and sends a command only when a button is pressed:
green per direction, ALL RED, AUTO cycle.

## Firebase traffic budget

| Source | Calls |
| --- | --- |
| App → status | 0 reads (persistent listener) |
| App → command | 1 write per button press |
| ESP32 → command | 1 persistent stream (no polling) |
| ESP32 → status | 1 write on change + 1 heartbeat write / 5 s |

## Safety notes

- Boot and Wi-Fi loss: all red, manual.
- Only one non-red direction at a time; changes run yellow → all-red → green.
- Stale commands (id ≤ last processed id) are ignored, so reconnect replays
  cannot re-trigger an old command.
- Manual mode returns to all-red after 120 s of inactivity.
- The legacy database secret is embedded in the device firmware; rotate it if
  a device is lost and move to token auth before real deployment.
