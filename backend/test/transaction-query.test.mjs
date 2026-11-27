import assert from 'node:assert/strict';
import { before, beforeEach, after, test } from 'node:test';
import { readFileSync } from 'node:fs';
import { initializeTestEnvironment } from '@firebase/rules-unit-testing';
import {
  doc, collection, setDoc, deleteDoc, getDocsFromServer, onSnapshot, Timestamp,
} from 'firebase/firestore';
import { emulatorAddress, projectId } from './support/emulator.mjs';
import { historyQuery, pageOf } from './support/transaction-query.mjs';

let env;
before(async () => {
  const { host, port } = emulatorAddress('FIRESTORE_EMULATOR_HOST');
  env = await initializeTestEnvironment({ projectId,
    firestore: { host, port, rules: readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8') } });
});
beforeEach(() => env.clearFirestore());
after(() => env?.cleanup());
const db = (uid = 'A') => env.authenticatedContext(uid).firestore();
const fixture = (day = '2026-11-27', legacy = false) => ({
  category: 'Gaji', description: 'Synthetic query fixture', amount: 100,
  isIncome: true, date: Timestamp.fromDate(new Date(`${day}T00:00:00Z`)),
  ...(legacy ? {} : { dateVersion: 2 }), revision: 1,
  createdAt: new Timestamp(1, 0), updatedAt: new Timestamp(1, 0),
});
const seed = (rows) => env.withSecurityRulesDisabled(async (context) => {
  const client = context.firestore();
  await Promise.all(rows.map(([id, data]) => setDoc(doc(client, `users/A/transactions/${id}`), data)));
});
const ids = (rows) => rows.map((row) => row.id);

test('ties use date plus document ID, every static row appears exactly once', async () => {
  const names = ['a', 'aa', 'b', 'c', 'd', 'e', 'f', 'g', 'z', '\ue000', '😀'];
  await seed(names.map((name) => [name, fixture()]));
  const client = db(); const collected = []; let afterCursor;
  do {
    const snapshot = await getDocsFromServer(historyQuery(client, 'A', { pageSize: 3 }, afterCursor));
    assert.ok(snapshot.size <= 4);
    const page = pageOf(snapshot, 3);
    collected.push(...ids(page.rows));
    afterCursor = page.after;
  } while (afterCursor);
  const expected = names.sort((a, b) => Buffer.compare(Buffer.from(b), Buffer.from(a)));
  assert.deepEqual(collected, expected);
  assert.equal(new Set(collected).size, names.length);
});

test('calendar range includes start, excludes end, leap/year boundaries and legacy', async () => {
  await seed([
    ['before', fixture('2024-02-28')], ['leap', fixture('2024-02-29')],
    ['end', fixture('2024-03-01')], ['legacy', fixture('2024-02-29', true)],
    ['year-before', fixture('2025-12-31')], ['year', fixture('2026-01-01')],
  ]);
  const client = db();
  const leap = await getDocsFromServer(historyQuery(client, 'A', { from: '2024-02-29', until: '2024-03-01' }));
  assert.deepEqual(ids(leap.docs), ['leap']);
  const year = await getDocsFromServer(historyQuery(client, 'A', { from: '2026-01-01', until: '2026-02-01' }));
  assert.deepEqual(ids(year.docs), ['year']);
  for (const bounds of [{ from: '2030-01-01' }, { from: '2026-01-01', until: '2026-01-01' }]) {
    assert.equal((await getDocsFromServer(historyQuery(client, 'A', bounds))).size, 0);
  }
});

test('deleting boundary and unseen row does not break the value cursor', async () => {
  await seed(['a', 'b', 'c', 'd', 'e'].map((name) => [name, fixture()]));
  const client = db();
  const first = pageOf(await getDocsFromServer(historyQuery(client, 'A', { pageSize: 2 })), 2);
  assert.deepEqual(ids(first.rows), ['e', 'd']);
  await deleteDoc(doc(client, 'users/A/transactions/d'));
  await deleteDoc(doc(client, 'users/A/transactions/b'));
  const second = pageOf(await getDocsFromServer(historyQuery(client, 'A', { pageSize: 2 }, first.after)), 2);
  assert.deepEqual(ids(second.rows), ['c', 'a']);
  assert.equal(second.after, null);
});

test('inserts before cursor need refresh; inserts after cursor join remaining pages', async () => {
  await seed(['a', 'c', 'e'].map((name) => [name, fixture()]));
  const client = db();
  const first = pageOf(await getDocsFromServer(historyQuery(client, 'A', { pageSize: 1 })), 1);
  await seed([['z', fixture()], ['d', fixture()]]);
  const next = await getDocsFromServer(historyQuery(client, 'A', { pageSize: 100 }, first.after));
  assert.deepEqual(ids(next.docs), ['d', 'c', 'a']);
  const refresh = await getDocsFromServer(historyQuery(client, 'A', { pageSize: 1 }));
  assert.equal(refresh.docs[0].id, 'z');
});

test('moving a date across the boundary requires refresh, not snapshot claims', async () => {
  await seed([['a', fixture('2026-11-25')], ['b', fixture('2026-11-26')], ['c', fixture('2026-11-27')]]);
  const client = db();
  const first = pageOf(await getDocsFromServer(historyQuery(client, 'A', { pageSize: 1 })), 1);
  // Admin fixture edit represents another writer, not a bypass used by the app.
  await seed([['a', fixture('2026-11-28')], ['c', fixture('2026-11-24')]]);
  const next = await getDocsFromServer(historyQuery(client, 'A', { pageSize: 100 }, first.after));
  assert.deepEqual(ids(next.docs), ['b', 'c']); // repeated c; moved a is before cursor
  const refresh = await getDocsFromServer(historyQuery(client, 'A', { pageSize: 100 }));
  assert.deepEqual(ids(refresh.docs), ['a', 'b', 'c']);
});

test('owner query allowed, foreign owner and unauthenticated queries denied', async () => {
  await seed([['private', fixture()]]);
  assert.equal((await getDocsFromServer(historyQuery(db(), 'A'))).size, 1);
  await assert.rejects(getDocsFromServer(historyQuery(db('B'), 'A')), { code: 'permission-denied' });
  await assert.rejects(getDocsFromServer(historyQuery(env.unauthenticatedContext().firestore(), 'A')),
    { code: 'permission-denied' });
  assert.equal((await getDocsFromServer(historyQuery(db('B'), 'B'))).size, 0);
});

test('existing collection listener still includes legacy and all canonical rows', async () => {
  await seed([['old', fixture('2026-11-27', true)], ['new', fixture()]]);
  const snapshot = await new Promise((resolve, reject) => {
    const stop = onSnapshot(collection(db(), 'users/A/transactions'), { includeMetadataChanges: true },
      (value) => { if (!value.metadata.fromCache) { stop(); resolve(value); } }, reject);
  });
  assert.deepEqual(ids(snapshot.docs).sort(), ['new', 'old']);
  assert.equal((await getDocsFromServer(historyQuery(db(), 'A'))).size, 1);
});

test('local index declaration covers the production filter and sort contract', () => {
  const config = JSON.parse(readFileSync(new URL('../firestore.indexes.json', import.meta.url), 'utf8'));
  assert.ok(config.indexes.some((index) => index.collectionGroup === 'transactions'
    && index.queryScope === 'COLLECTION'
    && JSON.stringify(index.fields) === JSON.stringify([
      { fieldPath: 'dateVersion', order: 'ASCENDING' },
      { fieldPath: 'date', order: 'DESCENDING' },
      { fieldPath: '__name__', order: 'DESCENDING' },
    ])));
});
