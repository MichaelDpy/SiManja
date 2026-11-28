import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { before, beforeEach, after, test } from 'node:test';
import { initializeTestEnvironment } from '@firebase/rules-unit-testing';
import {
  doc, collection, setDoc, updateDoc, deleteDoc, getDocFromServer,
  getDocsFromServer, serverTimestamp, increment, writeBatch,
} from 'firebase/firestore';
import { emulatorAddress, projectId, profile, transaction } from './support/emulator.mjs';
import { FROZEN_STATES } from '../functions/src/deletion.js';

let env;
before(async () => {
  const { host, port } = emulatorAddress('FIRESTORE_EMULATOR_HOST');
  env = await initializeTestEnvironment({ projectId,
    firestore: { host, port, rules: readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8') } });
});
beforeEach(() => env.clearFirestore());
after(() => env?.cleanup());
const db = (uid = 'A') => env.authenticatedContext(uid).firestore();
const denied = (request) => assert.rejects(request, { code: 'permission-denied' });
const change = (ref, patch) => updateDoc(ref, { ...patch, revision: increment(1), updatedAt: serverTimestamp() });

async function seed(lifecycle) {
  await env.withSecurityRulesDisabled(async (context) => {
    const admin = context.firestore();
    await setDoc(doc(admin, 'users/A'), { ...profile(), revision: 1 });
    await setDoc(doc(admin, 'users/A/transactions/old'), { ...transaction(), revision: 1 });
    if (lifecycle !== undefined) await setDoc(doc(admin, 'accountLifecycle/A'), lifecycle);
  });
}

async function assertFrozen() {
  const own = db();
  const user = doc(own, 'users/A');
  const old = doc(own, 'users/A/transactions/old');
  await denied(change(user, { name: 'Blocked profile' }));
  await denied(setDoc(doc(own, 'users/A/transactions/new'), transaction()));
  await denied(change(old, { amount: 2 }));
  await denied(deleteDoc(old));
  await denied(deleteDoc(doc(own, 'users/A/transactions/missing')));
  await denied(deleteDoc(user));
  // Freeze is a write policy, not permission to inspect another user's data.
  assert.equal((await getDocFromServer(user)).exists(), true);
  assert.equal((await getDocsFromServer(collection(own, 'users/A/transactions'))).size, 1);
  await denied(getDocFromServer(doc(db('B'), 'users/A')));
  await denied(getDocFromServer(doc(own, 'accountLifecycle/A')));
  // A tombstone protects documents even AFTER the Admin worker deletes them.
  await env.withSecurityRulesDisabled(async (context) => {
    await deleteDoc(doc(context.firestore(), 'users/A'));
    await deleteDoc(doc(context.firestore(), 'users/A/transactions/old'));
  });
  await denied(setDoc(user, profile()));
  await denied(setDoc(old, transaction()));
}

for (const state of FROZEN_STATES) {
  test(`C09: ${state} freezes profile and transaction writes, including recreation`, async () => {
    await seed({ state, version: 1 });
    await assertFrozen();
  });
}

for (const [label, lifecycle] of [
  ['unknown', { state: 'future-state' }], ['missing', {}], ['null', { state: null }],
  ['wrong type', { state: 1 }], ['explicit none', { state: 'none' }],
]) {
  test(`C09: malformed/unsupported lifecycle ${label} fails closed`, async () => {
    await seed(lifecycle);
    await assertFrozen();
  });
}

for (const lifecycle of [undefined, { state: 'cancelled', previousState: 'requested', version: 2 }]) {
  test(`C09: ${lifecycle ? 'cancelled' : 'absent lifecycle'} permits the existing versioned CRUD protocol`, async () => {
    await seed(lifecycle);
    const own = db();
    await change(doc(own, 'users/A'), { name: 'Active' });
    const ref = doc(own, 'users/A/transactions/new');
    await setDoc(ref, transaction());
    await change(ref, { amount: 2 });
    await deleteDoc(ref);
    await denied(deleteDoc(doc(own, 'users/A')));
    await denied(getDocsFromServer(collection(own, 'users')));
  });
}

test('C09: lifecycle cannot be forged, unfreezed, read or deleted by client claims/batches', async () => {
  await seed({ state: 'requested', version: 1 });
  for (const client of [db(), db('B'), env.unauthenticatedContext().firestore(),
    env.authenticatedContext('A', { admin: true, role: 'admin' }).firestore()]) {
    const ref = doc(client, 'accountLifecycle/A');
    await denied(getDocFromServer(ref));
    await denied(getDocsFromServer(collection(client, 'accountLifecycle')));
    await denied(setDoc(doc(client, 'accountLifecycle/new'), { state: 'cancelled' }));
    await denied(updateDoc(ref, { state: 'cancelled' }));
    await denied(deleteDoc(ref));
    const batch = writeBatch(client);
    batch.delete(ref);
    batch.update(doc(client, 'users/A'), { name: 'Escape', revision: 2, updatedAt: serverTimestamp() });
    await denied(batch.commit());
  }
  assert.equal((await getDocFromServer(doc(db(), 'users/A'))).data().name, 'Pengguna A');
});

test('C09: freeze is scoped to the owning UID; denied same-owner batch is atomic', async () => {
  await seed({ state: 'failed' });
  await setDoc(doc(db('B'), 'users/B'), profile());
  await setDoc(doc(db('B'), 'users/B/transactions/own'), transaction());
  const own = db(); const batch = writeBatch(own);
  batch.update(doc(own, 'users/A'), { name: 'Batch', revision: 2, updatedAt: serverTimestamp() });
  batch.set(doc(own, 'users/A/transactions/batch'), transaction());
  await denied(batch.commit());
  assert.equal((await getDocFromServer(doc(db(), 'users/A/transactions/batch'))).exists(), false);
  assert.equal((await getDocFromServer(doc(db(), 'users/A'))).data().name, 'Pengguna A');
});

test('C09: permitted same-UID batch stays within rule lookup limits', async () => {
  await seed({ state: 'cancelled' });
  const own = db(); const batch = writeBatch(own);
  for (let i = 0; i < 25; i++) batch.set(doc(own, `users/A/transactions/batch-${i}`), transaction());
  await batch.commit();
  assert.equal((await getDocsFromServer(collection(own, 'users/A/transactions'))).size, 26);
});

test('C09: lifecycle/privilege fields cannot be mass assigned through profile or transaction', async () => {
  await seed();
  for (const patch of [{ role: 'admin' }, { admin: true }, { state: 'cancelled' },
    { accountLifecycle: { state: 'cancelled' } }, { uid: 'B' }]) {
    await denied(change(doc(db(), 'users/A'), patch));
    await denied(change(doc(db(), 'users/A/transactions/old'), patch));
  }
});
