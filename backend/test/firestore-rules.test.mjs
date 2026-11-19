import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { before, after, beforeEach, test } from 'node:test';
import { initializeTestEnvironment, assertSucceeds } from '@firebase/rules-unit-testing';
import {
  doc, collection, collectionGroup, setDoc, updateDoc, deleteDoc, deleteField,
  getDocFromServer, getDocsFromServer, serverTimestamp, Timestamp, writeBatch,
} from 'firebase/firestore';
import { emulatorAddress, projectId, profile, transaction } from './support/emulator.mjs';

let env;
before(async () => {
  const { host, port } = emulatorAddress('FIRESTORE_EMULATOR_HOST');
  env = await initializeTestEnvironment({
    projectId,
    firestore: { host, port, rules: readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8') },
  });
});
beforeEach(async () => { await env.clearFirestore(); });
after(async () => { await env?.cleanup(); });

const db = (uid = 'A') => uid === null
  ? env.unauthenticatedContext().firestore()
  : env.authenticatedContext(uid).firestore();
const path = (owner = 'A', id = 'stable') => `users/${owner}/transactions/${id}`;
const denied = (request) => assert.rejects(request, { code: 'permission-denied' });

test('pemilik dapat CRUD, list, dan mempertahankan ID serta createdAt transaksi', async () => {
  const own = db();
  const ref = doc(own, path());
  await assertSucceeds(setDoc(ref, transaction()));
  const first = await getDocFromServer(ref);
  assert.equal(first.id, 'stable');
  assert.ok(first.data().createdAt instanceof Timestamp);
  await assertSucceeds(updateDoc(ref, { amount: 200000, updatedAt: serverTimestamp() }));
  const changed = await getDocFromServer(ref);
  assert.equal(changed.data().amount, 200000);
  assert.ok(changed.data().createdAt.isEqual(first.data().createdAt));
  assert.equal((await getDocsFromServer(collection(own, 'users/A/transactions'))).size, 1);
  await assertSucceeds(deleteDoc(ref));
  assert.equal((await getDocFromServer(ref)).exists(), false);
  await assertSucceeds(deleteDoc(ref));
});

test('profil pemilik dapat dibaca dan diedit sebagian tanpa menimpa preferensi', async () => {
  const ref = doc(db(), 'users/A');
  await assertSucceeds(setDoc(ref, profile()));
  const first = (await getDocFromServer(ref)).data();
  await assertSucceeds(updateDoc(ref, { darkMode: false, updatedAt: serverTimestamp() }));
  await assertSucceeds(updateDoc(ref, { name: 'Nama baru', updatedAt: serverTimestamp() }));
  const changed = (await getDocFromServer(ref)).data();
  assert.equal(changed.name, 'Nama baru');
  assert.equal(changed.darkMode, false);
  assert.ok(changed.createdAt.isEqual(first.createdAt));
  await denied(deleteDoc(ref));
  await denied(getDocsFromServer(collection(db(), 'users')));
});

for (const uid of [null, 'B']) {
  test(`${uid ?? 'tanpa sesi'} tidak dapat get/list/create/update/delete transaksi A`, async () => {
    await setDoc(doc(db(), path()), transaction());
    const other = db(uid);
    const ref = doc(other, path());
    await denied(getDocFromServer(ref));
    await denied(getDocsFromServer(collection(other, 'users/A/transactions')));
    await denied(setDoc(doc(other, path('A', 'new')), transaction()));
    await denied(updateDoc(ref, { amount: 2, updatedAt: serverTimestamp() }));
    await denied(deleteDoc(ref));
    assert.equal((await getDocFromServer(doc(db(), path()))).data().amount, 100000);
  });
  test(`${uid ?? 'tanpa sesi'} tidak dapat membaca, membuat atau mengubah profil A`, async () => {
    await setDoc(doc(db(), 'users/A'), profile());
    const other = db(uid);
    const ref = doc(other, 'users/A');
    await denied(getDocFromServer(ref));
    await denied(getDocsFromServer(collection(other, 'users')));
    await denied(setDoc(doc(other, 'users/A-new'), profile()));
    await denied(updateDoc(ref, { name: 'Hijack', updatedAt: serverTimestamp() }));
    await denied(setDoc(ref, profile()));
    await denied(deleteDoc(ref));
  });
}

test('akun baru kosong dan transaksi masing-masing UID terpisah', async () => {
  const a = db();
  const b = db('B');
  assert.equal((await getDocsFromServer(collection(b, 'users/B/transactions'))).size, 0);
  await setDoc(doc(a, path()), transaction());
  await setDoc(doc(b, path('B')), { ...transaction(), amount: 200 });
  assert.equal((await getDocsFromServer(collection(a, 'users/A/transactions'))).size, 1);
  assert.equal((await getDocFromServer(doc(b, path('B')))).data().amount, 200);
  await denied(getDocsFromServer(collectionGroup(a, 'transactions')));
});

const invalidTransactions = [
  ['nominal nol', { amount: 0 }],
  ['nominal negatif', { amount: -1 }],
  ['nominal pecahan', { amount: 1.5 }],
  ['nominal string', { amount: '1000' }],
  ['nominal NaN', { amount: NaN }],
  ['nominal Infinity', { amount: Infinity }],
  ['nominal melebihi integer aman', { amount: 9007199254740992 }],
  ['kategori kosong', { category: '' }],
  ['kategori hanya spasi', { category: ' \t\n' }],
  ['kategori salah tipe', { category: 1 }],
  ['kategori terlalu panjang', { category: 'x'.repeat(121) }],
  ['deskripsi kosong', { description: '' }],
  ['deskripsi hanya spasi', { description: ' \t\n' }],
  ['deskripsi salah tipe', { description: null }],
  ['deskripsi terlalu panjang', { description: 'x'.repeat(1001) }],
  ['boolean salah tipe', { isIncome: 'true' }],
  ['tanggal string', { date: '2026-01-01' }],
  ['tanggal terlalu awal', { date: Timestamp.fromDate(new Date('1899-12-31T23:59:59Z')) }],
  ['tanggal terlalu akhir', { date: Timestamp.fromDate(new Date('2201-01-01T00:00:00Z')) }],
  ['field asing', { ownerId: 'A' }],
  ['updatedAt waktu client', { updatedAt: Timestamp.fromMillis(1) }],
  ['createdAt null', { createdAt: null }],
];

for (const [name, invalid] of invalidTransactions) {
  test(`transaksi invalid ditolak saat create dan update: ${name}`, async () => {
    const ref = doc(db(), path());
    await denied(setDoc(ref, { ...transaction(), ...invalid }));
    await setDoc(ref, transaction());
    await denied(updateDoc(ref, { updatedAt: serverTimestamp(), ...invalid }));
    assert.equal((await getDocFromServer(ref)).data().amount, 100000);
  });
}

const invalidProfiles = [
  ['nama kosong', { name: '' }],
  ['nama hanya spasi', { name: ' \t\n' }],
  ['nama salah tipe', { name: 1 }],
  ['nama terlalu panjang', { name: 'x'.repeat(121) }],
  ['telepon salah tipe', { phone: 123456789 }],
  ['telepon terlalu panjang', { phone: '1'.repeat(31) }],
  ['telepon mengandung huruf', { phone: 'abc123456789' }],
  ['telepon kurang dari 9 digit', { phone: '12345678' }],
  ['telepon lebih dari 15 digit', { phone: '1234567890123456' }],
  ['alamat salah tipe', { address: [] }],
  ['alamat terlalu panjang', { address: 'x'.repeat(501) }],
  ['kota salah tipe', { city: null }],
  ['kota terlalu panjang', { city: 'x'.repeat(121) }],
  ['pekerjaan salah tipe', { job: false }],
  ['pekerjaan terlalu panjang', { job: 'x'.repeat(121) }],
  ['pendapatan negatif', { monthlyIncome: -1 }],
  ['pendapatan pecahan', { monthlyIncome: 1.5 }],
  ['pendapatan string', { monthlyIncome: '1000' }],
  ['pendapatan NaN', { monthlyIncome: NaN }],
  ['pendapatan Infinity', { monthlyIncome: Infinity }],
  ['pendapatan melebihi integer aman', { monthlyIncome: 9007199254740992 }],
  ['tema salah tipe', { darkMode: 'true' }],
  ['notifikasi salah tipe', { notifEnabled: 1 }],
  ['updatedAt waktu client', { updatedAt: Timestamp.fromMillis(1) }],
  ['createdAt null', { createdAt: null }],
  ['password di Firestore', { password: 'never-store-password' }],
  ['email identitas di Firestore', { email: 'other@example.test' }],
  ['path foto lokal di Firestore', { photoPath: '/private/file' }],
];

for (const [name, invalid] of invalidProfiles) {
  test(`profil invalid ditolak saat create dan update: ${name}`, async () => {
    const ref = doc(db(), 'users/A');
    await denied(setDoc(ref, { ...profile(), ...invalid }));
    await setDoc(ref, profile());
    await denied(updateDoc(ref, { updatedAt: serverTimestamp(), ...invalid }));
    assert.equal((await getDocFromServer(ref)).data().name, 'Pengguna A');
  });
}

for (const [kind, documentPath, fixture] of [
  ['profil', 'users/A', profile],
  ['transaksi', path(), transaction],
]) {
  test(`${kind}: setiap field wajib, metadata server dan createdAt immutable`, async () => {
    const ref = doc(db(), documentPath);
    for (const field of Object.keys(fixture())) {
      const missing = fixture();
      delete missing[field];
      await denied(setDoc(ref, missing));
    }
    await denied(setDoc(ref, { ...fixture(), createdAt: Timestamp.fromMillis(1) }));
    await setDoc(ref, fixture());
    for (const field of Object.keys(fixture())) {
      await denied(updateDoc(ref, { updatedAt: serverTimestamp(), [field]: deleteField() }));
    }
    await denied(updateDoc(ref, { createdAt: serverTimestamp(), updatedAt: serverTimestamp() }));
    await denied(updateDoc(ref, { createdAt: Timestamp.fromMillis(1), updatedAt: serverTimestamp() }));
    // Write tanpa updatedAt baru tetap ditolak.
    await denied(updateDoc(ref, kind === 'profil' ? { name: 'Tanpa metadata' } : { amount: 2 }));
  });
}

test('batas nominal, panjang teks dan tanggal valid tetap diterima', async () => {
  const own = db();
  await assertSucceeds(setDoc(doc(own, 'users/A'), {
    ...profile(), name: 'x'.repeat(120), phone: '+62 (812) 3456-7890',
    address: 'x'.repeat(500), city: 'x'.repeat(120), job: 'x'.repeat(120),
    monthlyIncome: 9007199254740991,
  }));
  for (const phone of ['', '123456789', '123456789012345']) {
    await assertSucceeds(updateDoc(doc(own, 'users/A'), { phone, updatedAt: serverTimestamp() }));
  }
  for (const [id, amount, date] of [
    ['min', 1, '1900-01-01T00:00:00Z'],
    ['max', 9007199254740991, '2200-12-31T23:59:59.999Z'],
  ]) {
    await assertSucceeds(setDoc(doc(own, path('A', id)), {
      ...transaction(), amount, category: 'x'.repeat(120), description: 'x'.repeat(1000),
      isIncome: false, date: Timestamp.fromDate(new Date(date)),
    }));
  }
});

test('batch berisi akses lintas UID ditolak utuh', async () => {
  const own = db();
  const batch = writeBatch(own);
  batch.set(doc(own, path('A', 'allowed')), transaction());
  batch.set(doc(own, path('B', 'denied')), transaction());
  await denied(batch.commit());
  assert.equal((await getDocFromServer(doc(own, path('A', 'allowed')))).exists(), false);
});

test('path yang belum didukung dan subcollection tambahan selalu ditolak', async () => {
  for (const uid of ['A', 'B', null]) {
    const client = db(uid);
    for (const location of ['unlisted/document', 'users/A/accounts/demo', `${path()}/private/data`]) {
      const ref = doc(client, location);
      await denied(setDoc(ref, { value: true }));
      await denied(getDocFromServer(ref));
      await denied(deleteDoc(ref));
    }
  }
});
