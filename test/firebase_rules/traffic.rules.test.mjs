import { readFile } from 'node:fs/promises';
import assert from 'node:assert/strict';
import { after, before, beforeEach, test } from 'node:test';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  Timestamp,
  collection,
  collectionGroup,
  deleteDoc,
  deleteField,
  doc,
  getDoc,
  getDocs,
  limit,
  query,
  serverTimestamp,
  setDoc,
  setLogLevel,
  updateDoc,
  where,
  writeBatch,
} from 'firebase/firestore';

// Refuse any other endpoint/project; this suite never contacts live Firestore.
const projectId = 'demo-traffic-rules';
assert.equal(process.env.FIRESTORE_EMULATOR_HOST, '127.0.0.1:8185',
  'Run with the documented firebase emulators:exec command on port 8185');
setLogLevel('silent');
let env;
const approved = {
  role: 'traffic_police',
  isVerified: true,
  verificationStatus: 'APPROVED',
  assignedIntersectionId: 'A',
};
const controllerPath = (intersection = 'A') => `trafficControllers/${intersection}`;
const commandPath = (id = 'request_1', intersection = 'A') =>
  `${controllerPath(intersection)}/commands/${id}`;
const dbFor = (uid, claims = {}) => env.authenticatedContext(uid, claims).firestore();
const officer = () => dbFor('officer');
const device = (uid = 'deviceA') => dbFor(uid, {
  firebase: { sign_in_provider: 'password' },
});
function payload(id = 'request_1', intersection = 'A', cmd = 'SET') {
  return {
    v: 2, cmd, request_id: id, intersection, uid: 'officer', role: 'traffic_police',
    ...(cmd === 'SET' ? { direction: 'north', light: 'green' } : {}),
    ...(cmd === 'AUTO' ? { green_sec: 30, yellow_sec: 3, all_red_sec: 2 } : {}),
  };
}
function envelope(id = 'request_1', intersection = 'A', cmd = 'SET') {
  return {
    state: 'pending',
    createdAt: serverTimestamp(),
    // Match the app's conservative margin below the server's 20s cap.
    expiresAt: Timestamp.fromMillis(Date.now() + 15_000),
    payload: payload(id, intersection, cmd),
  };
}
const telemetry = (overrides = {}) => ({
  statusJson: '{"v":2,"intersection":"A"}',
  reportedAt: serverTimestamp(), sampledAt: Timestamp.now(),
  transport: 'firebase', blePriority: false,
  ...overrides,
});
const ack = (overrides = {}) => ({
  state: 'accepted', error: '', ackJson: '{"v":2,"ack_id":"seed"}', ...overrides,
});
async function seed(path, data) {
  await env.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), path), data);
  });
}
async function create(data, id = 'request_1', db = officer(), intersection = 'A') {
  return setDoc(doc(db, commandPath(id, intersection)), data);
}

async function commitTelemetry(sampledAt, uid = 'deviceA') {
  // Unsigned mock JWTs are accepted ONLY by the emulator; no live auth tokens.
  const now = Math.floor(Date.now() / 1000);
  const encode = (value) => Buffer.from(JSON.stringify(value)).toString('base64url');
  const token = `${encode({ alg: 'none', typ: 'JWT' })}.${encode({
    sub: uid, user_id: uid, aud: projectId,
    iss: `https://securetoken.google.com/${projectId}`,
    iat: now, exp: now + 3600, auth_time: now,
    firebase: { sign_in_provider: 'password' },
  })}.`;
  const fields = {
    statusJson: { stringValue: '{"v":2,"intersection":"A"}' },
    transport: { stringValue: 'firebase' },
    blePriority: { booleanValue: false },
  };
  if (sampledAt !== null) fields.sampledAt = sampledAt;
  return fetch(`http://127.0.0.1:8185/v1/projects/${projectId}/databases/(default)/documents:commit`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
    signal: AbortSignal.timeout(10_000),
    body: JSON.stringify({ writes: [{
      update: { name: `projects/${projectId}/databases/(default)/documents/${controllerPath()}`, fields },
      currentDocument: { exists: true },
      updateMask: { fieldPaths: ['statusJson', 'sampledAt', 'transport', 'blePriority'] },
      updateTransforms: [{ fieldPath: 'reportedAt', setToServerValue: 'REQUEST_TIME' }],
    }] }),
  });
}

