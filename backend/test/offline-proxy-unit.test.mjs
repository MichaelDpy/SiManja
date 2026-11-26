import assert from 'node:assert/strict';
import net from 'node:net';
import { once } from 'node:events';
import { test } from 'node:test';
import { startOfflineProxy } from './support/offline-firestore-proxy.mjs';

test('proxy meneruskan TCP, memutus koneksi aktif dan menolak koneksi baru saat offline', async () => {
  const target = net.createServer((socket) => socket.pipe(socket));
  target.listen(0, '127.0.0.1'); await once(target, 'listening');
  const proxy = await startOfflineProxy({ targetPort: target.address().port, dataPort: 0, controlPort: 0 });
  const toggle = (online) => fetch(`http://127.0.0.1:${proxy.controlPort}/network`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ online }),
  });
  const connect = async () => {
    const socket = net.createConnection(proxy.dataPort, '127.0.0.1');
    socket.on('error', () => {});
    await once(socket, 'connect'); return socket;
  };
  try {
    const first = await connect();
    const reply = once(first, 'data'); first.write('fixture');
    assert.equal((await reply)[0].toString(), 'fixture');
    const closed = once(first, 'close');
    assert.equal((await toggle(false)).status, 200); await closed;
    const offline = await connect();
    if (!offline.destroyed) await once(offline, 'close');
    await toggle(true);
    const restored = await connect();
    const secondReply = once(restored, 'data'); restored.write('reconnected');
    assert.equal((await secondReply)[0].toString(), 'reconnected'); restored.destroy();
  } finally {
    await proxy.close(); await new Promise((done) => target.close(done));
  }
});
