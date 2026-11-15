# Traffic-only Firestore rules: MERGE BEFORE DEPLOY

**Do not deploy `firebase.traffic.json` or `firestore.traffic.rules` as-is to a
live project. No deployment is part of this change.** Firestore deploys replace
an entire database ruleset; this is not an additive patch. The existing
`firebase.json` is unchanged and does not configure Firestore rules. Absence of
a local rules file says nothing about the rules currently deployed remotely.

## Mandatory live-rules integration review

1. Export/retrieve and back up the **actual live rules** using the Firebase
   console or an authorized rules-management workflow. Do not infer them from
   this repository. Merge this traffic match/helpers into that reviewed ruleset.
2. Audit **every overlapping match** (including recursive authenticated-user,
   public, collection-group and admin grants). Firestore allows are ORed:
   `allow ...: if false` does **not** override another matching allow. A broad
   existing grant can bypass **all** traffic restrictions here. Narrow/remove
   conflicting grants before considering deployment.
3. Protect `users/{uid}` authorization fields: `role`, `isVerified`,
   `verificationStatus`, `assignedIntersectionId`, and any related authorization
   source must never be self-writable. This standalone file denies **all**
   profile writes, even from custom-claim admins; use a trusted Admin SDK
   backend. If the merged app needs user-editable profile fields, explicitly
   allowlist those fields and protect authorization fields on **both create and
   update**. A generic owner-write rule permits self-promotion and is unsafe.
   Protect `intersections/{id}.isActive` similarly. Admin SDK bypasses rules and
   must enforce authorization in trusted server code/IAM.
4. Restore only the app's necessary, independently reviewed profile/intersection
   read permissions in the merged rules. The standalone test rules deny those
   reads and all unrelated paths; they are **not** a whole-app replacement.
5. Run these tests **against the merged rules too**, adapting the test rules
   loader in this directory to the reviewed candidate. Repeat application and
   authorization regression tests. Only an authorized operator should then
   configure a separately reviewed live deployment. No live deploy command is
   provided intentionally.

`firebase.traffic.json` is a valid JSON config, with an explanatory `_comment`
metadata field rather than invalid JSON comments. It points only at these
traffic rules and an isolated local Firestore emulator (`127.0.0.1:8185`).

## Local emulator tests

Requirements: Node **24.12+**, npm, Firebase CLI compatible with Node 24
(verified locally with **15.24.0**), and Java supported by that CLI's Firestore
emulator (Java 25 was available during validation; recent emulators need 21+).
First run downloads the Firestore emulator if it is not cached. Installing the
pinned test-only dependencies uses npm/network access; no keys or production
credentials are needed.

From the repository root:

```sh
npm --prefix test/firebase_rules ci --ignore-scripts --no-audit --no-fund
firebase emulators:exec --config firebase.traffic.json --project demo-traffic-rules --only firestore "npm --prefix test/firebase_rules test"
```

The command starts/stops the emulator around Node's built-in test runner; do
not run a standalone persistent emulator for this workflow. If your environment
imposes timeouts, allow enough time for the first JAR download. All commands
use the **demo** project, never the application's live Firebase project. The
suite refuses to start unless `FIRESTORE_EMULATOR_HOST` is exactly
`127.0.0.1:8185`; the environment always uses `demo-traffic-rules`. No Auth
emulator is needed: rules-unit-testing mocks auth tokens, and fixtures use
`withSecurityRulesDisabled`. Tests clear this demo project's emulator data
before each top-level test. Do not share this emulator with other work.

If port 8185 is occupied, stop the conflicting local process or deliberately
change **both** the isolated config and test guard. Never fall back to a live
Firestore connection. Debug artifacts, if generated, should be placed in this
directory, not at the repository root. One way to do that is to run the same
CLI invocation from `test/firebase_rules` with
`--config ../../firebase.traffic.json` and the command `"npm test"`.

## Enforced contract

- `trafficControllers/{intersectionId}` is provisioned using an **admin custom
  claim** (`request.auth.token.admin == true`), never a user profile role. Create
  contains only a nonempty string `deviceUid`; admin updates may change only
  that field, and admin deletion is allowed. This simple provisioning policy
  does not require an empty command queue before rebind/delete. Operationally,
  quiesce/drain commands before rebinding. Deleting a controller does not delete
  its commands subcollection; use trusted maintenance tooling for cleanup.
- Only the bound Firebase password-authenticated device can update the five
  telemetry fields: `statusJson` (UTF-8 **<=511 bytes**), `reportedAt` (timestamp
  equal to `request.time`), `sampledAt` (required timestamp), `transport`
  (`ble`/`firebase`/`idle`), `blePriority` (boolean). Updates require an existing
  controller and preserve `deviceUid`. `sampledAt` is the actual signal-loop
  sample UTC, not the upload/commit time, and must be between `request.time -
  6 seconds` and `request.time + 2 seconds`, inclusive. This tolerates limited
  clock skew but rejects slow in-flight/stale snapshots fail-closed, even with
  a fresh `reportedAt`. The firmware REST commit masks `statusJson`, `sampledAt`,
  `transport`, `blePriority`; `sampledAt` uses `timestampValue` while
  `reportedAt` uses a REQUEST_TIME transform. Rules trust the bound device to
  report the actual sample time; they cannot inspect physical signal state.
  An app/officer cannot write telemetry. Provision each hardware device with
  its own email/password Firebase Auth account; never reuse an officer account
  as a device identity.
