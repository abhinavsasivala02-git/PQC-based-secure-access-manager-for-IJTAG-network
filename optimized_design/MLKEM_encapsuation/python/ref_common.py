import re

q = 3329
RINV = pow(2, -16, q)

rom = []
for line in open(r"pkg\ntt_rom.v", encoding="utf-8"):
    m = re.search(r"7'd(\d+):\s+zeta_comb\s*=\s*(-?16'sd)(\d+)", line)
    if m:
        rom.append((int(m.group(1)), -int(m.group(3)) if m.group(2).startswith("-") else int(m.group(3))))
zetas = [v % q for _, v in sorted(rom)]
assert len(zetas) == 128

def mont_mul(a, b):
    return (a * b * RINV) % q

def ntt_classic(f):
    f = f[:]
    k = 1
    length = 128
    while length >= 2:
        for start in range(0, 256, 2 * length):
            zeta = zetas[k]; k += 1
            for j in range(start, start + length):
                t = mont_mul(zeta, f[j + length])
                f[j + length] = (f[j] - t) % q
                f[j] = (f[j] + t) % q
        length >>= 1
    return f

def ntt_fips(f):
    return ntt_classic-like via k0=0