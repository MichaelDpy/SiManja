// Local test transport only: never deployed with the application/server.
import net from 'node:net';
import http from 'node:http';
import { pathToFileURL } from 'node:url';
import { resolve } from 'node:path';

export async function startOfflineProxy({ targetPort = 8080, dataPort = 18080, controlPort = 18081 } = {}) {
  let online = true;
  const connections = new Set();
  const data = net.createServer((client) => {
    if (!online) { client.destroy(); return; }
    const upstream = net.createConnection({ host: '127.0.0.1', port: targetPort });
    for (const socket of [client, upstream]) {
      connections.add(socket);
      socket.on('close', () => connections.delete(socket));
      socket.on('error', () => { client.destroy(); upstream.destroy(); });
    }
    client.on('close', () => upstream.destroy());
    upstream.on('close', () => client.destroy());
    client.pipe(upstream); upstream.pipe(client);
  });
  const control = http.createServer((req, res) => {
    if (req.method !== 'POST' || req.url !== '/network') { res.writeHead(404).end(); return; }
    let body = '';
    req.on('data', (chunk) => { body += chunk; if (body.length > 128) req.destroy(); });
    req.on('end', () => {
      try {
        const value = JSON.parse(body).online;
        if (typeof value !== 'boolean') throw new Error('invalid');
        online = value;
        if (!online) for (const socket of connections) socket.destroy();
        res.writeHead(200, { 'Content-Type': 'application/json' }).end(JSON.stringify({ online }));
      } catch { res.writeHead(400).end(); }
    });
  });
  const listen = (server, port) => new Promise((done, reject) => {
    server.once('error', reject); server.listen(port, '127.0.0.1', done);
  });
  try { await listen(data, dataPort); await listen(control, controlPort); }
  catch (error) { data.close(); control.close(); throw error; }
  return {
    dataPort: data.address().port, controlPort: control.address().port,
    async close() {
      for (const socket of connections) socket.destroy();
      await Promise.all([data, control].map((server) => new Promise((done) => server.close(done))));
    },
  };
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  if (process.env.GCLOUD_PROJECT !== 'demo-simanja' || process.env.FIRESTORE_EMULATOR_HOST !== '127.0.0.1:8080') {
    throw new Error('PROXY_REQUIRES_EXPLICIT_LOCAL_DEMO_TARGET');
  }
  const proxy = await startOfflineProxy();
  process.stdout.write('C05_PROXY_READY data=18080 control=18081 loopback-only\n');
  const stop = async () => { await proxy.close(); process.exit(0); };
  process.once('SIGINT', stop); process.once('SIGTERM', stop);
}
