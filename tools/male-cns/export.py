import pandas as pd, numpy as np, json
a = pd.read_feather('body-annotations-male-cns-v0.9-minconf-0.5.feather').set_index('bodyId')
nt = pd.read_feather('body-neurotransmitters-male-cns-v0.9.feather').set_index('body')
w = pd.read_parquet('w5.parquet')
role = {int(k): v for k, v in json.load(open('roles.json')).items()}
ids = sorted(role, key=lambda b: (['LC10a','vAB3','P1','DN','song','wingMN'].index(role[b]) if role[b] in ['LC10a','vAB3','P1','DN','song','wingMN'] else 2.5, b))
idx = {b: i for i, b in enumerate(ids)}
e = w[w.body_pre.isin(idx) & w.body_post.isin(idx)].copy()
SIGN = {'acetylcholine': 1, 'gaba': -1, 'glutamate': -1}
neurons = []
for b in ids:
    r = a.loc[b]; n = nt.loc[b] if b in nt.index else None
    t = (n.consensus_nt if n is not None and isinstance(n.consensus_nt, str) else (n.predicted_nt if n is not None else 'unknown'))
    loc = r.somaLocation if r.somaLocation is not None else r.tosomaLocation
    xyz = [int(v) for v in loc] if loc is not None and len(loc) == 3 else None
    neurons.append({'id': int(b), 'type': str(r.type), 'side': str(r.somaSide) if isinstance(r.somaSide, str) else '', 'role': role[b], 'nt': t, 'sign': SIGN.get(t, 0.3),
                    'superclass': str(r.superclass), 'xyz': xyz, 'syn': str(r.synonyms) if isinstance(r.synonyms, str) else ''})
# positions for neurons without a soma: the mean of their partners' somata
P = {i: n['xyz'] for i, n in enumerate(neurons) if n['xyz']}
for it in range(3):
    for i, n in enumerate(neurons):
        if n['xyz']: continue
        ps = [P[idx[o]] for o in list(e[e.body_pre == n['id']].body_post) + list(e[e.body_post == n['id']].body_pre) if idx[o] in P]
        if ps: P[i] = [int(np.mean([p[k] for p in ps])) for k in range(3)]
for i, n in enumerate(neurons): n['xyz'] = P.get(i)
E = np.stack([e.body_pre.map(idx).values, e.body_post.map(idx).values, e.weight.values], 1).astype(np.int32)
print(len(neurons), len(E), 'no position:', sum(1 for n in neurons if not n['xyz']))
print(pd.Series([n['nt'] for n in neurons]).value_counts().to_string())
json.dump({'neurons': neurons}, open('male-nodes.json', 'w')); np.save('male-edges.npy', E)
