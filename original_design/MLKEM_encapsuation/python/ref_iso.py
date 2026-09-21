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

def ntt(f, k0=1):
    f = f[:]
    k = k0
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

raw = [i % 7 for i in range(256)]

def load_hex_line(marker):
    txt = open("iso_out.txt", "rb").read()
    if txt[:2] == b"\xff\xfe" or txt[:2] == b"\xfe\xff":
        txt = txt.decode("utf-16")
    else:
        txt = txt.decode("utf-8", "ignore")
    tl = txt.splitlines()
    for i, line in enumerate(tl):
        if marker in line:
            return [int(x, 16) for x in tl[i + 1].strip().split()]
    raise SystemExit(f"marker {marker} not found")

dut = load_hex_line("OUTPUT:")
assert len(dut) == 256

for k0 in (0, 1):
    ref = ntt(raw, k0=k0)
    bad = [(i, r, d) for i, (r, d) in enumerate(zip(ref, dut)) if r != d]
    print(f"k0={k0}: {256-len(bad)}/256 match")
    if bad:
        for i, r, d in bad[:6]:
            print(f"  [{i}] ref={r} dut={d}")