import json, numpy as np, pandas as pd
N = json.load(open('male-nodes.json'))['neurons']; E = np.load('male-edges.npy')
nt = pd.read_feather('body-neurotransmitters-male-cns-v0.9.feather').set_index('body')
a = pd.read_feather('body-annotations-male-cns-v0.9-minconf-0.5.feather')
SIGN = {'acetylcholine': 1, 'gaba': -1, 'glutamate': -1}
X = np.array([x['xyz'] for x in N], float)
zmin, zmax, xmin, xmax = 8000, 136000, 8000, 92000
def proj(p): return [round((p[2] - zmin) / (zmax - zmin), 4), round((p[0] - xmin) / (xmax - xmin), 4)]
out = []
for x in N:
    t = x['nt']
    if t == 'unclear' and x['id'] in nt.index: t = str(nt.loc[x['id']].predicted_nt) + '?'
    s = SIGN.get(t.rstrip('?'), 0.3)
    note = ''
    if x['role'] == 'vAB3': s, note = 1, 'glutamate, but excites P1 in recordings (Clowney et al. 2015)'
    g = x['role']
    if x['type'] in ('vPR6', 'dPR1', 'IN08B001'): g = 'pulse'
    elif x['type'].startswith('TN1a'): g = 'sine'
    elif x['type'] == 'pIP10': g = 'pIP10'
    elif g.startswith('via'): g = 'link'
    out.append({'id': x['id'], 'type': x['type'], 'role': x['role'], 'g': g, 'nt': t, 'sign': s, 'p': proj(x['xyz']), **({'note': note} if note else {}), **({'aka': x['syn']} if x['syn'] else {})})
# the whole CNS, faintly: a random sample of all somata
rng = np.random.default_rng(1); locs = [l for l in a.somaLocation if l is not None and len(l) == 3]
sel = rng.choice(len(locs), 9000, replace=False); back = [v for i in sel for v in proj(locs[i])]
back = [int(round(v * 255)) for v in back]
meta = {'about': 'His courtship-song circuit, cut from the Janelia male CNS connectome v0.9 (brain + nerve cord of one male; Berg et al. 2025). '
                 'Seeds: LC10a (seeing her), vAB3 (tasting her), P1, the song descending neurons pIP10, pMP2, DNp36 (pIP9), the song premotor neurons '
                 '(vPR6, dPR1, TN1a, vMS12, Lillvis et al. 2024 types) and the wing motor neurons; plus the strongest links between successive stages. '
                 'Edges: synapse counts >= 5 (minconf 0.5). Signs: predicted transmitter (ACh +, GABA -, Glu -; others +0.3).',
        'G': 3.0, 'tau': 0.03, 'n': len(out), 'edges': int(len(E)), 'neurons': out, 'back': back}
json.dump(meta, open('/home/claude/opulation/data/male.json', 'w'), separators=(',', ':'))
b = np.zeros((len(E), 3), np.uint16); b[:, 0] = E[:, 0]; b[:, 1] = E[:, 1]; b[:, 2] = np.minimum(E[:, 2], 65535)
b.tofile('/home/claude/opulation/data/male.bin')
print(len(out), len(E), pd.Series([o['g'] for o in out]).value_counts().to_dict())
