import assert from 'node:assert/strict';
import { emulatorAddress, projectId } from './emulator.mjs';

// Admin fixture transport, ONLY for the owned local demo emulator. No cloud API.
export function firestoreDocumentsUrl() {
  assert.ok(projectId.startsWith('demo-'));
  return `${emulatorAddress('FIRESTORE_EMULATOR_HOST').origin}/v1/projects/${projectId}/databases/(default)/documents`;
}

export async function setLifecycle(uid, state, previousState = 'none') {
  const now = Date.now();
  const response = await fetch(`${firestoreDocumentsUrl()}/accountLifecycle/${encodeURIComponent(uid)}`, {
    method: 'PATCH',
    headers: { Authorization: 'Bearer owner', 'Content-Type': 'application/json' },
    body: JSON.stringify({ fields: {
      state: { stringValue: state }, previousState: { stringValue: previousState },
      requestId: { stringValue: 'req_fixture_0001' }, version: { integerValue: '2' },
      requestedAtMs: { integerValue: String(now) }, updatedAtMs: { integerValue: String(now) },
    } }),
    signal: AbortSignal.timeout(5000),
  });
  assert.equal(response.status, 200, 'Admin lifecycle fixture must be written to the local emulator.');
}

export async function removeFixtureDocument(path) {
  const response = await fetch(`${firestoreDocumentsUrl()}/${path}`, {
    method: 'DELETE', headers: { Authorization: 'Bearer owner' },
    signal: AbortSignal.timeout(5000),
  });
  assert.ok([200, 404].includes(response.status));
}
