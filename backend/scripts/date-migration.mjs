import { createHash } from 'node:crypto';

const MIN_DATE = Date.parse('1900-01-01T00:00:00Z') / 1000;
const MAX_DATE = Date.parse('2201-01-01T00:00:00Z') / 1000;
const FIELDS = ['category', 'description', 'amount', 'isIncome', 'date', 'dateVersion', 'createdAt', 'updatedAt'];

export function validId(value) {
  return typeof value === 'string' && value.trim().length > 0
    && !['.', '..'].includes(value) && !value.includes('/')
    && Buffer.byteLength(value) <= 1500;
}

export function timestamp(value) {
  if (!Number.isSafeInteger(value?.seconds) || !Number.isInteger(value?.nanoseconds)
    || value.nanoseconds < 0 || value.nanoseconds >= 1e9
    || value.seconds < -62135596800 || value.seconds > 253402300799) {
    throw new Error('INVALID_TIMESTAMP');
  }
  return { seconds: value.seconds, nanoseconds: value.nanoseconds };
}

export function sameTimestamp(a, b) {
  return a?.seconds === b?.seconds && a?.nanoseconds === b?.nanoseconds;
}

export function calendarTimestamp(value, { upperBound = false } = {}) {
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value)) throw new Error('INVALID_CALENDAR_DATE');
  const millis = Date.parse(`${value}T00:00:00Z`);
  if (!Number.isFinite(millis) || new Date(millis).toISOString().slice(0, 10) !== value
    || millis / 1000 < MIN_DATE || millis / 1000 > MAX_DATE
    || (!upperBound && millis / 1000 === MAX_DATE)) throw new Error('INVALID_CALENDAR_DATE');
  return { seconds: millis / 1000, nanoseconds: 0 };
}

export function validateScope(scope) {
  if (!/^[a-z][a-z0-9-]{4,62}$/.test(scope.projectId ?? '') || !validId(scope.uid)) throw new Error('INVALID_TARGET');
  const from = calendarTimestamp(scope.from);
  const until = calendarTimestamp(scope.until, { upperBound: true });
  if (from.seconds >= until.seconds) throw new Error('INVALID_RANGE');
  return { projectId: scope.projectId, uid: scope.uid, from: scope.from, until: scope.until };
}

export function decisionsFor(scope, manifest) {
  if (manifest == null) return new Map();
  if (manifest.formatVersion !== 1 || !Array.isArray(manifest.decisions)
    || Object.keys(scope).some((key) => manifest.scope?.[key] !== scope[key])) throw new Error('DECISION_SCOPE_MISMATCH');
  const decisions = new Map();
  for (const item of manifest.decisions) {
    if (!validId(item.id) || decisions.has(item.id)
      || !/^[A-Za-z0-9_.:-]{1,120}$/.test(item.reviewRef ?? '')) throw new Error('INVALID_DECISION');
    const before = timestamp(item.expectedDate);
    if (before.seconds < MIN_DATE || before.seconds >= MAX_DATE) throw new Error('INVALID_DECISION');
    decisions.set(item.id, {
      expectedDate: before, expectedUpdateTime: timestamp(item.expectedUpdateTime),
      after: calendarTimestamp(item.calendarDate), reviewRef: item.reviewRef,
    });
  }
  return decisions;
}

function validateRecord(data) {
  if (!data || Object.keys(data).some((key) => !FIELDS.includes(key))
    || typeof data.category !== 'string' || !data.category.trim() || data.category.length > 120
    || typeof data.description !== 'string' || !data.description.trim() || data.description.length > 1000
    || !Number.isSafeInteger(data.amount) || data.amount <= 0 || typeof data.isIncome !== 'boolean') {
    throw new Error('MALFORMED_RECORD');
  }
  timestamp(data.createdAt);
  timestamp(data.updatedAt);
  const date = timestamp(data.date);
  if (date.seconds < MIN_DATE || date.seconds >= MAX_DATE) throw new Error('DATE_OUT_OF_BOUNDS');
  if (Object.hasOwn(data, 'dateVersion')
    && (data.dateVersion !== 2 || date.nanoseconds !== 0 || date.seconds % 86400 !== 0)) throw new Error('INVALID_DATE_VERSION');
  return date;
}

