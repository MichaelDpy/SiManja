// Emulator-only descriptive benchmark; never cloud billing or speedup proof.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { performance } from 'node:perf_hooks';
import { initializeTestEnvironment } from '@firebase/rules-unit-testing';
import { collection, doc, writeBatch, Timestamp, onSnapshot, getDocsFromServer } from 'firebase/firestore';
import { emulatorAddress, projectId } from '../test/support/emulator.mjs';
import { historyQuery } from '../test/support/transaction-query.mjs';

assert.equal(process.env.GCLOUD_PROJECT, projectId, 'Only demo-simanja is allowed');
const { host, port } = emulatorAddress('FIRESTORE_EMULATOR_HOST');
assert.equal(typeof global.gc, 'function', 'Run node --expose-gc for the declared measurement protocol');
const env = await initializeTestEnvironment({ projectId,
  firestore: { host, port, rules: readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8') } });
const uid = 'c06-synthetic-benchmark';
const range = { from: '2026-11-01', until: '2026-12-01', pageSize: 50 };
const median = (values) => [...values].sort((a, b) => a - b)[Math.floor(values.length / 2)];
const serverListener = (client) => new Promise((resolve, reject) => {
  const stop = onSnapshot(collection(client, `users/${uid}/transactions`), { includeMetadataChanges: true },
    (snapshot) => { if (!snapshot.metadata.fromCache) { stop(); resolve(snapshot); } }, reject);
});
async function measure(client, kind) {
  global.gc();
  const heapBefore = process.memoryUsage().heapUsed;
  const start = performance.now();
  const snapshot = kind === 'listener-all' ? await serverListener(client)
    : await getDocsFromServer(historyQuery(client, uid, range));
  const latencyMs = performance.now() - start;
  const payload = JSON.stringify(snapshot.docs.map((row) => ({ id: row.id, ...row.data() })));
  return { deliveredDocuments: snapshot.size, payloadJsonBytes: Buffer.byteLength(payload),
    latencyMs, heapDeltaBytes: process.memoryUsage().heapUsed - heapBefore };
}

try {
  const results = [];
  for (const volume of [100, 1000, 5000]) {
    await env.clearFirestore();
    await env.withSecurityRulesDisabled(async (context) => {
      const client = context.firestore();
      for (let offset = 0; offset < volume; offset += 400) {
        const batch = writeBatch(client);
        for (let i = offset; i < Math.min(offset + 400, volume); i++) {
          batch.set(doc(client, `users/${uid}/transactions/row-${String(i).padStart(5, '0')}`), {
            category: ['Gaji', 'Makanan', 'Transportasi'][i % 3],
            description: `Synthetic fixture ${i} — kebutuhan bulanan`,
            amount: i % 100 === 0 ? 9007199254740991 : 1000 + i,
            isIncome: i % 3 === 0,
            date: Timestamp.fromDate(new Date(Date.UTC(2026, i % 12, 1 + i % 28))),
            ...(i % 10 === 0 ? {} : { dateVersion: 2 }),
            createdAt: new Timestamp(1, 0), updatedAt: new Timestamp(1, 0), revision: 1,
          });
        }
        await batch.commit();
      }
    });
    const client = env.authenticatedContext(uid).firestore();
    // Warm up both code paths. Samples alternate order, without clearing SDK
    // caches; measurements therefore describe warm local emulator behavior.
    await measure(client, 'listener-all'); await measure(client, 'canonical-page');
    const samples = { 'listener-all': [], 'canonical-page': [] };
    for (let round = 0; round < 5; round++) {
      for (const kind of round % 2 ? ['canonical-page', 'listener-all'] : ['listener-all', 'canonical-page']) {
        const value = await measure(client, kind);
        assert.ok(value.deliveredDocuments <= (kind === 'listener-all' ? volume : 51));
        if (kind === 'listener-all') assert.equal(value.deliveredDocuments, volume);
        samples[kind].push(value);
      }
    }
    const summary = Object.fromEntries(Object.entries(samples).map(([kind, values]) => [kind, {
      deliveredDocuments: values[0].deliveredDocuments,
      payloadJsonBytes: values[0].payloadJsonBytes,
      medianLatencyMs: median(values.map((value) => value.latencyMs)),
      medianHeapDeltaBytes: median(values.map((value) => value.heapDeltaBytes)),
    }]));
    results.push({ volume, summary, samples });
    process.stdout.write(`C06_BENCH_VOLUME ${volume} PASS\n`);
  }
  process.stdout.write(`C06_BENCH_RESULT ${JSON.stringify({ protocol: 'C06-v1-warm-local-emulator',
    node: process.version, platform: process.platform, arch: process.arch,
    pageSize: 50, lookahead: 1, trials: 5, legacyPercent: 10, results })}\n`);
} finally { await env.cleanup(); }