before(async () => {
  env = await initializeTestEnvironment({
    projectId,
    firestore: {
      host: '127.0.0.1', port: 8185,
      rules: await readFile(new URL('../../firestore.traffic.rules', import.meta.url), 'utf8'),
    },
  });
});
after(async () => { await env?.cleanup(); });
beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    const batch = writeBatch(db);
    batch.set(doc(db, 'users/officer'), approved);
    batch.set(doc(db, 'users/officerB'), { ...approved, assignedIntersectionId: 'B' });
    batch.set(doc(db, 'users/profileAdmin'), { role: 'admin', admin: true });
    batch.set(doc(db, 'intersections/A'), { isActive: true });
    batch.set(doc(db, 'intersections/B'), { isActive: true });
    batch.set(doc(db, controllerPath()), { deviceUid: 'deviceA' });
    batch.set(doc(db, controllerPath('B')), { deviceUid: 'deviceB' });
    for (const intersection of ['A', 'B']) {
      batch.set(doc(db, commandPath('seed', intersection)), {
        state: 'pending', createdAt: Timestamp.now(),
        expiresAt: Timestamp.fromMillis(Date.now() + 15_000),
        payload: payload('seed', intersection),
      });
    }
    await batch.commit();
  });
});

test('unauthenticated clients cannot read, query or write traffic', async () => {
  const db = env.unauthenticatedContext().firestore();
  await assertFails(getDoc(doc(db, controllerPath())));
  await assertFails(getDoc(doc(db, commandPath('seed'))));
  await assertFails(getDocs(collection(db, `${controllerPath()}/commands`)));
  await assertFails(create(envelope(), 'request_1', db));
  await assertFails(updateDoc(doc(db, controllerPath()), telemetry()));
});

test('approved officer can read assigned controller/all commands, never other intersections', async () => {
  const db = officer();
  await assertSucceeds(getDoc(doc(db, controllerPath())));
  await assertSucceeds(getDoc(doc(db, commandPath('seed'))));
  await seed(commandPath('another'), {
    state: 'accepted', payload: { ...payload('another'), uid: 'officerB' },
  });
  const result = await assertSucceeds(getDocs(collection(db, `${controllerPath()}/commands`)));
  assert.equal(result.size, 2);
  await assertFails(getDoc(doc(db, controllerPath('B'))));
  await assertFails(getDoc(doc(db, commandPath('seed', 'B'))));
  await assertFails(getDocs(collection(db, `${controllerPath('B')}/commands`)));
  await assertFails(getDocs(collection(db, 'trafficControllers')));
  await assertFails(getDocs(collectionGroup(db, 'commands')));
});

test('unassigned, unverified, unapproved, wrong-role and missing profiles fail', async (t) => {
  for (const [name, profile] of Object.entries({
    unassigned: { ...approved, assignedIntersectionId: 'B' },
    noAssignment: { role: 'traffic_police', isVerified: true, verificationStatus: 'APPROVED' },
    unverified: { ...approved, isVerified: false },
    pending: { ...approved, verificationStatus: 'PENDING' },
    lowercase: { ...approved, verificationStatus: 'approved' },
    wrongRole: { ...approved, role: 'admin' },
    stringVerified: { ...approved, isVerified: 'true' },
  })) {
    await t.test(name, async () => {
      await seed('users/officer', profile);
      await assertFails(create(envelope()));
      await assertFails(getDoc(doc(officer(), controllerPath())));
      await assertFails(getDocs(collection(officer(), `${controllerPath()}/commands`)));
    });
  }
  await assertFails(create(envelope(), 'request_1', dbFor('noProfile')));
});

test('inactive/missing intersections and missing/unprovisioned controllers block creation', async () => {
  await seed('intersections/A', { isActive: false });
  await assertFails(create(envelope()));
  await assertFails(getDoc(doc(officer(), controllerPath())));
  await env.withSecurityRulesDisabled(async (context) => {
    await deleteDoc(doc(context.firestore(), 'intersections/A'));
  });
  await assertFails(create(envelope()));
  await seed('intersections/A', { isActive: true });
  for (const invalid of [{}, { deviceUid: '' }, { deviceUid: 42 }]) {
    await seed(controllerPath(), invalid);
    await assertFails(create(envelope()));
  }
  await env.withSecurityRulesDisabled(async (context) => {
    await deleteDoc(doc(context.firestore(), controllerPath()));
  });
  await assertFails(create(envelope()));
});

