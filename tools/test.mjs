// node tools/test.mjs — the pairing protocol (and its cross-platform vectors), the face, both brains, the whole
// ritual between two simulated phones (including a man in the middle), and the relay.
import fs from 'fs';
await import('./load-sodium.mjs');
await sodium.ready; const S = sodium;
let fails = 0;
const ok = (c, m) => { if (!c) { fails++; console.log('FAIL', m); } else console.log('ok  ', m); };
export { ok, S };
if (process.argv[2] !== '--lib') {
  for (const f of ['./test-pair.mjs', './test-flycode.mjs', './test-male.mjs', './test-female.mjs', './test-e2e.mjs', './test-relay.mjs']) { const extra = await import(f); await extra.run(ok, S); }
  console.log(fails ? `${fails} FAILED` : 'all passed'); process.exit(fails ? 1 : 0);
}
