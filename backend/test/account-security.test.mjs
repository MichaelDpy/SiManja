// B03–B05: perilaku Firebase Auth nyata (Auth Emulator) yang dipakai
// AuthService: reset tanpa enumerasi, verifikasi email, autentikasi ulang,
// dan ganti password. Tidak memakai project cloud.
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { afterEach, test } from 'node:test';
import { initializeApp, deleteApp } from 'firebase/app';
import {
  getAuth, connectAuthEmulator, createUserWithEmailAndPassword,
  signInWithEmailAndPassword, signOut, sendPasswordResetEmail,
  sendEmailVerification, applyActionCode, reload,
  reauthenticateWithCredential, updatePassword, EmailAuthProvider,
} from 'firebase/auth';
import { emulatorAddress, projectId } from './support/emulator.mjs';

const apps = [];
const password = 'Demo-test-Password123!';
const email = () => `${randomUUID()}@example.test`;

function client() {
  const { origin } = emulatorAddress('FIREBASE_AUTH_EMULATOR_HOST');
  const app = initializeApp({
    projectId, apiKey: 'emulator-only', appId: 'emulator-only',
  }, `security-${randomUUID()}`);
  const auth = getAuth(app);
  connectAuthEmulator(auth, origin, { disableWarnings: true });
  apps.push({ app, auth });
  return auth;
}

afterEach(async () => {
  for (const { app, auth } of apps.splice(0)) {
    try { await signOut(auth); } finally { await deleteApp(app); }
  }
});

// Endpoint khusus Auth Emulator; kode tidak dicetak ke log tes.
async function oobCode(address, requestType) {
  const { origin } = emulatorAddress('FIREBASE_AUTH_EMULATOR_HOST');
  const response = await fetch(`${origin}/emulator/v1/projects/${projectId}/oobCodes`, {
    signal: AbortSignal.timeout(5000),
  });
  assert.equal(response.status, 200);
  const { oobCodes } = await response.json();
  const found = oobCodes.filter((item) => item.email === address && item.requestType === requestType);
  assert.ok(found.length > 0, `Auth Emulator tidak menghasilkan kode ${requestType}.`);
  return found.at(-1).oobCode;
}

test('B03: reset ke email tak terdaftar ditolak server sebagai user-not-found', async () => {
  // AuthService.resetPassword menelan kode ini agar UI tidak membocorkan
  // keberadaan akun ketika perlindungan enumerasi project nonaktif.
  const auth = client();
  await assert.rejects(sendPasswordResetEmail(auth, email()), { code: 'auth/user-not-found' });
});

test('B03: server menolak password di bawah batas minimum Firebase', async () => {
  const auth = client();
  await assert.rejects(createUserWithEmailAndPassword(auth, email(), '12345'), { code: 'auth/weak-password' });
  const { user } = await createUserWithEmailAndPassword(auth, email(), '123456');
  assert.ok(user.uid, 'Enam karakter adalah batas minimum Firebase yang diterima.');
});

test('B04: akun baru belum terverifikasi; tautan dibuka lalu reload memperbarui status', async () => {
  const auth = client();
  const address = email();
  const { user } = await createUserWithEmailAndPassword(auth, address, password);
  assert.equal(user.emailVerified, false);

  await sendEmailVerification(user);
  const code = await oobCode(address, 'VERIFY_EMAIL');

  // Tanpa reload, status lokal tetap lama walaupun server berubah.
  await applyActionCode(client(), code);
  assert.equal(auth.currentUser.emailVerified, false);
  await reload(auth.currentUser);
  assert.equal(auth.currentUser.emailVerified, true);
});

test('B04: tautan verifikasi yang sudah dipakai ditolak (invalid-action-code)', async () => {
  const auth = client();
  const address = email();
  const { user } = await createUserWithEmailAndPassword(auth, address, password);
  await sendEmailVerification(user);
  const code = await oobCode(address, 'VERIFY_EMAIL');
  await applyActionCode(auth, code);
  await assert.rejects(applyActionCode(auth, code), { code: 'auth/invalid-action-code' });
});

test('B04: status verifikasi bertahan setelah login ulang (app restart)', async () => {
  const first = client();
  const address = email();
  const { user } = await createUserWithEmailAndPassword(first, address, password);
  await sendEmailVerification(user);
  await applyActionCode(first, await oobCode(address, 'VERIFY_EMAIL'));
  await signOut(first);

  const second = client();
  const { user: again } = await signInWithEmailAndPassword(second, address, password);
  assert.equal(again.uid, user.uid);
  assert.equal(again.emailVerified, true);
});

test('B05: reauth password salah gagal dan password lama tetap berlaku', async () => {
  const auth = client();
  const address = email();
  const { user } = await createUserWithEmailAndPassword(auth, address, password);
  await assert.rejects(
    reauthenticateWithCredential(user, EmailAuthProvider.credential(address, 'salah-sekali')),
    (error) => ['auth/invalid-credential', 'auth/wrong-password'].includes(error.code),
  );
  await signOut(auth);
  const { user: again } = await signInWithEmailAndPassword(client(), address, password);
  assert.equal(again.uid, user.uid);
});

test('B05: reauth benar lalu ganti password; UID tetap dan password lama ditolak', async () => {
  const auth = client();
  const address = email();
  const next = 'Password-Baru-456!';
  const { user } = await createUserWithEmailAndPassword(auth, address, password);
  const result = await reauthenticateWithCredential(user, EmailAuthProvider.credential(address, password));
  assert.equal(result.user.uid, user.uid);
  await updatePassword(result.user, next);
  await signOut(auth);

  await assert.rejects(signInWithEmailAndPassword(client(), address, password),
    (error) => ['auth/invalid-credential', 'auth/wrong-password'].includes(error.code));
  const { user: again } = await signInWithEmailAndPassword(client(), address, next);
  assert.equal(again.uid, user.uid);
});

test('B05: reauth dengan kredensial akun lain ditolak (user-mismatch)', async () => {
  const other = email();
  await createUserWithEmailAndPassword(client(), other, password);
  const auth = client();
  const { user } = await createUserWithEmailAndPassword(auth, email(), password);
  await assert.rejects(
    reauthenticateWithCredential(user, EmailAuthProvider.credential(other, password)),
    { code: 'auth/user-mismatch' },
  );
  assert.equal(auth.currentUser.uid, user.uid);
});
