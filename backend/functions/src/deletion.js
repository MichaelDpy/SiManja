// Kontrak R-DELETE bagian B10: permintaan, status, dan pembatalan penghapusan
// akun. Modul murni (tanpa Firebase) agar aturan otorisasi dan idempotensi
// dapat diuji langsung. Worker pembersihan data adalah B11; revokasi dan
// retensi adalah B12.

/** Koleksi admin-only. Rules client default-deny; hanya Admin SDK menulis. */
export const LIFECYCLE_COLLECTION = 'accountLifecycle';

/** Batas umur login untuk operasi hapus akun (detik). */
export const RECENT_AUTH_MAX_AGE_SECONDS = 5 * 60;

/**
 * Status siklus penghapusan.
 * - none: tidak ada permintaan aktif (dokumen tidak ada).
 * - requested: diterima, menunggu worker (B11); masih dapat dibatalkan.
 * - processing: worker berjalan; tidak dapat dibatalkan; write dibekukan (C09).
 * - completed: selesai (B11/B12); tidak dapat dibatalkan.
 * - failed: worker gagal; pemilik/operasi menindaklanjuti (B11/B12).
 * - cancelled: dibatalkan pengguna sebelum processing.
 */
export const States = Object.freeze({
  none: 'none',
  requested: 'requested',
  processing: 'processing',
  completed: 'completed',
  failed: 'failed',
  cancelled: 'cancelled',
});

/** Status yang membekukan write normal pengguna (dipakai C09/B11). */
export const FROZEN_STATES = Object.freeze([
  States.requested, States.processing, States.completed,
]);

export class DeletionError extends Error {
  /**
   * @param {'unauthenticated'|'permission-denied'|'failed-precondition'|'invalid-argument'} code
   * @param {string} reason kode mesin yang stabil untuk dipetakan client.
   */
  constructor(code, reason, message = reason) {
    super(message);
    this.code = code;
    this.reason = reason;
  }
}

const REQUEST_ID = /^[A-Za-z0-9_-]{8,64}$/;

/**
 * Ambil identitas pemanggil dari token terverifikasi. UID di payload tidak
 * pernah dipakai: pemanggil hanya dapat bertindak atas akunnya sendiri.
 */
export function callerUid(auth) {
  const uid = auth?.uid;
  if (typeof uid !== 'string' || uid.length === 0) {
    throw new DeletionError('unauthenticated', 'unauthenticated', 'Harus masuk terlebih dahulu.');
  }
  return uid;
}

/** auth_time token (detik) harus cukup baru; jam server sebagai acuan. */
export function assertRecentAuth(authTimeSeconds, nowMs, maxAgeSeconds = RECENT_AUTH_MAX_AGE_SECONDS) {
  const authTime = Number(authTimeSeconds);
  if (!Number.isFinite(authTime) || authTime <= 0) {
    throw new DeletionError('failed-precondition', 'requires-recent-login');
  }
  const ageSeconds = nowMs / 1000 - authTime;
  // Toleransi kecil untuk selisih jam; auth_time di masa depan jauh ditolak.
  if (ageSeconds > maxAgeSeconds || ageSeconds < -60) {
    throw new DeletionError('failed-precondition', 'requires-recent-login');
  }
}

export function validateRequestId(requestId) {
  if (typeof requestId !== 'string' || !REQUEST_ID.test(requestId)) {
    throw new DeletionError('invalid-argument', 'invalid-request-id');
  }
  return requestId;
}

/**
 * Rencana untuk permintaan baru.
 * Idempoten: permintaan ulang (requestId sama atau berbeda) saat sudah ada
 * proses aktif/selesai tidak membuat proses kedua; status yang ada dikembalikan.
 */
export function planRequest(existing, { requestId, nowMs }) {
  const state = existing?.state ?? States.none;
  if ([States.requested, States.processing, States.completed].includes(state)) {
    return { write: null, doc: existing };
  }
  const doc = {
    state: States.requested,
    requestId,
    requestedAtMs: nowMs,
    updatedAtMs: nowMs,
    version: (existing?.version ?? 0) + 1,
    // Riwayat minimum untuk audit tanpa data pribadi.
    previousState: state,
  };
  return { write: doc, doc };
}

/** Rencana pembatalan: hanya saat requested; none/cancelled → tanpa perubahan. */
export function planCancel(existing, { nowMs }) {
  const state = existing?.state ?? States.none;
  if (state === States.none || state === States.cancelled) {
    return { write: null, doc: existing ?? null };
  }
  if (state !== States.requested) {
    throw new DeletionError('failed-precondition', 'deletion-not-cancellable');
  }
  const doc = {
    ...existing,
    state: States.cancelled,
    cancelledAtMs: nowMs,
    updatedAtMs: nowMs,
    version: (existing.version ?? 0) + 1,
    previousState: state,
  };
  return { write: doc, doc };
}

/** Bentuk respons untuk client; tidak membocorkan field internal lain. */
export function toStatus(doc) {
  if (!doc) return { state: States.none };
  return {
    state: doc.state,
    requestId: doc.requestId ?? null,
    requestedAtMs: doc.requestedAtMs ?? null,
    updatedAtMs: doc.updatedAtMs ?? null,
  };
}
