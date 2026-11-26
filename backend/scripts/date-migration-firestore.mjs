import { createRequire } from 'node:module';
import { timestamp, validateScope } from './date-migration.mjs';

// Reuse the Admin SDK already declared/locked by the Functions package.
const require = createRequire(new URL('../functions/package.json', import.meta.url));

export function migrationTarget(projectId, host, allowCloud = false) {
  if (!host) {
    if (!allowCloud) throw new Error('CLOUD_REQUIRES_EXPLICIT_ALLOW_CLOUD');
    return 'cloud';
  }
  const parsed = new URL(`http://${host}`);
  if (!['127.0.0.1', 'localhost'].includes(parsed.hostname) || !parsed.port
    || parsed.username || parsed.password || parsed.pathname !== '/' || parsed.search || parsed.hash
    || !projectId.startsWith('demo-')) throw new Error('INVALID_EMULATOR_TARGET');
  return 'emulator';
}

export function createFirestoreAdapter(scope, { allowCloud = false } = {}) {
  scope = validateScope(scope);
  migrationTarget(scope.projectId, process.env.FIRESTORE_EMULATOR_HOST, allowCloud);
  const { initializeApp, deleteApp } = require('firebase-admin/app');
  const { getFirestore, FieldPath, FieldValue, Timestamp } = require('firebase-admin/firestore');
  const app = initializeApp({ projectId: scope.projectId }, `date-migration-${process.pid}`);
  const db = getFirestore(app);
  const collection = db.collection('users').doc(scope.uid).collection('transactions');
  return {
    async scan({ scope: requestedScope, limit, afterId }) {
      if (Object.keys(scope).some((key) => requestedScope?.[key] !== scope[key])) throw new Error('ADAPTER_SCOPE_MISMATCH');
      let query = collection.orderBy(FieldPath.documentId()).limit(limit + 1);
      if (afterId) query = query.startAfter(afterId);
      const snapshot = await query.get();
      return {
        rows: snapshot.docs.slice(0, limit).map((doc) => ({ id: doc.id, data: doc.data(), updateTime: timestamp(doc.updateTime) })),
        hasMore: snapshot.size > limit,
      };
    },
    async commit(operations) {
      const batch = db.batch();
      for (const operation of operations) {
        batch.update(collection.doc(operation.id), {
          date: new Timestamp(operation.after.seconds, operation.after.nanoseconds),
          dateVersion: 2, updatedAt: FieldValue.serverTimestamp(),
        }, { lastUpdateTime: new Timestamp(operation.expectedUpdateTime.seconds, operation.expectedUpdateTime.nanoseconds) });
      }
      return (await batch.commit()).map((result) => timestamp(result.writeTime));
    },
    async close() { await db.terminate(); await deleteApp(app); },
  };
}
