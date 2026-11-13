# Intersections directory

## Verified Khulna Plus Code

Using Google's [Open Location Code Python implementation](https://github.com/google/open-location-code/blob/main/python/openlocationcode/openlocationcode.py):

- `recoverNearest('VGX3+G39', 22.8456, 89.5403)` (Khulna vicinity reference) returns **`7MJFVGX3+G39`**.
- Decoded bounds: latitude `[22.898775, 22.8988)`, longitude `[89.50271875, 89.50275)`.
- Exact center: **`22.8987875, 89.502734375`**.
- `encode(22.8987875, 89.502734375, 11)` returns `7MJFVGX3+G39`.

The supplied recovery and center are correct. Short codes require a nearby reference; this verifies the geographic code, not the existence or official name of a road intersection.

## Default Khulna directory

Opening the admin intersections page calls `IntersectionService.seedKhulnaIntersections()` to idempotently seed these four records:

| Intersection | Short Plus Code | Full Plus Code | Latitude | Longitude |
| --- | --- | --- | --- | --- |
| VGX3+G39, Khulna | `VGX3+G39` | `7MJFVGX3+G39` | 22.8987875 | 89.502734375 |
| Moylapota Mor | `RGPQ+37` | `7MJFRGPQ+37` | 22.8351875 | 89.5381875 |
| Royal Mor | `RH66+4W2` | `7MJFRH66+4W2` | 22.8102625 | 89.562265625 |
| Shibbari Mor | `RHC3+V3` | `7MJFRHC3+V3` | 22.8221875 | 89.5526875 |

The seed creates missing records without duplicating them or overwriting existing directory edits, controller mappings, or traffic-light states. The original record retains ID `khulna_vgx3_g39`. Reopening or retrying initialization is safe; seeding is not a signal reset or hardware command.

## Directory schema and app flow

Firestore `intersections/{id}` stores `name`, `city`, numeric `latitude`/`longitude`, `plusCode`, and boolean `isActive`, with creation/update metadata. Admin saves also write a `location` GeoPoint; seeds include `fullPlusCode` but do not require `location`.

New intersections default to **4 ways and 4 traffic lights**. `IntersectionPoint.directions` is `['north', 'east', 'south', 'west']`; `wayCount` and `trafficLightCount` both return `4`. The `lights` getter returns all four directions, including unconfigured lights for missing configuration. Each direction has its own separate light ID. `toMap()` stores:

```text
wayCount: 4
trafficLightCount: 4
trafficLights:
  north: {id: <distinct north light ID>, direction: north, controllerId: null, state: UNKNOWN}
  east:  {id: <distinct east light ID>, direction: east, controllerId: null, state: UNKNOWN}
  south: {id: <distinct south light ID>, direction: south, controllerId: null, state: UNKNOWN}
  west:  {id: <distinct west light ID>, direction: west, controllerId: null, state: UNKNOWN}
```

`IntersectionTrafficLight` contains string `id`, string `direction`, nullable string `controllerId`, and string `state` (default `UNKNOWN`). These are directory configuration fields, not verified live telemetry. There is currently no live hardware controller mapping. The admin page shows a read-only four-way diagram with North at the top, East at the right, South at the bottom, West at the left, and the intersection in the center. Light indicators are neutral gray and labeled `UNKNOWN`, with `Unconfigured` for missing controller mappings; they never infer live red/green states from stored data. Driver cards show only the concise four-way/four-light summary. Neither page adds signal-state controls.

Admins can add/edit entries and enable/disable directory availability; this does not change physical signals. `IntersectionService` checks the signed-in user's `users/{uid}.role == 'admin'` in app code.

Drivers open intersection search from the dashboard or tracking page. The manual-request contract is:

- `TrafficService` checks a signed-in, approved driver (`role == 'driver'`, `isApproved == true`), reloads the active intersection, obtains fresh GPS, and checks distance **<= 500 m**. UI distance checks alone are insufficient.
- Match eligible officers by explicit `assignedIntersectionId` first. If present, a mismatch must not fall through. Otherwise use assigned coordinates **<= 250 m**; only without coordinates use normalized (trimmed, lowercased) `assignedIntersection`, exactly matching the intersection name, short Plus Code, or `plusCode, city`. This is not substring matching.
- Write an alert per matched officer in the existing `emergency_alerts` collection, preserving officer-specific routing (`officerId`/`policeUid`). A manual request does **not** override hardware or automatically turn signals green; the officer handles the response.

