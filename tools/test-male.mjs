// His circuit from the male CNS connectome: seeing and tasting her drive P1, P1 drives pIP10, and song drives the wing.
import { readFileSync } from 'node:fs';
export async function run(ok) {
  globalThis.fetch = async (u) => { const b = readFileSync(new URL(u)); return { json: async () => JSON.parse(b), arrayBuffer: async () => b.buffer.slice(b.byteOffset, b.byteOffset + b.length) }; };
  const { MaleCircuit } = await import('../js/male.js');
  const run = async (sees, tastes, sing) => { const c = new MaleCircuit(); await c.ready; let t = 0;
    for (let k = 0; k < 300; k++) { t += 0.005; c.step(0.005, { sees, tastes, singing: sing, pulse: sing && k % 7 === 0, hum: false }); } return { ...c.a, n: c.meta.n }; };
  const rest = await run(0, 0, false), look = await run(1, 0, false), taste = await run(0, 1, false), song = await run(1, 1, true);
  console.log(`     ${rest.n} neurons; P1 at rest ${rest.P1.toFixed(2)}, seeing her ${look.P1.toFixed(2)}, tasting her ${taste.P1.toFixed(2)}; pIP10 ${song.pIP10.toFixed(2)}; wing ${rest.wing.toFixed(2)} -> ${song.wing.toFixed(2)} singing`);
  ok(rest.P1 < 0.01 && rest.wing < 0.01, 'his circuit is quiet with nothing to court');
  ok(look.P1 > 0.2 && taste.P1 > 0.2, 'seeing her (LC10a) or tasting her (vAB3) wakes P1, through the connectome');
  ok(look.pIP10 > 0.2, 'P1 drives pIP10, the song command, through the connectome');
  ok(song.wing > look.wing, 'singing drives his wing motor neurons');
}
