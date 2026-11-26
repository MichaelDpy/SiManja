import assert from 'node:assert/strict';
import { Timestamp, serverTimestamp, increment, updateDoc } from 'firebase/firestore';

// Existing behavior tests use the C04 revision protocol for their valid writes;
// dedicated conflict tests use raw updateDoc to verify rejected stale writes.
export const versionedUpdate = (ref, data) => updateDoc(ref, { revision: increment(1), ...data });

export const projectId = 'demo-simanja';

// Tes harus berhenti sebelum membuat client bila emulator belum disiapkan.
export function emulatorAddress(variable) {
  const address = process.env[variable];
  assert.ok(address, `${variable} belum diatur. Jalankan npm.cmd test dari backend/.`);
  const url = new URL(`http://${address}`);
  assert.ok(['127.0.0.1', 'localhost'].includes(url.hostname), 'Tes hanya memakai emulator lokal.');
  assert.ok(url.port && Number(url.port) > 0, 'Port emulator tidak valid.');
  assert.equal(url.username + url.password + url.search + url.hash, '');
  assert.equal(url.pathname, '/');
  return { host: url.hostname, port: Number(url.port), origin: url.origin };
}

export const profile = () => ({
  name: 'Pengguna A',
  phone: '',
  address: '',
  city: '',
  job: '',
  monthlyIncome: 0,
  darkMode: true,
  notifEnabled: true,
  createdAt: serverTimestamp(),
  updatedAt: serverTimestamp(),
});

export const transaction = () => ({
  category: 'Gaji',
  description: 'Transaksi pengujian',
  amount: 100000,
  isIncome: true,
  date: Timestamp.fromDate(new Date('2026-01-31T00:00:00+07:00')),
  createdAt: serverTimestamp(),
  updatedAt: serverTimestamp(),
});
