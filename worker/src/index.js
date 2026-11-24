// OPUlation relay. A room (8 random bytes from her face) holds at most one socket per role: 'f' (her) and 'm' (him).
// Binary frames from one go to the other, untouched; the relay can't read them (they're sealed end to end, js/pair.js)
// and can't forge his key either (her face and his song catch that). Text frames are the relay's own: 'peer' when
// both are in, 'gone' when one leaves. Nothing is stored; a room is just a Durable Object holding two sockets.
const MAX = 1 << 20;   // largest frame passed on
export class Room {
  constructor(state) { this.state = state; }
  async fetch(req) {
    const role = new URL(req.url).searchParams.get('role');
    if (role !== 'f' && role !== 'm') return new Response('role must be f or m', { status: 400 });
    if (req.headers.get('Upgrade') !== 'websocket') return new Response('websocket only', { status: 426 });
    const [client, server] = Object.values(new WebSocketPair());
    for (const old of this.state.getWebSockets(role)) { try { old.close(4000, 'replaced'); } catch (e) {} }
    this.state.acceptWebSocket(server, [role]);
    const other = this.state.getWebSockets(role === 'f' ? 'm' : 'f')[0];
    if (other) { try { other.send('peer'); server.send('peer'); } catch (e) {} }
    return new Response(null, { status: 101, webSocket: client });
  }
  other(ws) { const role = this.state.getTags(ws)[0]; return this.state.getWebSockets(role === 'f' ? 'm' : 'f')[0]; }
  webSocketMessage(ws, msg) {
    if (typeof msg === 'string') { if (msg === 'ping') ws.send('pong'); return; }
    if (msg.byteLength > MAX) return;
    const o = this.other(ws); if (o) try { o.send(msg); } catch (e) {}
  }
  webSocketClose(ws) { const o = this.other(ws); if (o) try { o.send('gone'); } catch (e) {} }
  webSocketError(ws) { this.webSocketClose(ws); }
}
export default {
  async fetch(req, env) {
    const u = new URL(req.url), m = u.pathname.match(/^\/r\/([0-9a-f]{16})$/);
    if (!m) return new Response('OPUlation relay. It introduces two phones and passes their sealed frames; it keeps nothing.\n', { headers: { 'content-type': 'text/plain' } });
    return env.ROOMS.get(env.ROOMS.idFromName(m[1])).fetch(req);
  },
};
