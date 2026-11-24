// node tools/relay-dev.mjs [port] — the relay (worker/src/index.js) for local tests, on ws://localhost:8787/r/<room>?role=f|m
import { WebSocketServer } from 'ws';
const port = +(process.argv[2] || 8787), rooms = new Map();
const wss = new WebSocketServer({ port });
wss.on('connection', (ws, req) => {
  const u = new URL(req.url, 'http://x'), m = u.pathname.match(/^\/r\/([0-9a-f]{16})$/), role = u.searchParams.get('role');
  if (!m || (role !== 'f' && role !== 'm')) return ws.close(4400, 'bad');
  const room = rooms.get(m[1]) || {}; rooms.set(m[1], room);
  if (room[role]) try { room[role].close(4000, 'replaced'); } catch (e) {}
  room[role] = ws; const other = () => room[role === 'f' ? 'm' : 'f'];
  if (other()) { other().send('peer'); ws.send('peer'); }
  ws.on('message', (d, isBinary) => { if (!isBinary) { if (String(d) === 'ping') ws.send('pong'); return; } const o = other(); if (o) o.send(d, { binary: true }); });
  ws.on('close', () => { if (room[role] === ws) delete room[role]; const o = other(); if (o) o.send('gone'); if (!room.f && !room.m) rooms.delete(m[1]); });
});
console.log(`relay on ws://localhost:${port}`);
