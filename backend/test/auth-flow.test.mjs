import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { setTimeout as delay } from 'node:timers/promises';
import { afterEach, test } from 'node:test';
import { initializeApp, deleteApp } from 'firebase/app';
import {
  getAuth, connectAuthEmulator, createUserWithEmailAndPassword,
  signInWithEmailAndPassword, signOut, sendPasswordResetEmail,
  verifyPasswordResetCode, confirmPasswordReset,
} from 'firebase/auth';
import {
  getFirestore, connectFirestoreEmulator, doc, collection, setDoc,
  deleteDoc, getDocFromServer, getDocsFromServer, serverTimestamp, onSnapshot, terminate,
} from 'firebase/firestore';
import { emulatorAddress, projectId, profile, transaction, versionedUpdate as updateDoc } from './support/emulator.mjs';

const clients = [];
const password = 'Demo-test-Password123!';
const email = () => `${randomUUID()}@example.test`;
const denied = (request) => assert.rejects(request, { code: 'permission-denied' });

function client() {
  const authAddress = emulatorAddress('FIREBASE_AUTH_EMULATOR_HOST');
  const firestoreAddress = emulatorAddress('FIRESTORE_EMULATOR_HOST');
  const app = initializeApp({
    projectId, apiKey: 'emulator-only', appId: 'emulator-only',
  }, `test-${randomUUID()}`);
  const auth = getAuth(app);
  connectAuthEmulator(auth, authAddress.origin, { disableWarnings: true });
  const db = getFirestore(app);
  connectFirestoreEmulator(db, firestoreAddress.host, firestoreAddress.port);
  const result = { app, auth, db };
  clients.push(result);
  return result;
}

afterEach(async () => {
  for (const { app, auth, db } of clients.splice(0)) {
    try { await signOut(auth); }
    finally {
      try { await terminate(db); }
      finally { await deleteApp(app); }
    }
  }
});

test('Auth: daftar, tolak email duplikat/password lemah, login salah, login ulang dan logout', async () => {
  const { auth } = client();
  const address = email();
  await assert.rejects(createUserWithEmailAndPassword(auth, email(), '123'), { code: 'auth/weak-password' });
  const { user } = await createUserWithEmailAndPassword(auth, address, password);
  const uid = user.uid;
  assert.equal(auth.currentUser.uid, uid);
  await signOut(auth);
  assert.equal(auth.currentUser, null);
  await assert.rejects(createUserWithEmailAndPassword(auth, address, password), { code: 'auth/email-already-in-use' });
  await assert.rejects(signInWithEmailAndPassword(auth, address, 'incorrect-password'),
    (error) => ['auth/invalid-credential', 'auth/wrong-password'].includes(error.code));
  assert.equal(auth.currentUser, null);
  await signInWithEmailAndPassword(auth, address, password);
  assert.equal(auth.currentUser.uid, uid);
  await signOut(auth);
  assert.equal(auth.currentUser, null);
});

test('Auth: reset password mengganti kredensial dan kode tidak bisa dipakai dua kali', async () => {
  const { auth } = client();
  const address = email();
  await createUserWithEmailAndPassword(auth, address, password);
  await signOut(auth);
  await sendPasswordResetEmail(auth, address);
  // Endpoint ini hanya tersedia pada Auth Emulator; kode tidak dicetak ke log tes.
  const { origin } = emulatorAddress('FIREBASE_AUTH_EMULATOR_HOST');
  const response = await fetch(`${origin}/emulator/v1/projects/${projectId}/oobCodes`, {
    signal: AbortSignal.timeout(5000),
  });
  assert.equal(response.status, 200);
  const { oobCodes } = await response.json();
  const reset = oobCodes.find((item) => item.email === address && item.requestType === 'PASSWORD_RESET');
  assert.ok(reset, 'Auth Emulator tidak menghasilkan kode reset.');
  assert.equal(await verifyPasswordResetCode(auth, reset.oobCode), address);
  const newPassword = 'New-test-Password456!';
  await confirmPasswordReset(auth, reset.oobCode, newPassword);
  await assert.rejects(confirmPasswordReset(auth, reset.oobCode, newPassword), { code: 'auth/invalid-action-code' });
  await assert.rejects(signInWithEmailAndPassword(auth, address, password),
    (error) => ['auth/invalid-credential', 'auth/wrong-password'].includes(error.code));
  await signInWithEmailAndPassword(auth, address, newPassword);
  assert.equal(auth.currentUser.email, address);
});

