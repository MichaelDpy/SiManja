// B10: aturan murni kontrak permintaan penghapusan akun (tanpa emulator).
import assert from 'node:assert/strict';
import { test } from 'node:test';
import {
  DeletionError, FROZEN_STATES, RECENT_AUTH_MAX_AGE_SECONDS, States,
  assertRecentAuth, callerUid, planCancel, planRequest, toStatus, validateRequestId,
} from '../functions/src/deletion.js';

const now = Date.UTC(2026, 10, 27, 3, 0, 0);
const seconds = (ms) => Math.floor(ms / 1000);
const rejects = (fn, code, reason) => assert.throws(fn, (error) =>
  error instanceof DeletionError && error.code === code && error.reason === reason);

test('UID hanya dari token; tanpa token ditolak', () => {
  assert.equal(callerUid({ uid: 'A' }), 'A');
  rejects(() => callerUid(null), 'unauthenticated', 'unauthenticated');
  rejects(() => callerUid({ uid: '' }), 'unauthenticated', 'unauthenticated');
});

test('recent login: baru diterima, kedaluwarsa/hilang/masa depan ditolak', () => {
  assertRecentAuth(seconds(now) - 10, now);
  assertRecentAuth(seconds(now) - RECENT_AUTH_MAX_AGE_SECONDS, now);
  rejects(() => assertRecentAuth(seconds(now) - RECENT_AUTH_MAX_AGE_SECONDS - 1, now),
    'failed-precondition', 'requires-recent-login');
  rejects(() => assertRecentAuth(undefined, now), 'failed-precondition', 'requires-recent-login');
  rejects(() => assertRecentAuth(seconds(now) + 3600, now), 'failed-precondition', 'requires-recent-login');
});

test('requestId wajib dan berformat aman', () => {
  assert.equal(validateRequestId('req_12345678'), 'req_12345678');
  for (const bad of [undefined, '', 'short', 'a'.repeat(65), 'ada spasi 123', '../../etc']) {
    rejects(() => validateRequestId(bad), 'invalid-argument', 'invalid-request-id');
  }
});

test('permintaan pertama membuat requested', () => {
  const plan = planRequest(null, { requestId: 'req_00000001', nowMs: now });
  assert.equal(plan.write.state, States.requested);
  assert.equal(plan.write.requestId, 'req_00000001');
  assert.equal(plan.write.version, 1);
  assert.equal(plan.write.previousState, States.none);
});

test('permintaan ganda idempoten: tidak membuat proses kedua', () => {
  const first = planRequest(null, { requestId: 'req_00000001', nowMs: now }).doc;
  for (const state of [States.requested, States.processing, States.completed]) {
    const existing = { ...first, state };
    const again = planRequest(existing, { requestId: 'req_00000002', nowMs: now + 1000 });
    assert.equal(again.write, null, state);
    assert.equal(again.doc.requestId, 'req_00000001', state);
  }
});

test('setelah dibatalkan atau gagal, permintaan baru diterima dengan versi naik', () => {
  for (const state of [States.cancelled, States.failed]) {
    const plan = planRequest({ state, version: 3, requestId: 'old_0000001' },
      { requestId: 'req_00000009', nowMs: now });
    assert.equal(plan.write.state, States.requested);
    assert.equal(plan.write.version, 4);
    assert.equal(plan.write.previousState, state);
  }
});

test('batal hanya saat requested; sebelum ada permintaan tanpa perubahan', () => {
  assert.deepEqual(planCancel(null, { nowMs: now }), { write: null, doc: null });
  const requested = planRequest(null, { requestId: 'req_00000001', nowMs: now }).doc;
  const cancel = planCancel(requested, { nowMs: now + 5 });
  assert.equal(cancel.write.state, States.cancelled);
  assert.equal(cancel.write.version, 2);
  assert.equal(planCancel(cancel.doc, { nowMs: now + 6 }).write, null);
  for (const state of [States.processing, States.completed, States.failed]) {
    rejects(() => planCancel({ state }, { nowMs: now }), 'failed-precondition', 'deletion-not-cancellable');
  }
});

test('status client hanya memuat field publik', () => {
  assert.deepEqual(toStatus(null), { state: States.none });
  const status = toStatus({ ...planRequest(null, { requestId: 'req_00000001', nowMs: now }).doc, secret: 'x' });
  assert.deepEqual(Object.keys(status).sort(), ['requestId', 'requestedAtMs', 'state', 'updatedAtMs']);
});

test('status beku untuk write normal sesuai kontrak C09', () => {
  assert.deepEqual([...FROZEN_STATES].sort(), ['completed', 'failed', 'processing', 'requested']);
});

test('kegagalan parsial tetap beku; hanya none/cancelled yang membuka write', () => {
  assert.ok(FROZEN_STATES.includes(States.failed));
  assert.ok(!FROZEN_STATES.includes(States.cancelled));
  assert.ok(!FROZEN_STATES.includes(States.none));
  // Permintaan ulang setelah gagal tetap beku (requested), tidak lewat status terbuka.
  const retry = planRequest({ state: States.failed, version: 4, requestId: 'old_0000001' },
    { requestId: 'req_00000010', nowMs: now });
  assert.ok(FROZEN_STATES.includes(retry.write.state));
});

test('C09: retry setelah cleanup gagal tidak dapat dibatalkan untuk membuka write', () => {
  const failed = { state: States.failed, previousState: States.processing, version: 4 };
  const retry = planRequest(failed, { requestId: 'req_retry_0001', nowMs: now });
  rejects(() => planCancel(retry.doc, { nowMs: now + 1 }),
    'failed-precondition', 'deletion-not-cancellable');
  const duplicate = planRequest(retry.doc, { requestId: 'req_retry_0002', nowMs: now + 2 });
  rejects(() => planCancel(duplicate.doc, { nowMs: now + 3 }),
    'failed-precondition', 'deletion-not-cancellable');
});

test('C09: requested dengan asal transisi tak dikenal gagal tertutup saat cancel', () => {
  for (const previousState of [undefined, null, 'unknown', States.processing, States.completed, States.requested]) {
    rejects(() => planCancel({ state: States.requested, previousState }, { nowMs: now }),
      'failed-precondition', 'deletion-not-cancellable');
  }
});

test('C09: lifecycle malformed tidak dapat di-reset lewat callable menjadi akun terbuka', () => {
  for (const existing of [{}, { state: null }, { state: 'none' }, { state: 'future-state' }, { state: 1 }]) {
    rejects(() => planRequest(existing, { requestId: 'req_invalid_01', nowMs: now }),
      'failed-precondition', 'invalid-lifecycle');
    rejects(() => planCancel(existing, { nowMs: now }), 'failed-precondition', 'invalid-lifecycle');
    rejects(() => toStatus(existing), 'failed-precondition', 'invalid-lifecycle');
  }
});
