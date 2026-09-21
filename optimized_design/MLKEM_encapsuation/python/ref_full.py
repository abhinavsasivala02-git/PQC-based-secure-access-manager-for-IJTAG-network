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

def ntt(f):
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

def load(marker):
    txt = open("dbg_out.txt", "rb").read()
    if txt[:2] == b"\xff\xfe" or txt[:2] == b"\xfe\xff":
        txt = txt.decode("utf-16")
    else:
        txt = txt.decode("utf-8", "ignore")
    lines = txt.splitlines()
    for i, l in enumerate(lines):
        if marker in l:
            return [int(x, 16) for x in lines[i + 1].strip().split()]
    raise SystemExit(f"marker {marker} not found")

raw = load("CBD1 RAW")
dut = load("NTT1 DONE")
print("raw len:", len(raw), "dut len:", len(dut))
ref = ntt(raw)
bad = [(i, r, d) for i, (r, d) in enumerate(zip(ref, dut)) if r != d]
print(f"classic NTT r_hat[0]: {256-len(bad)}/256 match")
for i, r, d in bad[:10]:
    print(f"  [{i}] ref={r} dut={d}")