test('all five command types and allowed SET direction/light values create pending documents', async () => {
  for (const cmd of ['SET', 'AUTO', 'ALL_RED', 'MANUAL', 'STATUS']) {
    await assertSucceeds(create(envelope(cmd, 'A', cmd), cmd));
  }
  for (const direction of ['north', 'east', 'south', 'west']) {
    for (const light of ['red', 'yellow', 'green']) {
      const id = `${direction}_${light}`;
      const data = envelope(id);
      Object.assign(data.payload, { direction, light });
      await assertSucceeds(create(data, id));
    }
  }
});

test('AUTO timing integer boundaries are accepted', async () => {
  for (const [id, timings] of [
    ['min', { green_sec: 5, yellow_sec: 3, all_red_sec: 2 }],
    ['max', { green_sec: 300, yellow_sec: 60, all_red_sec: 60 }],
  ]) {
    const data = envelope(id, 'A', 'AUTO');
    Object.assign(data.payload, timings);
    await assertSucceeds(create(data, id));
  }
});

test('payload identity/version spoofing and forbidden keys fail', async (t) => {
  for (const [name, changes] of Object.entries({
    uid: { uid: 'victim' }, intersection: { intersection: 'B' },
    requestId: { request_id: 'other' }, role: { role: 'admin' },
    version: { v: 1 }, stringVersion: { v: '2' },
    password: { pass: 'never-upload-a-secret' }, extra: { surprise: true },
    direction: { direction: 'NORTH' }, light: { light: 'blue' },
    unknownCommand: { cmd: 'RESET' },
  })) {
    await t.test(name, async () => {
      const data = envelope();
      Object.assign(data.payload, changes);
      await assertFails(create(data));
    });
  }
  const missing = envelope();
  delete missing.payload.uid;
  await assertFails(create(missing));
  for (const cmd of ['ALL_RED', 'MANUAL', 'STATUS']) {
    const data = envelope('request_1', 'A', cmd);
    data.payload.direction = 'north';
    await assertFails(create(data));
  }
});

test('AUTO rejects out-of-range, overflow, fractional, string and missing timings', async (t) => {
  for (const [field, invalids] of Object.entries({
    green_sec: [4, 301, 2 ** 40, 5.5, '30', null],
    yellow_sec: [2, 61, 3.5], all_red_sec: [1, 61, 2.5],
  })) {
    for (const value of invalids) {
      await t.test(`${field}=${value}`, async () => {
        const data = envelope('request_1', 'A', 'AUTO');
        data.payload[field] = value;
        await assertFails(create(data));
      });
    }
  }
  const data = envelope('request_1', 'A', 'AUTO');
  delete data.payload.all_red_sec;
  await assertFails(create(data));
});

test('command IDs use ASCII allowlist and 32-character cap', async () => {
  for (const id of ['bad.id', 'bad space', 'é', 'a'.repeat(33)]) {
    await assertFails(create(envelope(id), id));
  }
  const id = 'Ab_9-'.padEnd(32, 'x');
  await assertSucceeds(create(envelope(id), id));
});

test('strict envelope, pending state, server timestamp and 20-second expiry cap', async (t) => {
  const cases = {
    expired: () => ({ expiresAt: Timestamp.fromMillis(Date.now() - 1000) }),
    zeroLifetime: () => ({ expiresAt: serverTimestamp() }),
    over20: () => ({ expiresAt: Timestamp.fromMillis(Date.now() + 21_000) }),
    overflow: () => ({ expiresAt: Timestamp.fromMillis(253402300799000) }),
    stringExpiry: () => ({ expiresAt: 'later' }),
    staleCreated: () => ({ createdAt: Timestamp.fromMillis(Date.now() - 1000) }),
    futureCreated: () => ({ createdAt: Timestamp.fromMillis(Date.now() + 60_000) }),
    terminal: () => ({ state: 'accepted' }),
    extra: () => ({ error: '' }),
    notMap: () => ({ payload: 'SET' }),
  };
  for (const [name, changes] of Object.entries(cases)) {
    await t.test(name, async () => {
      await assertFails(create({ ...envelope(), ...changes() }));
    });
  }
  for (const field of ['state', 'createdAt', 'expiresAt', 'payload']) {
    const data = envelope();
    delete data[field];
    await assertFails(create(data));
  }
});

test('officer cannot ACK, overwrite, delete, provision or write telemetry', async () => {
  const db = officer();
  await assertFails(updateDoc(doc(db, commandPath('seed')), ack()));
  await assertFails(setDoc(doc(db, commandPath('seed')), envelope('seed')));
  await assertFails(deleteDoc(doc(db, commandPath('seed'))));
  await assertFails(updateDoc(doc(db, controllerPath()), telemetry()));
  await assertFails(updateDoc(doc(db, controllerPath()), { deviceUid: 'officer' }));
  await assertFails(setDoc(doc(db, controllerPath('C')), { deviceUid: 'officer' }));
  await assertFails(deleteDoc(doc(db, controllerPath())));
});

