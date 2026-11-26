// Cloud Functions SIMANJA — permintaan penghapusan akun (B10).
// Hanya diuji di Firebase Emulator. Deploy ke project nyata memerlukan
// paket Blaze dan keputusan target/region (R00), tidak dilakukan otomatis.
import { initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';
import { setGlobalOptions } from 'firebase-functions/v2';
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import * as logger from 'firebase-functions/logger';

import {
  LIFECYCLE_COLLECTION, DeletionError, assertRecentAuth, callerUid,
  planCancel, planRequest, toStatus, validateRequestId,
} from './deletion.js';

// Region harus sama dengan client (lib/services/account_deletion_service.dart).
// Default Firebase dipakai sampai region R00 diputuskan.
export const REGION = 'us-central1';
setGlobalOptions({ region: REGION, maxInstances: 5 });

initializeApp();
const db = getFirestore();

function lifecycleRef(uid) {
  return db.collection(LIFECYCLE_COLLECTION).doc(uid);
}

/** Petakan error domain ke HttpsError tanpa membocorkan detail internal. */
function wrap(handler) {
  return async (request) => {
    try {
      return await handler(request);
    } catch (error) {
      if (error instanceof DeletionError) {
        throw new HttpsError(error.code, error.message, { reason: error.reason });
      }
      if (error instanceof HttpsError) throw error;
      logger.error('account deletion handler failed', { name: error?.name });
      throw new HttpsError('internal', 'Permintaan belum dapat diproses.');
    }
  };
}

/** Akun Auth harus masih ada dan aktif; Admin SDK melewati rules. */
async function assertActiveAccount(uid) {
  try {
    const user = await getAuth().getUser(uid);
    if (user.disabled) {
      throw new DeletionError('permission-denied', 'account-disabled');
    }
  } catch (error) {
    if (error instanceof DeletionError) throw error;
    if (error?.code === 'auth/user-not-found') {
      throw new DeletionError('permission-denied', 'account-not-found');
    }
    throw error;
  }
}

const callableOptions = {
  // App Check dipasang di B16; sampai saat itu otorisasi bergantung pada
  // token Auth + recent login yang diperiksa di bawah.
  enforceAppCheck: false,
};

export const getAccountDeletionStatus = onCall(callableOptions, wrap(async (request) => {
  const uid = callerUid(request.auth);
  const snapshot = await lifecycleRef(uid).get();
  return toStatus(snapshot.exists ? snapshot.data() : null);
}));

export const requestAccountDeletion = onCall(callableOptions, wrap(async (request) => {
  const uid = callerUid(request.auth);
  assertRecentAuth(request.auth.token?.auth_time, Date.now());
  const requestId = validateRequestId(request.data?.requestId);
  await assertActiveAccount(uid);

  const result = await db.runTransaction(async (tx) => {
    const ref = lifecycleRef(uid);
    const snapshot = await tx.get(ref);
    const plan = planRequest(snapshot.exists ? snapshot.data() : null, {
      requestId,
      nowMs: Date.now(),
    });
    if (plan.write) tx.set(ref, plan.write);
    return { created: plan.write !== null, doc: plan.doc };
  });
  if (result.created) logger.info('account deletion requested', { uid });
  return { ...toStatus(result.doc), created: result.created };
}));

export const cancelAccountDeletion = onCall(callableOptions, wrap(async (request) => {
  const uid = callerUid(request.auth);
  const result = await db.runTransaction(async (tx) => {
    const ref = lifecycleRef(uid);
    const snapshot = await tx.get(ref);
    const plan = planCancel(snapshot.exists ? snapshot.data() : null, { nowMs: Date.now() });
    if (plan.write) tx.set(ref, plan.write);
    return plan.doc;
  });
  return toStatus(result);
}));
