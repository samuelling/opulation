import pandas as pd, numpy as np, json
a = pd.read_feather('body-annotations-male-cns-v0.9-minconf-0.5.feather')
w = pd.read_parquet('w5.parquet')
T = a.type.astype(str); syn = a.synonyms.astype(str)
role = {}
def put(mask, r):
    for b in a.bodyId[mask]: role.setdefault(int(b), r)
put(T.str.fullmatch('LC10a'), 'LC10a')
put(syn.str.contains('vAB3'), 'vAB3')
put(T.str.match(r'^P1_'), 'P1')
put(T.isin(['pIP10', 'pMP2', 'DNp36']), 'DN')
put(T.isin(['vPR6', 'dPR1']) | T.str.match(r'^TN1a') | T.str.match(r'^vMS12') | syn.str.contains('Lillvis 2024'), 'song')
put((a.superclass == 'vnc_motor') & (a.subclass == 'wm'), 'wingMN')
from collections import Counter; print(Counter(role.values()))
stages = ['LC10a', 'vAB3', 'P1', 'DN', 'song', 'wingMN']
S = {r: set(b for b, x in role.items() if x == r) for r in stages}
pre_by = w.groupby('body_pre'); 
def bridges(A, B, n):
    i = w[w.body_pre.isin(A)].groupby('body_post').weight.sum()
    o = w[w.body_post.isin(B)].groupby('body_pre').weight.sum()
    j = pd.concat([i.rename('i'), o.rename('o')], axis=1).dropna()
    j = j[~j.index.isin(role.keys())]
    j['s'] = np.minimum(j.i, j.o); return j.sort_values('s', ascending=False).head(n)
br = {}
for A, B, n in [('LC10a', 'P1', 60), ('vAB3', 'P1', 40), ('P1', 'DN', 80), ('DN', 'song', 80), ('song', 'wingMN', 80), ('DN', 'wingMN', 40)]:
    j = bridges(S[A], S[B], n); print(A, '->', B, len(j), 'top', j.s.head(3).tolist(), 'min', j.s.min() if len(j) else None)
    for b in j.index: role.setdefault(int(b), f'via {A}->{B}')
print(len(role))
json.dump({str(k): v for k, v in role.items()}, open('roles.json', 'w'))