test('bound password device reads controller and queries all own commands, not other intersections', async () => {
  const db = device();
  await assertSucceeds(getDoc(doc(db, controllerPath())));
  await assertSucceeds(getDoc(doc(db, commandPath('seed'))));
  await assertSucceeds(getDocs(collection(db, `${controllerPath()}/commands`)));
  const pending = query(collection(db, `${controllerPath()}/commands`),
    where('state', '==', 'pending'), limit(1));
  assert.equal((await assertSucceeds(getDocs(pending))).size, 1);
  await assertFails(getDoc(doc(db, controllerPath('B'))));
  await assertFails(getDoc(doc(db, commandPath('seed', 'B'))));
  await assertFails(getDocs(collection(db, `${controllerPath('B')}/commands`)));
  await assertFails(getDocs(collectionGroup(db, 'commands')));
  await assertFails(getDocs(collection(db, 'trafficControllers')));
  await assertFails(getDoc(doc(dbFor('deviceA', {
    firebase: { sign_in_provider: 'anonymous' },
  }), controllerPath())));
});

test('only bound device updates telemetry, using server time and strict types/byte limits', async (t) => {
  const db = device();
  const missingSample = telemetry();
  delete missingSample.sampledAt;
  await assertFails(updateDoc(doc(db, controllerPath()), missingSample));
  for (const transport of ['ble', 'firebase', 'idle']) {
    await assertSucceeds(updateDoc(doc(db, controllerPath()), telemetry({ transport })));
  }
  await assertSucceeds(updateDoc(doc(db, controllerPath()), telemetry({ statusJson: 'x'.repeat(511) })));
  for (const [name, changes] of Object.entries({
    stale: { reportedAt: Timestamp.fromMillis(Date.now() - 1000) },
    missingTime: { reportedAt: deleteField() },
    missingSample: { sampledAt: deleteField() },
    sampleType: { sampledAt: 'now' },
    futureSample: { sampledAt: Timestamp.fromMillis(Date.now() + 3000) },
    oldSample: { sampledAt: Timestamp.fromMillis(Date.now() - 7000) },
    timeType: { reportedAt: 'now' }, transport: { transport: 'wifi' },
    priority: { blePriority: 'true' }, statusType: { statusJson: {} },
    tooLong: { statusJson: 'x'.repeat(512) },
    utf8TooLong: { statusJson: 'é'.repeat(256) },
    rebind: { deviceUid: 'deviceB' }, extra: { secret: 'not-allowed' },
  })) {
    await t.test(name, async () => {
      await assertFails(updateDoc(doc(db, controllerPath()), telemetry(changes)));
    });
  }
  await assertFails(updateDoc(doc(device('deviceB'), controllerPath()), telemetry()));
  await assertFails(setDoc(doc(db, controllerPath('C')), { deviceUid: 'deviceA', ...telemetry() }));
  await assertFails(deleteDoc(doc(db, controllerPath())));
});

test('firmware REST commit accepts fresh sample timestamps and rejects invalid samples', async (t) => {
  const db = device();
  for (const offset of [0, -5000, 1000]) {
    const sampledAt = new Date(Date.now() + offset).toISOString();
    const response = await commitTelemetry({ timestampValue: sampledAt });
    assert.equal(response.status, 200, await response.text());
    const stored = (await getDoc(doc(db, controllerPath()))).data();
    assert.equal(stored.deviceUid, 'deviceA');
    assert.equal(stored.sampledAt.toDate().toISOString(), sampledAt);
    assert.ok(stored.reportedAt instanceof Timestamp);
  }
  for (const [name, value] of Object.entries({
    missing: () => null,
    wrongType: () => ({ stringValue: new Date().toISOString() }),
    future3sec: () => ({ timestampValue: new Date(Date.now() + 3000).toISOString() }),
    old7sec: () => ({ timestampValue: new Date(Date.now() - 7000).toISOString() }),
  })) {
    await t.test(name, async () => {
      const before = (await getDoc(doc(db, controllerPath()))).data();
      const response = await commitTelemetry(value());
      assert.equal(response.status, 403, await response.text());
      assert.deepEqual((await getDoc(doc(db, controllerPath()))).data(), before);
    });
  }
  for (const uid of ['officer', 'deviceB']) {
    const response = await commitTelemetry({ timestampValue: new Date().toISOString() }, uid);
    assert.equal(response.status, 403, await response.text());
  }
});

