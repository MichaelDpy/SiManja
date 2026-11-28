// B10: callable penghapusan akun di Functions Emulator dengan client sungguhan
// (token Auth Emulator). Tidak memakai project cloud atau deploy.
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { afterEach, test } from 'node:test';
import { initializeApp, deleteApp } from 'firebase/app';
import {
  getAuth, connectAuthEmulator, createUserWithEmailAndPassword, signOut,
} from 'firebase/auth';
import {
  getFirestore, connectFirestoreEmulator, doc, getDoc, setDoc, terminate,
} from 'firebase/firestore';
import { getFunctions, connectFunctionsEmulator, httpsCallable } from 'firebase/functions';
import { emulatorAddress, projectId, profile, transaction } from './support/emulator.mjs';
import { setLifecycle } from './support/lifecycle-fixture.mjs';

const REGION = 'us-central1';
const password = 'Demo-test-Password123!';
const clients = [];

function functionsAddress() {
  const raw = process.env.FUNCTIONS_EMULATOR_HOST ?? process.env.FIREBASE_FUNCTIONS_EMULATOR_HOST ?? '127.0.0.1:5001';
  const url = new URL(raw.startsWith('http') ? raw : `http://${raw}`);
  assert.ok(['127.0.0.1', 'localhost'].includes(url.hostname), 'Tes hanya memakai emulator lokal.');
  return { host: url.hostname, port: Number(url.port) };
}

function client() {
  const app = initializeApp({ projectId, apiKey: 'emulator-only', appId: 'emulator-only' }, `del-${randomUUID()}`);
  const auth = getAuth(app);
  connectAuthEmulator(auth, emulatorAddress('FIREBASE_AUTH_EMULATOR_HOST').origin, { disableWarnings: true });
  const db = getFirestore(app);
  const fs = emulatorAddress('FIRESTORE_EMULATOR_HOST');
  connectFirestoreEmulator(db, fs.host, fs.port);
  const functions = getFunctions(app, REGION);
  const fn = functionsAddress();
  connectFunctionsEmulator(functions, fn.host, fn.port);
  const call = (name, data) => httpsCallable(functions, name)(data).then((r) => r.data);
  const c = { app, auth, db, call };
  clients.push(c);
  return c;
}

afterEach(async () => {
  for (const { app, auth, db } of clients.splice(0)) {
    try { await signOut(auth); } finally {
      try { await terminate(db); } finally { await deleteApp(app); }
    }
  }
});

async function signedIn() {
  const c = client();
  const { user } = await createUserWithEmailAndPassword(c.auth, `${randomUUID()}@example.test`, password);
  return { ...c, uid: user.uid };
}

const rid = () => `req_${randomUUID().replaceAll('-', '')}`;
const fails = (promise, code, reason) => assert.rejects(promise, (error) => {
  assert.equal(error.code, `functions/${code}`);
  if (reason) assert.equal(error.details?.reason, reason);
  return true;
});

test('B10: tanpa login ditolak (unauthenticated)', async () => {
  const c = client();
  await fails(c.call('getAccountDeletionStatus', {}), 'unauthenticated');
  await fails(c.call('requestAccountDeletion', { requestId: rid() }), 'unauthenticated');
  await fails(c.call('cancelAccountDeletion', {}), 'unauthenticated');
});

test('B10: akun baru berstatus none; permintaan membuat requested', async () => {
  const a = await signedIn();
  assert.deepEqual(await a.call('getAccountDeletionStatus', {}), { state: 'none' });
  const id = rid();
  const result = await a.call('requestAccountDeletion', { requestId: id });
  assert.equal(result.state, 'requested');
  assert.equal(result.requestId, id);
  assert.equal(result.created, true);
  assert.equal(typeof result.requestedAtMs, 'number');
  const status = await a.call('getAccountDeletionStatus', {});
  assert.equal(status.state, 'requested');
  assert.equal(status.requestId, id);
});

test('B10: permintaan ganda idempoten — satu proses, requestId pertama dipertahankan', async () => {
  const a = await signedIn();
  const first = rid();
  await a.call('requestAccountDeletion', { requestId: first });
  const again = await a.call('requestAccountDeletion', { requestId: rid() });
  assert.equal(again.created, false);
  assert.equal(again.requestId, first);
  const parallel = await Promise.all([1, 2, 3].map(() => a.call('requestAccountDeletion', { requestId: rid() })));
  assert.ok(parallel.every((r) => r.created === false && r.requestId === first));
});

test('B10: UID di payload diabaikan — tidak bisa meminta hapus akun orang lain', async () => {
  const a = await signedIn();
  const b = await signedIn();
  await b.call('requestAccountDeletion', { requestId: rid(), uid: a.uid, targetUid: a.uid });
  assert.deepEqual(await a.call('getAccountDeletionStatus', { uid: b.uid }), { state: 'none' });
  assert.equal((await b.call('getAccountDeletionStatus', {})).state, 'requested');
});

