import re
exec(open("ref_rt.py").read().split("raw =")[0])

def br7(i): return int(f"{i:07b}"[::-1], 2)

# Test: for each delta position d, where does ntt->intt put the unit?
for d in [0, 1, 5, 128, 255]:
    f = [0] * 256
    f[d] = 1
    h = intt(ntt(f))
    nz = [(i, v) for i, v in enumerate(h) if v != 0]
    print(f"delta@{d} ->", nz[:4])

# Also check the relationship ntt(intt) too
for d in [0, 1, 5]:
    f = [0] * 256
    f[d] = 1
    h = ntt(intt(f))
    nz = [(i, v) for i, v in enumerate(h) if v != 0]
    print(f"intt->ntt delta@{d} ->", nz[:4])