import assert from 'node:assert/strict';
import { test } from 'node:test';
import { runDateMigration, calendarTimestamp, timestamp, validateScope } from '../scripts/date-migration.mjs';
import { parseOptions, main } from '../scripts/migrate-transaction-dates.mjs';
import { migrationTarget } from '../scripts/date-migration-firestore.mjs';
import { mkdtemp, rm, readFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { basename, dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const scope = { projectId: 'demo-simanja', uid: 'A', from: '1900-01-01', until: '2201-01-01' };
const stamp = (seconds, nanoseconds = 0) => ({ seconds, nanoseconds });
const row = (id = 'legacy') => ({ id, updateTime: stamp(1769990000), data: {
  category: 'Gaji', description: 'Jangan masuk laporan: nama pribadi', amount: 9007199254740991,
  isIncome: true, date: stamp(1769792400, 123456000),
  createdAt: stamp(1769990000), updatedAt: stamp(1769990000),
} });
const manifest = (rows, date = '2026-01-31') => ({ formatVersion: 1, scope, decisions: rows.map((r) => ({
  id: r.id, expectedDate: r.data.date, expectedUpdateTime: r.updateTime,
  calendarDate: date, reviewRef: 'review:fixture-1',
})) });

function memory(rows, { failBatch = 0, hasMore = false } = {}) {
  return {
    writes: 0, commits: [],
    async scan({ limit }) { return { rows: structuredClone(rows.slice(0, limit)), hasMore }; },
    async commit(operations) {
      this.commits.push(operations);
      if (this.commits.length === failBatch) throw new Error('PRIVATE_SDK_ERROR');
      return operations.map((op) => {
        const item = rows.find((r) => r.id === op.id);
        assert.deepEqual(item.updateTime, op.expectedUpdateTime);
        this.writes++;
        item.data.date = op.after;
        item.data.dateVersion = 2;
        item.data.updatedAt = stamp(1770000000);
        item.updateTime = stamp(1770000000);
        return item.updateTime;
      });
    },
  };
}

test('dry-run membedakan kandidat/ambigu/v2/malformed dan tidak menulis', async () => {
  const candidate = row();
  const v2 = row('v2'); v2.data.dateVersion = 2; v2.data.date = calendarTimestamp('2024-02-29');
  const broken = row('broken'); broken.data.amount = 1.5;
  const adapter = memory([candidate, row('ambiguous'), v2, broken]);
  const journal = { async append() { assert.fail('dry-run tidak menulis journal'); } };
  const report = await runDateMigration({ adapter, scope, manifest: manifest([candidate]), journal });
  assert.equal(report.mode, 'dry-run');
  assert.deepEqual(report.counts, { candidate: 1, applied: 0, skipped: 1, ambiguous: 1, error: 1, not_attempted: 0, scanned: 4, planned: 1 });
  assert.equal(adapter.writes, 0);
  assert.equal(adapter.commits.length, 0);
  assert.ok(!JSON.stringify(report).includes(candidate.data.description));
  assert.ok(!JSON.stringify(report).includes('9007199254740991'));
  assert.ok(!Object.hasOwn(report.target, 'uid'));
});

test('tanpa keputusan, legacy midnight UTC tetap ambigu', async () => {
  const input = row(); input.data.date = calendarTimestamp('2026-01-31');
  const report = await runDateMigration({ adapter: memory([input]), scope });
  assert.equal(report.entries[0].reason, 'REVIEW_REQUIRED');
});

test('apply menyimpan before-image sebelum setiap batch dan rerun idempotent', async () => {
  const rows = [row('a'), row('b'), row('c')];
  const review = manifest(rows, '2024-02-29');
  const adapter = memory(rows);
  const events = [];
  const journal = { async append(event) { events.push(structuredClone(event)); } };
  const commit = adapter.commit.bind(adapter);
  adapter.commit = async (operations) => {
    assert.equal(events.at(-1).kind, 'prepared');
    assert.deepEqual(events.at(-1).operations, operations);
    return commit(operations);
  };
  const result = await runDateMigration({ adapter, scope, manifest: review, apply: true, journal, batchSize: 2 });
  assert.equal(result.counts.applied, 3);
  assert.deepEqual(adapter.commits.map((batch) => batch.length), [2, 1]);
  assert.deepEqual(events.map((event) => event.kind), ['prepared', 'committed', 'prepared', 'committed']);
  assert.equal(events[0].operations[0].before.date.nanoseconds, 123456000);
  const rerun = await runDateMigration({ adapter, scope, manifest: review, apply: true, journal });
  assert.equal(rerun.counts.skipped, 3);
  assert.equal(adapter.writes, 3);
});

test('partial failure mempertahankan batch sukses dan menghentikan sisa, lalu retry aman', async () => {
  const rows = [row('a'), row('b'), row('c')];
  const review = manifest(rows);
  const adapter = memory(rows, { failBatch: 2 });
  const journal = { async append() {} };
  const first = await runDateMigration({ adapter, scope, manifest: review, apply: true, journal, batchSize: 1 });
  assert.equal(first.counts.applied, 1);
  assert.equal(first.counts.error, 1);
  assert.equal(first.counts.not_attempted, 1);
  assert.equal(adapter.writes, 1);
  const retry = await runDateMigration({ adapter, scope, manifest: review, apply: true, journal, batchSize: 1 });
  assert.equal(retry.counts.skipped, 1);
  assert.equal(retry.counts.applied, 2);
  assert.equal(adapter.writes, 3);
});

test('kegagalan journal sebelum commit tidak menulis database', async () => {
  const input = row(); const adapter = memory([input]);
  const report = await runDateMigration({ adapter, scope, manifest: manifest([input]), apply: true,
    journal: { async append() { throw new Error('disk full'); } } });
  assert.equal(report.entries[0].reason, 'JOURNAL_NOT_DURABLE');
  assert.equal(adapter.writes, 0);
});

test('commit sukses tetapi receipt gagal ditulis dilaporkan unconfirmed, bukan sukses palsu', async () => {
  const input = row(); const adapter = memory([input]);
  const report = await runDateMigration({ adapter, scope, manifest: manifest([input]), apply: true,
    journal: { async append(event) { if (event.kind === 'committed') throw new Error('disk full'); } } });
  assert.equal(report.counts.applied, 0);
  assert.equal(report.entries[0].reason, 'COMMIT_OR_RECEIPT_UNCONFIRMED');
  assert.equal(adapter.writes, 1);
});

test('keputusan stale, scope salah, duplikat, invalid date/version tidak memutasi', async () => {
  const input = row(); const review = manifest([input]);
  review.decisions[0].expectedUpdateTime = stamp(1);
  const adapter = memory([input]);
  const report = await runDateMigration({ adapter, scope, manifest: review });
  assert.equal(report.entries[0].reason, 'STALE_DECISION');
  for (const invalid of [
    { ...manifest([input]), scope: { ...scope, uid: 'B' } },
    manifest([input, input]), manifest([input], '2026-02-30'),
    { ...manifest([input]), formatVersion: 2 },
  ]) await assert.rejects(runDateMigration({ adapter, scope, manifest: invalid }));
  for (const version of [1, 3, null, '2']) {
    const invalid = row(); invalid.data.dateVersion = version;
    const result = await runDateMigration({ adapter: memory([invalid]), scope });
    assert.equal(result.entries[0].reason, 'INVALID_DATE_VERSION');
  }
  assert.equal(adapter.writes, 0);
});

test('scan terbatas menyatakan incomplete dan cursor; range tidak memakai timezone host', async () => {
  const outside = row('a'); outside.data.date = calendarTimestamp('2025-12-31');
  const narrowed = { ...scope, from: '2026-01-01', until: '2026-02-01' };
  const report = await runDateMigration({ adapter: memory([outside, row('b')], { hasMore: true }), scope: narrowed, limit: 2 });
  assert.equal(report.scan.complete, false);
  assert.equal(report.scan.nextAfterId, 'b');
  assert.equal(report.counts.skipped, 1);
  assert.equal(report.counts.ambiguous, 1);
  assert.equal(calendarTimestamp('2024-02-29').seconds, 1709164800);
  assert.throws(() => calendarTimestamp('2023-02-29'));
  assert.throws(() => calendarTimestamp('2201-01-01'));
  assert.throws(() => timestamp({ seconds: 1, nanoseconds: 1e9 }));
  assert.throws(() => validateScope({ ...scope, from: scope.until }));
});

test('CLI menolak target/range/apply salah sebelum membuka SDK', () => {
  const args = ['--project', scope.projectId, '--uid', scope.uid, '--from', scope.from, '--until', scope.until, '--report', 'report.json'];
  const env = { FIRESTORE_EMULATOR_HOST: '127.0.0.1:8080' };
  assert.equal(parseOptions(args, env).apply, false);
  for (const extra of [['--apply'], ['--limit', '0'], ['--batch-size', '101'], ['--after-id', '../x'], ['--unknown']]) {
    assert.throws(() => parseOptions([...args, ...extra], env));
  }
  assert.throws(() => parseOptions(args, {}));
  assert.throws(() => migrationTarget('actual-project', '127.0.0.1:8080'));
  assert.throws(() => migrationTarget(scope.projectId, 'example.com:8080'));
  assert.equal(migrationTarget('actual-project', undefined, true), 'cloud');
  assert.equal(parseOptions(['--help'], {}).help, true);
});

test('CLI refuse report di Git dan tidak menimpa berkas output existing', async () => {
  const previous = process.env.FIRESTORE_EMULATOR_HOST;
  process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:8080';
  const dir = await mkdtemp(join(tmpdir(), 'simanja-date-unit-'));
  try {
    const args = ['--project', scope.projectId, '--uid', scope.uid, '--from', scope.from, '--until', scope.until, '--report'];
    await assert.rejects(main([...args, fileURLToPath(new URL('../package.json', import.meta.url))]), /OUTPUT_MUST_BE_OUTSIDE_REPOSITORY/);
    const { writeFile } = await import('node:fs/promises');
    const existing = join(dir, 'existing.json');
    await writeFile(existing, 'keep');
    await assert.rejects(main([...args, existing]), { code: 'EEXIST' });
    assert.equal(await readFile(existing, 'utf8'), 'keep');
  } finally {
    if (previous === undefined) delete process.env.FIRESTORE_EMULATOR_HOST;
    else process.env.FIRESTORE_EMULATOR_HOST = previous;
    assert.equal(dirname(dir), tmpdir());
    assert.ok(basename(dir).startsWith('simanja-date-unit-'));
    await rm(dir, { recursive: true });
  }
});