- Officer authority requires a current `users/{auth.uid}` profile with exact
  role `traffic_police`, boolean `isVerified == true`, `verificationStatus ==
  'APPROVED'`, exact `assignedIntersectionId`, and an existing intersection with
  boolean `isActive == true`. No legacy assignment/name/location fallback.
  Officers can read the assigned controller and **all** commands at their
  assigned intersection, including other submitting officers' commands. They
  cannot read another intersection or query all controllers/collection groups.
- Officers create commands only on provisioned controllers. Document IDs match
  `[A-Za-z0-9_-]{1,32}`. Top-level fields are exactly `state`, `createdAt`,
  `expiresAt`, `payload`; state is `pending`, creation is server time, expiry is
  strictly after server time and at most **20 seconds** later. The app uses
  `now + 15 seconds` for a conservative margin below that server cap, providing
  tolerance for modest client clock skew rather than targeting exactly 20
  seconds. Excessive skew or a command arriving after expiry still fails
  closed; the server limit is not relaxed.
- Payload has exact base keys `v`, `cmd`, `request_id`, `intersection`, `uid`,
  `role`, with integer v2 and identity matching the document/path/auth context.
  `SET` adds only a valid lowercase direction and red/yellow/green light.
  `AUTO` adds only integer `green_sec` 5..300, `yellow_sec` 3..60,
  `all_red_sec` 2..60. `ALL_RED`, `MANUAL`, `STATUS` add no keys.
  **No passcode, password, or extra field can be uploaded.**
- A bound device can read all its own commands, including the firmware's
  `state == pending`, `limit(1)` query, but cannot create/delete commands.
  Only it may transition `pending` to `accepted`/`rejected`, changing exactly
  `state`, `error` (UTF-8 <=64 bytes), `ackJson` (UTF-8 <=511 bytes).
  Accepted requires empty error; rejected requires nonempty error. All original
  command fields remain unchanged. Once terminal, only the bound device may
  retry an ACK whose resulting document is **exactly equal** to the stored
  document; no field may change. Officers cannot update/delete, even pending
  commands. Custom-claim admins get no command-write exception.
- JSON strings are opaque, device-trusted telemetry/ACKs; rules enforce types
  and UTF-8 size, not JSON semantics. Firmware/app retain protocol parsing,
  interlocks, BLE priority, ACK identity validation, and expiry enforcement.

## Explicit limitations / handoff

**Revocation race:** officer authority is checked at command creation (and on
subsequent officer reads), not again per command in device queries. Rules are
not filters; per-command submitting-profile predicates would make the firmware
pending query unusable. A command created immediately before assignment,
approval, or intersection activity revocation can still be fetched/executed
until its <=20-second expiry. The firmware checks ticket lifetime before
execution. Device reads/ACKs deliberately remain possible for expired tickets
so the firmware can reject them. Immediate revocation at execution requires a
separately designed trusted dispatch/authorization path, outside these files.

**Idempotent ACK retries:** if a successful ACK's HTTP response is lost, the
bound device may resend the firmware's cached `state`, `error`, `ackJson`
update mask and identical values. This exception applies only when the stored
state is `accepted` or `rejected` and `request.resource.data == resource.data`.
It does not allow changing any terminal result, payload, timestamp, or other
field, and does not allow pending no-op updates. Device binding is checked on
every retry; other devices, officers, and custom-claim-only admins cannot
retry it. Initial `pending -> accepted/rejected` writes still require the
strict ACK validation above. No firmware changes are required.

## Validation result

The isolated `emulators:exec` command above passed **95 tests, 0 failures**
(including nested cases) using Node 24.14.0, Firebase CLI 15.24.0, Firestore
emulator 1.21.0, and Java 25. Coverage includes the firmware's actual REST
commit shape (sample timestamp, update mask, REQUEST_TIME transform), missing/
wrong-type/future-3-second/old-7-second sample denials, stale-sample restamping
denial, exact terminal ACK retries, terminal mutation denials, and the bounded
revocation race. Existing access-control checks remain covered. REST tests use
unsigned emulator-only mock tokens, never production credentials. Dependencies are pinned in
`package-lock.json` for `npm ci`.

On this Windows environment the CLI reported shutdown but left its Java
emulator process listening on 8185. It was explicitly stopped after verifying
its process command line identified this demo project's emulator. If this
occurs locally, verify the process identity before terminating it; do not kill
unrelated Java processes or start a second emulator on the occupied port.

These are local security-rules tests, not an ESP32/TLS hardware integration,
Auth sign-in, physical traffic-safety, or deployed-rules audit. No deployment
has been performed.
