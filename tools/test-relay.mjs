// The relay (tools/relay-dev.mjs, same rules as worker/src/index.js): two sockets meet in a room and pass binary
// frames; text is the relay's own ('peer', 'gone'); a third socket in the same role replaces the old one.
import { spawn } from 'child_process';
import WebSocket from 'ws';
const sleep = (ms) => new Promise(r => setTimeout(r, ms));
export async function run(ok) {
  const port = 18000 + Math.floor(Math.random() * 1000), srv = spawn('node', [new URL('./relay-dev.mjs', import.meta.url).pathname, String(port)], { stdio: 'ignore' });
  await sleep(600);
  try {
    const url = (role) => `ws://localhost:${port}/r/0123456789abcdef?role=${role}`, open = (ws) => new Promise(r => ws.on('open', r));
    const f = new WebSocket(url('f')), m = new WebSocket(url('m')); const got = { f: [], m: [] };
    for (const [k, ws] of [['f', f], ['m', m]]) ws.on('message', (d, bin) => got[k].push(bin ? [...new Uint8Array(d)] : String(d)));
    await open(f); await open(m); await sleep(150);
    ok(got.f.includes('peer') && got.m.includes('peer'), 'both hear "peer" when the second arrives');
    m.send(Uint8Array.of(1, 2, 3)); await sleep(150);
    ok(got.f.some(x => Array.isArray(x) && x.join() === '1,2,3'), 'his binary frame reaches her untouched');
    m.close(); await sleep(150); ok(got.f.includes('gone'), 'she hears "gone" when he leaves');
    f.close();
  } finally { srv.kill(); }
}