test('fresh reportedAt cannot revive a stored stale sample without a new sample time', async () => {
  await seed(controllerPath(), {
    deviceUid: 'deviceA', ...telemetry({
      reportedAt: Timestamp.now(), sampledAt: Timestamp.fromMillis(Date.now() - 7000),
    }),
  });
  await assertFails(updateDoc(doc(device(), controllerPath()), { reportedAt: serverTimestamp() }));
});

test('bound device accepts/rejects pending commands and preserves every original field', async () => {
  const db = device();
  const ref = doc(db, commandPath('seed'));
  const original = (await getDoc(ref)).data();
  await assertSucceeds(updateDoc(ref, ack()));
  const result = (await getDoc(ref)).data();
  for (const key of ['createdAt', 'expiresAt', 'payload']) {
    assert.deepEqual(result[key], original[key]);
  }
  // Repeat the firmware's three-field PATCH after a simulated lost response.
  await assertSucceeds(updateDoc(ref, ack()));
  assert.deepEqual((await getDoc(ref)).data(), result);
  await assertFails(updateDoc(ref, ack({ state: 'rejected', error: 'changed' })));
  await assertSucceeds(create(envelope('reject'), 'reject'));
  const rejectedRef = doc(db, commandPath('reject'));
  await assertSucceeds(updateDoc(rejectedRef,
    ack({ state: 'rejected', error: 'expired' })));
  const rejectedResult = (await getDoc(rejectedRef)).data();
  await assertSucceeds(updateDoc(rejectedRef,
    ack({ state: 'rejected', error: 'expired' })));
  assert.deepEqual((await getDoc(rejectedRef)).data(), rejectedResult);
});

test('terminal ACK retries deny every mutation and require the bound device', async (t) => {
  for (const state of ['accepted', 'rejected']) {
    await t.test(state, async () => {
      const db = device();
      const id = `terminal_${state}`;
      await assertSucceeds(create(envelope(id), id));
      const ref = doc(db, commandPath(id));
      const result = ack({ state, error: state === 'accepted' ? '' : 'expired' });
      await assertSucceeds(updateDoc(ref, result));
      const committed = (await getDoc(ref)).data();
      for (const changes of [
        { ackJson: '{"changed":true}' },
        { error: 'different_error' },
        { state: state === 'accepted' ? 'rejected' : 'accepted' },
        { state: 'pending' },
        { payload: { ...payload(id), uid: 'forged' } },
        { createdAt: serverTimestamp() },
        { expiresAt: Timestamp.fromMillis(Date.now() + 60_000) },
        { ackJson: deleteField() },
        { extra: true },
      ]) {
        await assertFails(updateDoc(ref, { ...result, ...changes }));
      }
      for (const unauthorized of [officer(), device('deviceB'),
        dbFor('claimAdmin', { admin: true }), env.unauthenticatedContext().firestore()]) {
        await assertFails(updateDoc(doc(unauthorized, commandPath(id)), result));
      }
      await assertSucceeds(updateDoc(ref, result));
      assert.deepEqual((await getDoc(ref)).data(), committed);
    });
  }
  // A pending document does not qualify for the terminal no-op exception.
  await assertFails(updateDoc(doc(device(), commandPath('seed')), { state: 'pending' }));
});

test('device cannot forge commands, ACK other controllers, change originals or send invalid ACKs', async (t) => {
  const db = device();
  await assertFails(create(envelope(), 'request_1', db));
  await assertFails(deleteDoc(doc(db, commandPath('seed'))));
  await assertFails(updateDoc(doc(device('deviceB'), commandPath('seed')), ack()));
  await assertFails(updateDoc(doc(db, commandPath('seed', 'B')), ack()));
  for (const [name, changes] of Object.entries({
    payload: { payload: { ...payload('seed'), uid: 'forged' } },
    created: { createdAt: serverTimestamp() },
    expiry: { expiresAt: Timestamp.fromMillis(Date.now() + 60_000) },
    deletePayload: { payload: deleteField() },
    extra: { secret: true }, pending: { state: 'pending' },
    acceptedError: { error: 'oops' }, rejectedEmpty: { state: 'rejected', error: '' },
    oversizedError: { state: 'rejected', error: 'x'.repeat(65) },
    oversizedAck: { ackJson: 'x'.repeat(512) }, utf8Ack: { ackJson: 'é'.repeat(256) },
    errorType: { error: 123 }, ackType: { ackJson: {} },
    missingAck: { ackJson: deleteField() },
  })) {
    await t.test(name, async () => {
      await assertFails(updateDoc(doc(db, commandPath('seed')), ack(changes)));
    });
  }
  await assertSucceeds(updateDoc(doc(db, commandPath('seed')),
    ack({ state: 'rejected', error: 'e'.repeat(64), ackJson: 'x'.repeat(511) })));
});