function inspect(row, scope, decisions) {
  const entry = { id: row.id, status: 'ERROR', reason: 'MALFORMED_RECORD' };
  try {
    if (!validId(row.id)) return { entry };
    const date = validateRecord(row.data);
    const updateTime = timestamp(row.updateTime);
    if (date.seconds < calendarTimestamp(scope.from).seconds
      || date.seconds >= calendarTimestamp(scope.until, { upperBound: true }).seconds) {
      return { entry: { ...entry, status: 'SKIPPED', reason: 'OUTSIDE_UTC_SCAN_RANGE' } };
    }
    if (row.data.dateVersion === 2) return { entry: { ...entry, status: 'SKIPPED', reason: 'ALREADY_V2' } };
    entry.before = { date, updateTime };
    const decision = decisions.get(row.id);
    if (!decision) return { entry: { ...entry, status: 'AMBIGUOUS', reason: 'REVIEW_REQUIRED' } };
    if (!sameTimestamp(date, decision.expectedDate) || !sameTimestamp(updateTime, decision.expectedUpdateTime)) {
      return { entry: { ...entry, reason: 'STALE_DECISION' } };
    }
    return {
      entry: { ...entry, status: 'CANDIDATE', reason: 'REVIEWED_DATE', after: decision.after, reviewRef: decision.reviewRef },
      operation: {
        id: row.id, before: { date, updatedAt: timestamp(row.data.updatedAt) },
        expectedUpdateTime: updateTime, after: decision.after,
      },
    };
  } catch (error) {
    return { entry: { ...entry, reason: error.message } };
  }
}

// Each batch has a durable before-image before commit. Failed/unknown commits
// are never retried blindly; rerun starts with a new scan and the same review.
export async function runDateMigration({ adapter, scope, manifest, apply = false, batchSize = 100, limit = 500, afterId, journal }) {
  scope = validateScope(scope);
  if (!Number.isInteger(batchSize) || batchSize < 1 || batchSize > 100
    || !Number.isInteger(limit) || limit < 1 || limit > 5000
    || (afterId !== undefined && !validId(afterId))) throw new Error('INVALID_LIMIT');
  if (apply && (!manifest || !journal?.append)) throw new Error('APPLY_REQUIRES_DECISIONS_AND_JOURNAL');
  const decisions = decisionsFor(scope, manifest);
  const page = await adapter.scan({ scope, limit, afterId });
  if (!Array.isArray(page.rows) || page.rows.length > limit) throw new Error('INVALID_SCAN');
  const items = page.rows.map((row) => inspect(row, scope, decisions));
  const report = {
    formatVersion: 1, mode: apply ? 'apply' : 'dry-run',
    target: { projectId: scope.projectId, subjectHash: createHash('sha256').update(scope.uid).digest('hex'), from: scope.from, until: scope.until },
    scan: { limit, afterId: afterId ?? null, complete: !page.hasMore, nextAfterId: page.hasMore ? page.rows.at(-1)?.id : null },
    entries: items.map((item) => item.entry),
  };
  if (apply) {
    const candidates = items.filter((item) => item.operation);
    for (let offset = 0; offset < candidates.length; offset += batchSize) {
      const batch = candidates.slice(offset, offset + batchSize);
      let attempted = false;
      try {
        await journal.append({ kind: 'prepared', scope, operations: batch.map((item) => item.operation) });
        attempted = true;
        const receipts = await adapter.commit(batch.map((item) => item.operation));
        if (!Array.isArray(receipts) || receipts.length !== batch.length) throw new Error('INVALID_COMMIT_RECEIPT');
        await journal.append({ kind: 'committed', records: batch.map((item, i) => ({ id: item.operation.id, updateTime: timestamp(receipts[i]) })) });
        for (const item of batch) Object.assign(item.entry, { status: 'APPLIED', reason: 'COMMIT_CONFIRMED' });
      } catch {
        for (const item of batch) Object.assign(item.entry, {
          status: 'ERROR', reason: attempted ? 'COMMIT_OR_RECEIPT_UNCONFIRMED' : 'JOURNAL_NOT_DURABLE',
        });
        for (const item of candidates.slice(offset + batchSize)) Object.assign(item.entry, { status: 'NOT_ATTEMPTED', reason: 'STOPPED_AFTER_BATCH_FAILURE' });
        break;
      }
    }
  }
  report.counts = Object.fromEntries(['CANDIDATE', 'APPLIED', 'SKIPPED', 'AMBIGUOUS', 'ERROR', 'NOT_ATTEMPTED']
    .map((status) => [status.toLowerCase(), report.entries.filter((entry) => entry.status === status).length]));
  report.counts.scanned = report.entries.length;
  report.counts.planned = items.filter((item) => item.operation).length;
  return report;
}
