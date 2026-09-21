import re
exec(open("ref_rt.py").read().split("raw =")[0])

f = [i % 7 for i in range(256)]
g = ntt(f)
h = intt(g)
print("diff of h-f (first 8):", [(h[i] - f[i]) % q for i in range(8)])
print("unique ratios h/f for f!=0 (first 8):", [(i, h[i] * pow(f[i], -1, q) % q) for i in range(256) if f[i] != 0][:8])
perm_map = {}
for i in range(256):
    perm_map.get(h[i], set()).add(i)
# is h a permutation of f?
from collections import Counter
print("multiset equal:", Counter(h) == Counter(f))
# maybe h == perm applied to f: check h[bitrev]?
def br7(i): return int(f"{i:07b}"[::-1], 2)
h2 = [h[br7(i)] for i in range(256)]
print("h(bitrev) == f:", sum(1 for a,b in zip(h2, f) if a == b))
h3 = [f[br7(i)] for i in range(256)]
print("h == f(bitrev):", sum(1 for a,b in zip(h, h3) if a == b))