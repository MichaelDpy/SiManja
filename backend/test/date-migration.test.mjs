import assert from 'node:assert/strict';
import { before, beforeEach, after, test } from 'node:test';
import { createRequire } from 'node:module';
import { readFile, writeFile, mkdtemp, rm } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { basename, dirname, join } from 'node:path';
import { tmpdir } from 'node:os';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { emulatorAddress, projectId } from './support/emulator.mjs';
import { createFirestoreAdapter } from '../scripts/date-migration-firestore.mjs';
import { runDateMigration, timestamp } from '../scripts/date-migration.mjs';

const require = createRequire(new URL('../functions/package.json', import.meta.url));
const { initializeApp, deleteApp } = require('firebase-admin/app');
const { getFirestore, Timestamp } = require('firebase-admin/firestore');
const fixture = JSON.parse(await readFile(new URL('./fixtures/date-migration.json', import.meta.url), 'utf8'));
const scope = { projectId, uid: 'migration-fixture-A', from: '1900-01-01', until: '2201-01-01' };
const otherUid = 'migration-fixture-B';
const cli = fileURLToPath(new URL('../scripts/migrate-transaction-dates.mjs', import.meta.url));
const exec = promisify(execFile);
let app;
let db;

before(() => {
  emulatorAddress('FIRESTORE_EMULATOR_HOST');
  assert.ok(projectId.startsWith('demo-'));
  app = initializeApp({ projectId }, 'date-migration-tests');
  db = getFirestore(app);
});
beforeEach(async () => {
  for (const uid of [scope.uid, otherUid]) {
    const docs = await db.collection(`users/${uid}/transactions`).get();
    const batch = db.batch();
    for (const doc of docs.docs) batch.delete(doc.ref);
    await batch.commit();
  }
});
after(async () => { await db?.terminate(); if (app) await deleteApp(app); });

const ref = (id, uid = scope.uid) => db.doc(`users/${uid}/transactions/${id}`);
const legacy = () => ({
  category: 'Gaji', description: 'Fixture privat', amount: 9007199254740991,
  isIncome: true, date: new Timestamp(fixture.legacyDate.seconds, fixture.legacyDate.nanoseconds),
  createdAt: Timestamp.fromMillis(1769900000000), updatedAt: Timestamp.fromMillis(1769990000000),
});
async function review(ids) {
  const decisions = [];
  for (const id of ids) {
    const snapshot = await ref(id).get();
    decisions.push({ id, expectedDate: timestamp(snapshot.data().date), expectedUpdateTime: timestamp(snapshot.updateTime),
      calendarDate: fixture.calendarDate, reviewRef: 'review:fixture-1' });
  }
  return { formatVersion: 1, scope, decisions };
}
const journal = () => ({ events: [], async append(event) { this.events.push(structuredClone(event)); } });

test('audit emulator tidak menulis legacy, baru, malformed, ambigu atau UID lain', async () => {
  for (const [id, data] of [
    ['candidate', legacy()], ['ambiguous', legacy()],
    ['v2', { ...legacy(), dateVersion: 2, date: new Timestamp(fixture.migratedDate.seconds, 0) }],
    ['broken', { ...legacy(), date: 'invalid' }],
  ]) await ref(id).set(data);
  await ref('other', otherUid).set(legacy());
  const before = (await ref('candidate').get()).updateTime;
  const adapter = createFirestoreAdapter(scope);
  try {
    const report = await runDateMigration({ adapter, scope, manifest: await review(['candidate']) });
    assert.equal(report.counts.candidate, 1);
    assert.equal(report.counts.ambiguous, 1);
    assert.equal(report.counts.skipped, 1);
    assert.equal(report.counts.error, 1);
    assert.ok((await ref('candidate').get()).updateTime.isEqual(before));
    assert.ok(!report.entries.some((item) => item.id === 'other'));
    assert.ok(!Object.hasOwn((await ref('other', otherUid).get()).data(), 'dateVersion'));
  } finally { await adapter.close(); }
});

test('apply atomik per batch mempertahankan field/createdAt dan idempotent pada run kedua', async () => {
  for (const id of ['a', 'b', 'c']) await ref(id).set(legacy());
  const manifest = await review(['a', 'b', 'c']);
  const adapter = createFirestoreAdapter(scope);
  const audit = journal();
  try {
    const first = await runDateMigration({ adapter, scope, manifest, apply: true, batchSize: 2, journal: audit });
    assert.equal(first.counts.applied, 3);
    assert.deepEqual(audit.events.filter((e) => e.kind === 'prepared').map((e) => e.operations.length), [2, 1]);
    const migrated = (await ref('a').get()).data();
    assert.equal(migrated.dateVersion, 2);
    assert.deepEqual(timestamp(migrated.date), fixture.migratedDate);
    for (const key of ['category', 'description', 'amount', 'isIncome']) assert.equal(migrated[key], legacy()[key]);
    assert.ok(migrated.createdAt.isEqual(legacy().createdAt));
    assert.ok(migrated.updatedAt.toMillis() > legacy().updatedAt.toMillis());
    const beforeRetry = (await ref('a').get()).updateTime;
    const retry = await runDateMigration({ adapter, scope, manifest, apply: true, journal: audit });
    assert.equal(retry.counts.skipped, 3);
    assert.equal(retry.counts.applied, 0);
    assert.ok((await ref('a').get()).updateTime.isEqual(beforeRetry));
  } finally { await adapter.close(); }
});