`TrafficService.requestEmergencyEscape` implements these checks and re-reads the intersection and matched officers in the alert-write transaction. GPS readings older than 30 seconds or with reported accuracy worse than 100 m are rejected. Repeated requests do not overwrite active alerts or immediately reopen cleared/overridden ones (one-minute cooldown). Existing automatic route alerts also use the 500 m approach limit, with an additional heading check; manual requests do not require a heading.

All four entries have been written to project `e-ambulance-system-001` through the existing Firebase CLI account and read back for verification. IDs are `khulna_vgx3_g39`, `khulna_moylapota_mor`, `khulna_royal_mor`, and `khulna_shibbari_mor`. Each stored document has `wayCount: 4`, `trafficLightCount: 4`, and distinct North/East/South/West light records. Existing document edits, controller mappings, and states were preserved using conditional writes. The three new centers were independently decoded using `openlocationcode` 1.0.1 with a Khulna reference. GPS/on-device notification delivery has not been tested end to end.

## Hardware limitations

The repository now includes **four-way v2 prototype firmware**, a matching BLE protocol and directional police controls. See [traffic_light_firmware.md](traffic_light_firmware.md) for pin wiring, required intersection binding, safety transitions and flashing prerequisites. The directory alone does **not** assign physical controllers or synchronize live signal states. No hardware was flashed automatically. This prototype has no physical output feedback or public-road safety certification; hardware, security and electrical validation remain required.

## Critical deployment/security requirements

The repository has **no Firestore rules file or Firestore rules configuration** (`firebase.json` only configures Flutter apps). Existing production rules are unknown. **Do not invent broad rules or deploy rules from this document.** First retrieve/review the existing rules, then merge and test a narrowly scoped change. Overlapping permissive rules can defeat a restrictive match.

Minimal illustrative directory match, placed inside the existing `/databases/{database}/documents` block:

```text
match /intersections/{intersectionId} {
  function isDirectoryAdmin() {
    return request.auth != null
      && get(/databases/$(database)/documents/users/$(request.auth.uid)).data.role == 'admin';
  }
  function validIntersection() {
    let d = request.resource.data;
    return d.keys().hasAll([
        'name', 'city', 'latitude', 'longitude', 'plusCode', 'isActive'
      ])
      && d.name is string && d.name.size() > 0 && d.name.size() <= 200
      && d.city is string && d.city.size() > 0 && d.city.size() <= 100
      && d.latitude is number && d.latitude >= -90 && d.latitude <= 90
      && d.longitude is number && d.longitude >= -180 && d.longitude <= 180
      && d.plusCode is string && d.plusCode.size() <= 16
      && d.isActive is bool
      && (!('fullPlusCode' in d)
          || (d.fullPlusCode is string && d.fullPlusCode.size() <= 16))
      && (!('location' in d)
          || (d.location is latlng
              && d.location.latitude == d.latitude
              && d.location.longitude == d.longitude));
  }
  allow read: if request.auth != null;
  allow create, update: if isDirectoryAdmin() && validIntersection();
  allow delete: if isDirectoryAdmin();
}
```

This snippet only covers basic directory fields; it does not validate the four-way traffic-light schema. Before deployment, adapt metadata/allowed-field constraints and validate `wayCount == 4`, `trafficLightCount == 4`, all four directional map entries, distinct light IDs, matching directions, nullable string controller IDs, and permitted state values against the existing schema. Ensure users cannot self-assign or self-change `role` or `isApproved` in `users/{uid}` (including profile creation). **App-level admin/approved-driver checks are not server security.** Separately secure `emergency_alerts` with server rules and/or a trusted backend for authorized creation, recipients, field validation, and state transitions. Modified clients can bypass Dart checks; client GPS can be spoofed, so even server distance validation against submitted coordinates does not prove physical proximity. No rules were deployed.
