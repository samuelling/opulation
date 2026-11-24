// node tools/run-one.mjs ./test-flycode.mjs — run one test module on its own
await import('./load-sodium.mjs'); await sodium.ready;
let bad = 0; const m = await import(process.argv[2]);
await m.run((c, n) => { console.log(c ? 'ok  ' : 'FAIL', n); if (!c) bad++; }, sodium);
process.exit(bad ? 1 : 0);