test('Auth + Firestore: data persisten pada client baru dan akun B tidak mengakses akun A', async () => {
  const a = client();
  const address = email();
  const { user } = await createUserWithEmailAndPassword(a.auth, address, password);
  const uidA = user.uid;
  const profilePath = `users/${uidA}`;
  const transactionPath = `${profilePath}/transactions/stable`;
  await setDoc(doc(a.db, profilePath), { ...profile(), name: 'A persisten', darkMode: false });
  await setDoc(doc(a.db, transactionPath), transaction());
  const createdAt = (await getDocFromServer(doc(a.db, transactionPath))).data().createdAt;
  await updateDoc(doc(a.db, transactionPath), { amount: 200000, updatedAt: serverTimestamp() });
  await signOut(a.auth);
  await denied(getDocFromServer(doc(a.db, profilePath)));
  await denied(getDocFromServer(doc(a.db, transactionPath)));

  const b = client();
  const accountB = await createUserWithEmailAndPassword(b.auth, email(), password);
  assert.notEqual(accountB.user.uid, uidA);
  assert.equal((await getDocsFromServer(collection(b.db, `users/${accountB.user.uid}/transactions`))).size, 0);
  await denied(getDocFromServer(doc(b.db, profilePath)));
  await denied(getDocFromServer(doc(b.db, transactionPath)));
  await denied(getDocsFromServer(collection(b.db, `${profilePath}/transactions`)));
  await denied(setDoc(doc(b.db, `${profilePath}/transactions/intruder`), transaction()));
  await denied(updateDoc(doc(b.db, transactionPath), { amount: 999, updatedAt: serverTimestamp() }));
  await denied(deleteDoc(doc(b.db, transactionPath)));
  await denied(updateDoc(doc(b.db, profilePath), { name: 'Hijack', updatedAt: serverTimestamp() }));

  const reopened = client();
  await signInWithEmailAndPassword(reopened.auth, address, password);
  assert.equal(reopened.auth.currentUser.uid, uidA);
  const savedProfile = (await getDocFromServer(doc(reopened.db, profilePath))).data();
  assert.equal(savedProfile.name, 'A persisten');
  assert.equal(savedProfile.darkMode, false);
  const saved = (await getDocFromServer(doc(reopened.db, transactionPath))).data();
  assert.equal(saved.amount, 200000);
  assert.ok(saved.createdAt.isEqual(createdAt));
  await deleteDoc(doc(reopened.db, transactionPath));
  assert.equal((await getDocFromServer(doc(reopened.db, transactionPath))).exists(), false);
});

test('Firestore: listener akun yang sama menerima tambah, edit dan hapus dari client lain', async () => {
  const a = client();
  const address = email();
  const { user } = await createUserWithEmailAndPassword(a.auth, address, password);
  const remote = client();
  await signInWithEmailAndPassword(remote.auth, address, password);
  const location = `users/${user.uid}/transactions`;
  const received = [];
  let streamError;
  const unsubscribe = onSnapshot(collection(a.db, location), { includeMetadataChanges: true },
    (snapshot) => {
      if (!snapshot.metadata.isFromCache && !snapshot.metadata.hasPendingWrites) {
        received.push(snapshot.docs.map((item) => ({ id: item.id, amount: item.data().amount })));
      }
    }, (error) => { streamError = error; });
  async function waitFor(predicate) {
    const deadline = Date.now() + 15000;
    while (!received.some(predicate)) {
      if (streamError) throw streamError;
      assert.ok(Date.now() < deadline, 'Listener tidak menerima perubahan server dalam 15 detik.');
      await delay(25);
    }
  }
  try {
    await waitFor((rows) => rows.length === 0);
    received.length = 0;
    const ref = doc(remote.db, `${location}/stable`);
    await setDoc(ref, transaction());
    await waitFor((rows) => rows.length === 1 && rows[0].id === 'stable' && rows[0].amount === 100000);
    received.length = 0;
    await updateDoc(ref, { amount: 200000, updatedAt: serverTimestamp() });
    await waitFor((rows) => rows.length === 1 && rows[0].amount === 200000);
    received.length = 0;
    await deleteDoc(ref);
    await waitFor((rows) => rows.length === 0);
  } finally {
    unsubscribe();
  }
});
