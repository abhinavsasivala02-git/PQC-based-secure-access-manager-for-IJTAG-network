import re
lines = open(r"pkg\ntt_rom.v", encoding="utf-8").readlines()
pat = re.compile(r"7'd(\d+):\s+zeta_comb = (-?16'sd)(\d+)")
hits = []
for l in lines:
    m = pat.search(l)
    if m:
        hits.append((int(m.group(1)), m.group(2), int(m.group(3))))
print("total hits:", len(hits))
print("first 5:", hits[:5])
found = {h[0] for h in hits}
missed = sorted(set(range(128)) - found)
print("missed idxs:", missed)
extra = sorted(found - set(range(128)))
print("out-of-range idxs:", extra)
# show a few raw lines that contain zeta_comb but did not match
zo = [l for l in lines if "zeta_comb" in l]
print("zeta_comb lines:", len(zo))
for l in zo[:3]:
    print(repr(l))