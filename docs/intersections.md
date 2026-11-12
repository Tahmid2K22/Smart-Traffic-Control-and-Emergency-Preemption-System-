# Intersections directory

## Verified Khulna Plus Code

Using Google's [Open Location Code Python implementation](https://github.com/google/open-location-code/blob/main/python/openlocationcode/openlocationcode.py):

- `recoverNearest('VGX3+G39', 22.8456, 89.5403)` (Khulna vicinity reference) returns **`7MJFVGX3+G39`**.
- Decoded bounds: latitude `[22.898775, 22.8988)`, longitude `[89.50271875, 89.50275)`.
- Exact center: **`22.8987875, 89.502734375`**.
- `encode(22.8987875, 89.502734375, 11)` returns `7MJFVGX3+G39`.

The supplied recovery and center are correct. Short codes require a nearby reference; this verifies the geographic code, not the existence or official name of a road intersection.

## Directory and app flow

Firestore `intersections/{id}` stores `name`, `city`, numeric `latitude`/`longitude`, `plusCode`, and boolean `isActive`, with creation/update metadata. Admin saves also write a `location` GeoPoint; the seed includes `fullPlusCode` but does not require `location`.

Opening the admin intersections page automatically calls `IntersectionService.seedKhulnaIntersection()`. Its transaction creates `khulna_vgx3_g39` only if absent, so repeated openings neither duplicate nor overwrite it. Admins can add/edit entries and enable/disable them. `IntersectionService` checks the signed-in user's `users/{uid}.role == 'admin'` in app code.

Drivers open intersection search from the dashboard or tracking page. The manual-request contract is:

- `TrafficService` checks a signed-in, approved driver (`role == 'driver'`, `isApproved == true`), reloads the active intersection, obtains fresh GPS, and checks distance **<= 500 m**. UI distance checks alone are insufficient.
- Match eligible officers by explicit `assignedIntersectionId` first. If present, a mismatch must not fall through. Otherwise use assigned coordinates **<= 250 m**; only without coordinates use normalized (trimmed, lowercased) `assignedIntersection`, exactly matching the intersection name, short Plus Code, or `plusCode, city`. This is not substring matching.
- Write an alert per matched officer in the existing `emergency_alerts` collection, preserving officer-specific routing (`officerId`/`policeUid`). A manual request does **not** override hardware or automatically turn signals green; the officer handles the response.

`TrafficService.requestEmergencyEscape` implements these checks and re-reads the intersection and matched officers in the alert-write transaction. GPS readings older than 30 seconds or with reported accuracy worse than 100 m are rejected. Repeated requests do not overwrite active alerts or immediately reopen cleared/overridden ones (one-minute cooldown). Existing automatic route alerts also use the 500 m approach limit, with an additional heading check; manual requests do not require a heading.

The seed was inserted into project `e-ambulance-system-001` at `intersections/khulna_vgx3_g39` on 2026-11-03 through the existing Firebase CLI account. The API confirmed the stored coordinates and active status. GPS/on-device notification delivery has not been tested end to end.

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

This snippet only covers the directory; adapt metadata/allowed-field constraints to the existing schema. Ensure users cannot self-assign or self-change `role` or `isApproved` in `users/{uid}` (including profile creation). **App-level admin/approved-driver checks are not server security.** Separately secure `emergency_alerts` with server rules and/or a trusted backend for authorized creation, recipients, field validation, and state transitions. Modified clients can bypass Dart checks; client GPS can be spoofed, so even server distance validation against submitted coordinates does not prove physical proximity. No rules were deployed.