test('B10: requestId tidak valid ditolak tanpa membuat permintaan', async () => {
  const a = await signedIn();
  await fails(a.call('requestAccountDeletion', {}), 'invalid-argument', 'invalid-request-id');
  await fails(a.call('requestAccountDeletion', { requestId: 'x' }), 'invalid-argument', 'invalid-request-id');
  assert.deepEqual(await a.call('getAccountDeletionStatus', {}), { state: 'none' });
});

test('B10: batal sebelum ada permintaan tidak mengubah apa pun; batal setelah requested → cancelled', async () => {
  const a = await signedIn();
  assert.deepEqual(await a.call('cancelAccountDeletion', {}), { state: 'none' });
  await a.call('requestAccountDeletion', { requestId: rid() });
  const cancelled = await a.call('cancelAccountDeletion', {});
  assert.equal(cancelled.state, 'cancelled');
  assert.equal((await a.call('cancelAccountDeletion', {})).state, 'cancelled');
  const again = await a.call('requestAccountDeletion', { requestId: rid() });
  assert.equal(again.state, 'requested');
  assert.equal(again.created, true);
});

test('B10: dokumen lifecycle admin-only — client tidak bisa baca, buat, atau ubah', async () => {
  const a = await signedIn();
  await a.call('requestAccountDeletion', { requestId: rid() });
  const ref = doc(a.db, 'accountLifecycle', a.uid);
  await assert.rejects(getDoc(ref), { code: 'permission-denied' });
  await assert.rejects(setDoc(ref, { state: 'cancelled' }), { code: 'permission-denied' });
  const fresh = await signedIn();
  await assert.rejects(setDoc(doc(fresh.db, 'accountLifecycle', fresh.uid), { state: 'completed' }),
    { code: 'permission-denied' });
  assert.deepEqual(await fresh.call('getAccountDeletionStatus', {}), { state: 'none' });
});

test('B10: akun Auth yang dinonaktifkan tidak dapat meminta penghapusan', async () => {
  const a = await signedIn();
  // Endpoint admin khusus Auth Emulator (token "owner"), bukan API produksi.
  const { origin } = emulatorAddress('FIREBASE_AUTH_EMULATOR_HOST');
  const response = await fetch(
    `${origin}/identitytoolkit.googleapis.com/v1/projects/${projectId}/accounts:update`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: 'Bearer owner' },
      body: JSON.stringify({ localId: a.uid, disableUser: true }),
      signal: AbortSignal.timeout(5000),
    },
  );
  assert.equal(response.status, 200);
  await fails(a.call('requestAccountDeletion', { requestId: rid() }), 'permission-denied', 'account-disabled');
});

test('C09: callable requested freezes writes; safe cancellation restores versioned data access', async () => {
  const a = await signedIn();
  await setDoc(doc(a.db, 'users', a.uid), profile());
  await a.call('requestAccountDeletion', { requestId: rid() });
  const ref = doc(a.db, 'users', a.uid, 'transactions', 'after-request');
  await assert.rejects(setDoc(ref, transaction()), { code: 'permission-denied' });
  assert.equal((await a.call('getAccountDeletionStatus', {})).state, 'requested');
  assert.equal((await a.call('cancelAccountDeletion', {})).state, 'cancelled');
  await setDoc(ref, transaction());
  assert.equal((await getDoc(ref)).exists(), true);
});

test('C09: retry after partial failure cannot cancel back into an unfrozen account', async () => {
  const a = await signedIn();
  // Simulates Admin worker output, not implementation of the future worker.
  await setLifecycle(a.uid, 'failed', 'processing');
  const retry = await a.call('requestAccountDeletion', { requestId: rid() });
  assert.equal(retry.state, 'requested');
  await fails(a.call('cancelAccountDeletion', {}), 'failed-precondition', 'deletion-not-cancellable');
  assert.equal((await a.call('getAccountDeletionStatus', {})).state, 'requested');
  await assert.rejects(setDoc(doc(a.db, 'users', a.uid), profile()), { code: 'permission-denied' });
  await setLifecycle(a.uid, 'completed', 'processing');
  const completed = await a.call('requestAccountDeletion', { requestId: rid() });
  assert.equal(completed.state, 'completed');
  assert.equal(completed.created, false);
  await fails(a.call('cancelAccountDeletion', {}), 'failed-precondition', 'deletion-not-cancellable');
});

test('C09: malformed lifecycle cannot be reopened by request then cancel', async () => {
  const a = await signedIn();
  await setLifecycle(a.uid, 'none'); // Stored none is NOT the absence of a doc.
  for (const [name, data] of [['getAccountDeletionStatus', {}],
    ['requestAccountDeletion', { requestId: rid() }], ['cancelAccountDeletion', {}]]) {
    await fails(a.call(name, data), 'failed-precondition', 'invalid-lifecycle');
  }
  await assert.rejects(setDoc(doc(a.db, 'users', a.uid), profile()), { code: 'permission-denied' });
});