test('admin custom claim alone provisions/rebinds/deletes; profile admin never grants authority', async () => {
  const admin = dbFor('claimAdmin', { admin: true });
  const ref = doc(admin, controllerPath('C'));
  await assertSucceeds(setDoc(ref, { deviceUid: 'deviceC' }));
  await assertSucceeds(updateDoc(ref, { deviceUid: 'deviceD' }));
  await assertFails(updateDoc(ref, telemetry()));
  await assertFails(updateDoc(ref, { deviceUid: '' }));
  await assertFails(updateDoc(ref, { deviceUid: 42 }));
  await assertFails(updateDoc(ref, { deviceUid: deleteField() }));
  await assertFails(setDoc(doc(admin, controllerPath('D')), { deviceUid: 'd', ...telemetry() }));
  await assertFails(setDoc(doc(admin, controllerPath('D')), {}));
  await assertFails(setDoc(doc(dbFor('profileAdmin'), controllerPath('D')), { deviceUid: 'd' }));
  await assertFails(setDoc(doc(dbFor('fakeAdmin', { admin: 'true' }), controllerPath('D')), { deviceUid: 'd' }));
  await assertFails(create(envelope(), 'request_1', admin));
  await assertFails(updateDoc(doc(admin, commandPath('seed')), ack()));
  await assertSucceeds(deleteDoc(ref));
  // Rebinding takes effect immediately for the old and new device identities.
  await assertSucceeds(updateDoc(doc(admin, controllerPath()), { deviceUid: 'deviceNew' }));
  await assertFails(getDoc(doc(device(), controllerPath())));
  await assertFails(updateDoc(doc(device(), commandPath('seed')), ack()));
  await assertSucceeds(getDoc(doc(device('deviceNew'), controllerPath())));
});

test('profiles/intersections/default paths are client-denied, including self-promotion and admin claims', async () => {
  for (const db of [officer(), device(), dbFor('claimAdmin', { admin: true })]) {
    await assertFails(getDoc(doc(db, 'users/officer')));
    await assertFails(getDocs(collection(db, 'users')));
    await assertFails(setDoc(doc(db, 'users/newOfficer'), approved));
    await assertFails(updateDoc(doc(db, 'users/officer'), { role: 'admin', admin: true }));
    await assertFails(deleteDoc(doc(db, 'users/officer')));
    await assertFails(getDoc(doc(db, 'intersections/A')));
    await assertFails(updateDoc(doc(db, 'intersections/A'), { isActive: true }));
    await assertFails(setDoc(doc(db, 'unrelated/secret'), { data: true }));
    await assertFails(getDoc(doc(db, 'unrelated/secret')));
  }
  const db = officer();
  const batch = writeBatch(db);
  batch.update(doc(db, 'users/officer'), { assignedIntersectionId: 'B' });
  batch.set(doc(db, commandPath('batch', 'B')), envelope('batch', 'B'));
  await assertFails(batch.commit());
});

test('revocation blocks new officer activity, but device pending query remains readable (TTL race)', async () => {
  await assertSucceeds(create(envelope()));
  await seed('users/officer', { ...approved, isVerified: false });
  await assertFails(create(envelope('after'), 'after'));
  await assertFails(getDoc(doc(officer(), commandPath())));
  await assertSucceeds(getDocs(query(collection(device(), `${controllerPath()}/commands`),
    where('state', '==', 'pending'), limit(1))));
  // Rules do not check submitter profiles or expiry on device reads/ACKs.
  // Firmware is responsible for rejecting expired tickets before execution.
  await seed(commandPath('expired'), {
    state: 'pending', createdAt: Timestamp.fromMillis(Date.now() - 30_000),
    expiresAt: Timestamp.fromMillis(Date.now() - 10_000), payload: payload('expired'),
  });
  await assertSucceeds(updateDoc(doc(device(), commandPath('expired')),
    ack({ state: 'rejected', error: 'expired' })));
});