test('precondition SDK menolak batch stale tanpa menimpa perubahan yang datang setelah scan', async () => {
  for (const id of ['a', 'b', 'c']) await ref(id).set(legacy());
  const manifest = await review(['a', 'b', 'c']);
  const adapter = createFirestoreAdapter(scope);
  const commit = adapter.commit;
  let batches = 0;
  adapter.commit = async (operations) => {
    batches++;
    if (batches === 2) await ref('b').update({ amount: 888 });
    return commit(operations);
  };
  try {
    const result = await runDateMigration({ adapter, scope, manifest, apply: true, batchSize: 1, journal: journal() });
    assert.equal(result.counts.applied, 1);
    assert.equal(result.counts.error, 1);
    assert.equal(result.counts.not_attempted, 1);
    assert.equal((await ref('b').get()).data().amount, 888);
    assert.ok(!Object.hasOwn((await ref('b').get()).data(), 'dateVersion'));
    assert.ok(!Object.hasOwn((await ref('c').get()).data(), 'dateVersion'));
  } finally { await adapter.close(); }
});

test('scan limit/cursor nyata tidak menghilangkan record pada batch berikutnya', async () => {
  for (const id of ['a', 'b', 'c']) await ref(id).set(legacy());
  const adapter = createFirestoreAdapter(scope);
  try {
    await assert.rejects(runDateMigration({ adapter, scope: { ...scope, uid: otherUid } }), /ADAPTER_SCOPE_MISMATCH/);
    const first = await runDateMigration({ adapter, scope, limit: 2 });
    assert.equal(first.scan.complete, false);
    assert.equal(first.scan.nextAfterId, 'b');
    const next = await runDateMigration({ adapter, scope, limit: 2, afterId: first.scan.nextAfterId });
    assert.deepEqual(next.entries.map((item) => item.id), ['c']);
    assert.equal(next.scan.complete, true);
  } finally { await adapter.close(); }
});

test('satu precondition gagal membatalkan seluruh multi-record batch', async () => {
  for (const id of ['a', 'b', 'c']) await ref(id).set(legacy());
  const manifest = await review(['a', 'b', 'c']);
  const adapter = createFirestoreAdapter(scope);
  const commit = adapter.commit;
  adapter.commit = async (operations) => {
    await ref('b').update({ description: 'Perubahan setelah scan' });
    return commit(operations);
  };
  try {
    const result = await runDateMigration({ adapter, scope, manifest, apply: true, batchSize: 2, journal: journal() });
    assert.equal(result.counts.applied, 0);
    assert.equal(result.counts.error, 2);
    assert.equal(result.counts.not_attempted, 1);
    for (const id of ['a', 'b', 'c']) assert.ok(!Object.hasOwn((await ref(id).get()).data(), 'dateVersion'));
    assert.equal((await ref('b').get()).data().description, 'Perubahan setelah scan');
  } finally { await adapter.close(); }
});

test('CLI end-to-end dry-run default lalu apply dengan report dan journal privat', async () => {
  await ref('cli').set(legacy());
  const dir = await mkdtemp(join(tmpdir(), 'simanja-date-cli-'));
  try {
    const args = [cli, '--project', projectId, '--uid', scope.uid, '--from', scope.from, '--until', scope.until];
    const dryReport = join(dir, 'dry.json');
    const before = (await ref('cli').get()).updateTime;
    await exec(process.execPath, [...args, '--report', dryReport]);
    const dry = JSON.parse(await readFile(dryReport, 'utf8'));
    assert.equal(dry.mode, 'dry-run');
    assert.equal(dry.counts.ambiguous, 1);
    assert.ok((await ref('cli').get()).updateTime.isEqual(before));
    const decisions = join(dir, 'decisions.json');
    const journalPath = join(dir, 'journal.jsonl');
    await writeFile(decisions, JSON.stringify(await review(['cli'])));
    await exec(process.execPath, [...args, '--report', join(dir, 'applied.json'), '--apply', '--confirm-project', projectId, '--decisions', decisions, '--journal', journalPath]);
    const receipts = (await readFile(journalPath, 'utf8')).trim().split('\n').map((line) => JSON.parse(line));
    assert.deepEqual(receipts.map((entry) => entry.kind), ['prepared', 'committed']);
    assert.deepEqual(receipts[0].operations[0].before.date, fixture.legacyDate);
    assert.ok(receipts[1].records[0].updateTime.seconds > 0);
    assert.equal((await ref('cli').get()).data().dateVersion, 2);
    const result = JSON.parse(await readFile(join(dir, 'applied.json'), 'utf8'));
    assert.equal(result.counts.applied, 1);
    assert.ok(!JSON.stringify(result).includes('Fixture privat'));
  } finally {
    assert.equal(dirname(dir), tmpdir());
    assert.ok(basename(dir).startsWith('simanja-date-cli-'));
    await rm(dir, { recursive: true });
  }
});
