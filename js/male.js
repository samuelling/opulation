// His courtship-song circuit, from a real male connectome: 978 neurons and 23,964 connections cut from Janelia's
// male CNS connectome (v0.9; brain and nerve cord of one male fly; tools/male-cns/ rebuilds data/male.*):
//   LC10a (275 cells, seeing her)  and  vAB3 (tasting her pheromone through his forelegs)
//     -> P1 (148 cells, the courtship decision hub)
//     -> the song descending neurons: pIP10, pMP2, pIP9 (DNp36)
//     -> the song premotor network of the nerve cord: vPR6 and dPR1 (pulse), TN1a (sine), vMS12, and the other
//        types Lillvis et al. (2024) traced in MANC
//     -> 67 wing motor neurons
//   plus the 380 neurons that link successive stages most strongly, wherever they are.
// Wiring and synapse counts are the connectome's; signs come from predicted transmitters (ACh +, GABA and
// glutamate -), except vAB3, whose glutamate excites P1 in recordings (Clowney et al. 2015). Dynamics are a
// plain rate model with one gain and one time constant, set by hand, as in FlyHarp: not fit to physiology.
// Two things are imposed rather than emergent: his eye drives LC10a (js/eye.js's frontal OFF/motion read), and
// the song's timing (each pulse, each hum) comes from the key (js/song.js) and is fed into the pulse and sine
// premotor neurons, scaled by how active pIP10 is. A rate model can't make the song's rhythm; real males make it
// in nerve-cord circuits we can't yet simulate. Everything between those is the connectome's own.
// Floating point is fine here: nothing about the handshake depends on these numbers.
export const GROUPS = [
  { g: 'LC10a', label: 'LC10a', role: 'sees her', col: '79,179,164' },
  { g: 'vAB3', label: 'vAB3', role: 'tastes her', col: '143,127,214' },
  { g: 'P1', label: 'P1', role: 'decides to court', col: '255,104,186' },
  { g: 'pIP10', label: 'pIP10', role: 'commands song', col: '255,181,71' },
  { g: 'pulse', label: 'vPR6 · dPR1', role: 'pulse song', col: '255,210,63' },
  { g: 'sine', label: 'TN1a', role: 'sine song', col: '255,150,90' },
  { g: 'wingMN', label: 'wing MNs', role: 'sings', col: '255,236,200' },
];
const OTHER = { link: '200,170,190', DN: '255,181,71', song: '255,190,110' };
export class MaleCircuit {
  constructor() {
    this.a = { LC10a: 0, vAB3: 0, P1: 0, pIP10: 0, dPR1: 0, vPR6: 0, TN1A: 0, wing: 0 }; this.meta = null;
    this.ready = (async () => {
      const [m, b] = await Promise.all([fetch(new URL('../data/male.json', import.meta.url)).then(r => r.json()), fetch(new URL('../data/male.bin', import.meta.url)).then(r => r.arrayBuffer())]);
      const n = m.n, e = new Uint16Array(b), E = e.length / 3, tot = new Float32Array(n);
      for (let k = 0; k < E; k++) tot[e[3 * k + 1]] += e[3 * k + 2];
      // incoming weights, normalised by each neuron's total input, signed by the sender
      this.pre = new Uint16Array(E); this.post = new Uint16Array(E); this.w = new Float32Array(E);
      for (let k = 0; k < E; k++) { const p = e[3 * k], q = e[3 * k + 1]; this.pre[k] = p; this.post[k] = q; this.w[k] = m.neurons[p].sign * e[3 * k + 2] / Math.max(1, tot[q]); }
      this.r = new Float32Array(n); this.u = new Float32Array(n); this.ext = new Float32Array(n);
      this.groups = {}; m.neurons.forEach((x, i) => (this.groups[x.g] ||= []).push(i));
      this.meta = m; return this;
    })();
  }
  /** dt seconds; sees, tastes: 0..1; pulse: a pulse began this step; hum: sine song now */
  step(dt, { sees = 0, tastes = 0, singing = false, pulse = false, hum = false }) {
    if (!this.meta) return this.a;
    const { G, tau } = this.meta, n = this.meta.n, gr = this.groups, r = this.r, u = this.u, ext = this.ext;
    const steps = Math.min(40, Math.max(1, Math.round(dt / 0.005))), h = dt / steps;
    for (let s = 0; s < steps; s++) {
      ext.fill(0);
      for (const i of gr.LC10a) ext[i] = sees * 0.9;
      for (const i of gr.vAB3) ext[i] = tastes;
      const drive = Math.max(0.3, this.a.pIP10);           // the song's timing, fed in where the nerve cord would make it
      if (singing && pulse && s === 0) for (const i of gr.pulse) ext[i] = 3 * drive;
      if (singing && hum) for (const i of gr.sine) ext[i] = 0.9 * drive;
      u.fill(0); for (let k = 0; k < this.w.length; k++) u[this.post[k]] += this.w[k] * r[this.pre[k]];
      for (let i = 0; i < n; i++) { const x = G * u[i] + ext[i]; r[i] += (h / tau) * (-r[i] + (x > 0 ? Math.tanh(x) : 0)); }
    }
    const mean = (g) => { const ix = gr[g] || []; let s = 0; for (const i of ix) s += r[i]; return ix.length ? s / ix.length : 0; };
    const a = this.a; a.LC10a = mean('LC10a'); a.vAB3 = mean('vAB3'); a.P1 = mean('P1'); a.pIP10 = mean('pIP10');
    a.vPR6 = a.dPR1 = mean('pulse'); a.TN1A = mean('sine'); a.wing = Math.min(1, 1.6 * mean('wingMN'));
    return a;
  }
  /** his CNS lying on its side (brain left, nerve cord right), every neuron of the circuit lit by its activity */
  draw(c) {
    const g = c.getContext('2d'), W = c.width, H = c.height; g.fillStyle = '#12040c'; g.fillRect(0, 0, W, H);
    if (!this.meta) return;
    const m = this.meta, X = (p) => 18 + p[0] * (W - 36), Y = (p) => 14 + p[1] * (H - 28);
    if (!this.bg || this.bg.width !== W || this.bg.height !== H) {   // the whole CNS, faintly (a sample of every soma), drawn once
      this.bg = document.createElement('canvas'); this.bg.width = W; this.bg.height = H; const bg = this.bg.getContext('2d');
      bg.fillStyle = 'rgba(243,227,211,.08)'; const b = m.back; for (let i = 0; i < b.length; i += 2) bg.fillRect(X([b[i] / 255]), Y([0, b[i + 1] / 255]), 1.4, 1.4);
    }
    g.drawImage(this.bg, 0, 0);
    const col = Object.fromEntries(GROUPS.map(x => [x.g, x.col]));
    m.neurons.forEach((x, i) => { const v = Math.min(1, this.r[i]), cc = col[x.g] || OTHER[x.g] || '220,200,210';
      g.fillStyle = `rgba(${cc},${0.18 + 0.82 * v})`; const rad = 1.3 + 3 * v; g.beginPath(); g.arc(X(x.p), Y(x.p), rad, 0, 7); g.fill(); });
    // labels in fixed places, each with a leader to its cells (on the label's side of the midline, if it has any there)
    g.font = '600 12px system-ui, sans-serif'; g.textBaseline = 'middle';
    const spot = { LC10a: [0.30, 0.07], P1: [0.31, 0.33], pIP10: [0.31, 0.62], pulse: [0.50, 0.10], sine: [0.47, 0.90], wingMN: [0.70, 0.90], vAB3: [0.80, 0.10] };
    const act = { LC10a: this.a.LC10a, vAB3: this.a.vAB3, P1: this.a.P1, pIP10: this.a.pIP10, pulse: this.a.vPR6, sine: this.a.TN1A, wingMN: this.a.wing };
    for (const G of GROUPS) {
      const all = this.groups[G.g]; if (!all) continue; const [fx, fy] = spot[G.g], top = fy < 0.5;
      const side = all.filter(i => (m.neurons[i].p[1] < 0.5) === top), ix = side.length ? side : all;
      let sx = 0, sy = 0; for (const i of ix) { sx += X(m.neurons[i].p); sy += Y(m.neurons[i].p); }
      const cx = sx / ix.length, cy = sy / ix.length, lx = fx * W, ly = fy * H, v = Math.min(1, act[G.g] * 1.5);
      g.strokeStyle = `rgba(${G.col},.45)`; g.lineWidth = 1; g.beginPath(); g.moveTo(cx, cy); g.lineTo(lx, ly); g.stroke();
      g.fillStyle = `rgba(${G.col},${0.55 + 0.45 * v})`; g.fillText(`${G.label} · ${G.role}`, lx + 3, ly);
    }
    g.fillStyle = 'rgba(243,227,211,.35)'; g.font = '11px system-ui, sans-serif'; g.fillText('brain', 18, H - 10); g.fillText('nerve cord →', W * 0.62, H - 10);
  }
}
