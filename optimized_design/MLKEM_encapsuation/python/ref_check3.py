import re
exec(open("ref_check2.py").read().split("candidates =")[0])

def mont(xs):
    return [(x * 2285) % q for x in xs]

raw = [int(x, 16) for x in raw_s.split()]
dut = [int(x, 16) for x in dut_s.split()]

for name, inp in [("plain", raw), ("bitrev7", perm_br(raw)), ("pairswap", perm_swap(raw))]:
    for k0 in (0, 1):
        ref = ntt_gen(inp, k0=k0)
        for tag, out in [("plain", ref), ("mont", mont(ref))]:
            bad = sum(1 for a, b in zip(out, dut) if a != b)
            if bad < 256:
                print(f"{name} k0={k0} {tag}: {256-bad}/256")
print("done")