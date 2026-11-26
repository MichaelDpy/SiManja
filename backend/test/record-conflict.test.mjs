import assert from 'node:assert/strict';
import { before, beforeEach, after, test } from 'node:test';
import { readFileSync } from 'node:fs';
import { initializeTestEnvironment } from '@firebase/rules-unit-testing';
import { doc, setDoc, updateDoc, deleteDoc, deleteField, getDocFromServer,
  serverTimestamp, runTransaction, disableNetwork, enableNetwork } from 'firebase/firestore';
import { emulatorAddress, projectId, profile, transaction } from './support/emulator.mjs';

let env;
before(async () => {
  const { host, port } = emulatorAddress('FIRESTORE_EMULATOR_HOST');
  env = await initializeTestEnvironment({ projectId,
    firestore: { host, port, rules: readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8') } });
});
beforeEach(() => env.clearFirestore());
after(async () => { await env?.cleanup(); });
const db = (uid = 'A') => env.authenticatedContext(uid).firestore();
const location = 'users/A/transactions/stable';
const denied = (promise) => assert.rejects(promise, { code: 'permission-denied' });
const sameStamp = (a, b) => a?.isEqual(b) ?? false;
const versionMatches = (a, b) => (a.revision ?? 0) === (b.revision ?? 0)
  && sameStamp(a.createdAt, b.createdAt) && sameStamp(a.updatedAt, b.updatedAt);

// Exercise the R-VERSION client protocol against real SDK retries and rules.
// The same policy is used by the Dart RecordConcurrency helper and tested there.
async function edit(client, path, base, patch, { remove = false } = {}) {
  const ref = doc(client, path);
  await runTransaction(client, async (operation) => {
    const current = await operation.get(ref);
    if (!current.exists()) {
      if (remove) return;
      throw new Error('record-deleted');
    }
    if (!versionMatches(base, current.data())) throw new Error('record-changed');
    if (remove) operation.delete(ref);
    else operation.update(ref, { ...patch, revision: (current.data().revision ?? 0) + 1, updatedAt: serverTimestamp() });
  }, { maxAttempts: 1 });
}

test('dua editor field sama atau berbeda: update stale tidak menimpa versi terbaru', async () => {
  const a = db(); const b = db(); const ref = doc(a, location);
  await setDoc(ref, { ...transaction(), revision: 1 });
  const base = (await getDocFromServer(ref)).data();
  await edit(b, location, base, { amount: 200000 });
  await assert.rejects(edit(a, location, base, { amount: 300000 }), /record-changed/);
  await assert.rejects(edit(a, location, base, { description: 'Draft A' }), /record-changed/);
  await denied(updateDoc(ref, { amount: 300000, revision: 2, updatedAt: serverTimestamp() }));
  const current = (await getDocFromServer(ref)).data();
  assert.equal(current.amount, 200000);
  assert.equal(current.revision, 2);
  assert.ok(current.createdAt.isEqual(base.createdAt));
});

test('edit-vs-delete, delete-vs-edit dan delete ulang tidak membangkitkan dokumen', async () => {
  const a = db(); const b = db(); const ref = doc(a, location);
  await setDoc(ref, { ...transaction(), revision: 1 });
  const base = (await getDocFromServer(ref)).data();
  await edit(b, location, base, { amount: 20 });
  await assert.rejects(edit(a, location, base, {}, { remove: true }), /record-changed/);
  const latest = (await getDocFromServer(ref)).data();
  await edit(b, location, latest, {}, { remove: true });
  await assert.rejects(edit(a, location, latest, { description: 'Lama' }), /record-deleted/);
  await edit(a, location, latest, {}, { remove: true });
  assert.equal((await getDocFromServer(ref)).exists(), false);
});

test('ID yang dibuat ulang mempunyai incarnation berbeda dan menolak editor lama', async () => {
  const client = db(); const ref = doc(client, location);
  await setDoc(ref, { ...transaction(), revision: 1 });
  const base = (await getDocFromServer(ref)).data();
  await edit(client, location, base, {}, { remove: true });
  await setDoc(ref, { ...transaction(), revision: 1 });
  assert.ok(!(await getDocFromServer(ref)).data().createdAt.isEqual(base.createdAt));
  await assert.rejects(edit(client, location, base, { amount: 999 }), /record-changed/);
  await assert.rejects(edit(client, location, base, {}, { remove: true }), /record-changed/);
});

test('reconnect tidak mengubah retry stale menjadi last-write-wins', async () => {
  const a = db(); const b = db(); const ref = doc(a, location);
  await setDoc(ref, { ...transaction(), revision: 1 });
  const base = (await getDocFromServer(ref)).data();
  await disableNetwork(a);
  // SDK stream disable is not an OS-level partition of unary transaction RPCs.
  // Test the reconnect/stale-base sequence without claiming offline write proof.
  try { await edit(b, location, base, { amount: 200000 }); }
  finally { await enableNetwork(a); }
  await assert.rejects(edit(a, location, base, { amount: 999 }), /record-changed/);
  assert.equal((await getDocFromServer(ref)).data().amount, 200000);
});

test('revision legacy/read compatibility dan counter invalid/downgrade ditolak rules', async () => {
  const client = db(); const ref = doc(client, location);
  await setDoc(ref, transaction());
  const legacy = (await getDocFromServer(ref)).data();
  await denied(updateDoc(ref, { amount: 20, updatedAt: serverTimestamp() }));
  await edit(client, location, legacy, { amount: 20 });
  assert.equal((await getDocFromServer(ref)).data().revision, 1);
  for (const revision of [deleteField(), null, 0, -1, 1, 3, 1.5, '2', 9007199254740992]) {
    await denied(updateDoc(ref, { revision, updatedAt: serverTimestamp() }));
  }
  await denied(updateDoc(doc(db('B'), location), { amount: 2, revision: 2, updatedAt: serverTimestamp() }));
});

async function editProfile(client, base, desired) {
  const ref = doc(client, 'users/A');
  await runTransaction(client, async (operation) => {
    const snapshot = await operation.get(ref);
    if (!snapshot.exists()) throw new Error('record-deleted');
    const current = snapshot.data();
    if (!sameStamp(base.createdAt, current.createdAt)) throw new Error('record-changed');
    const patch = {};
    for (const [field, value] of Object.entries(desired)) {
      if (base[field] === value) continue;
      if (current[field] !== base[field] && current[field] !== value) throw new Error('record-changed');
      if (current[field] !== value) patch[field] = value;
    }
    if (Object.keys(patch).length) operation.update(ref, { ...patch,
      revision: (current.revision ?? 0) + 1, updatedAt: serverTimestamp() });
  });
}

test('profil menggabungkan field berbeda, menolak field sama, retry desired tidak menulis lagi', async () => {
  const a = db(); const b = db(); const ref = doc(a, 'users/A');
  await setDoc(ref, { ...profile(), revision: 1 });
  const base = (await getDocFromServer(ref)).data();
  await editProfile(b, base, { ...base, city: 'Jakarta' });
  await editProfile(a, base, { ...base, name: 'Nama A' });
  const result = (await getDocFromServer(ref)).data();
  assert.equal(result.city, 'Jakarta'); assert.equal(result.name, 'Nama A');
  assert.equal(result.revision, 3);
  await assert.rejects(editProfile(b, base, { ...base, name: 'Nama B' }), /record-changed/);
  await editProfile(a, base, { ...base, name: 'Nama A' });
  assert.equal((await getDocFromServer(ref)).data().revision, 3);
  await denied(updateDoc(ref, { city: 'Bandung', revision: 3, updatedAt: serverTimestamp() }));
});
