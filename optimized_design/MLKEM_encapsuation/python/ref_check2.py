import re

q = 3329
RINV = pow(2, -16, q)

# --- zetas from ROM ---
rom = []
for line in open(r"pkg\ntt_rom.v", encoding="utf-8"):
    m = re.search(r"7'd(\d+):\s+zeta_comb\s*=\s*(-?16'sd)(\d+)", line)
    if m:
        rom.append((int(m.group(1)), -int(m.group(3)) if m.group(2).startswith("-") else int(m.group(3))))
zetas = [v % q for _, v in sorted(rom)]

def mont_mul(a, b):
    return (a * b * RINV) % q

def ntt_gen(f, k0=1):
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

def bitrev7(i):
    return int(f"{i:07b}"[::-1], 2)

raw_s = ("000 000 000 000 001 000 001 001 000 002 001 000 000 000 000 001 002 001 000 000 d00 001 d00 001 000 000 000 d00 d00 000 cff 000 000 001 000 cff d00 000 001 000 001 cff d00 001 002 001 d00 001 001 000 001 d00 d00 001 d00 001 d00 000 d00 001 001 001 d00 000 001 cff d00 000 000 000 d00 d00 000 001 001 000 cff d00 000 001 cff d00 cff 000 000 000 d00 000 000 d00 000 000 001 d00 000 000 001 001 000 000 000 000 000 000 001 001 d00 000 d00 001 001 d00 000 d00 d00 d00 d00 001 001 001 d00 002 001 000 d00 000 000 001 001 000 002 000 000 d00 000 000 cff d00 d00 d00 000 000 000 001 002 002 001 002 d00 d00 000 d00 001 d00 000 d00 d00 000 001 001 d00 d00 000 002 d00 000 000 d00 d00 001 cff 001 000 001 001 001 001 000 002 000 000 cff 000 cff 001 000 001 000 d00 000 002 000 001 000 000 001 002 001 000 000 d00 d00 cff d00 000 d00 d00 000 000 002 000 000 d00 000 d00 d00 001 000 000 cff 000 002 000 000 000 000 cff d00 cff 000 000 d00 000 002 000 001 cff d00 001 002 001 000 000 cff 000 000 001 000 000 000 001 d00 d00 001 001 000")
dut_s = ("cce 1f3 11f 545 b92 c3e 249 cf6 5cf 6c5 3ea 1c9 9d9 125 14e 998 087 81c 9bb 533 398 0e0 798 8d5 1c8 815 685 528 2d5 740 2ee 8af 7d3 c54 516 b4b 0a7 079 203 2ce 1e8 5e5 351 301 096 9d0 330 97a 3ee 869 036 555 1b9 0e0 084 5da a00 7e0 a04 7f4 6d5 769 ba7 88d 2b3 803 00e 2c4 6a2 c48 515 c9b a20 64b 0e6 02c af1 314 81a b34 5cf 9be c39 539 0fa 85b 3e6 3cd 4a6 3f5 468 a9b 2a9 6a1 a88 2fc 93d 1d0 520 2a5 c21 5c4 8de 571 549 a2d 948 a6c c87 b3a 549 9f2 a59 6a7 363 24a 7e7 1fd bbd 811 73e 812 57d 770 214 2ae 184 28e 900 443 198 762 7ce 84e 1cf 505 b7c 6a0 426 850 9ee 4da aa4 2bd 50a 817 1de 6f8 24a 1ee 21d 32a 472 612 057 bc1 34b c46 543 9e1 a6a 13b bba 7f0 51d 005 693 5ab 50b 445 b78 389 3ed 397 008 a0a 145 6c6 702 962 4ac 83b 8a4 1aa 233 7be 8a5 b24 495 bbf 225 41a aa4 06c bff 7f1 6ce 754 6f0 ac5 213 567 8be 8d5 11c 746 486 147 015 06e 511 bfb 181 9b9 bfc 4da 1a8 358 64f 984 926 0e0 21b 277 0a8 bd9 711 447 358 789 aae 006 286 037 a9a aa5 b41 30b ce5 293 bd0 0d2 c06 36b 277 a8f b1d 6dc c89 cdd 27e 2fe 766 b7d 96e 3d5")
raw = [int(x, 16) for x in raw_s.split()]
dut = [int(x, 16) for x in dut_s.split()]
assert len(raw) == 256 and len(dut) == 256

def perm_br(f):
    return [f[bitrev7(i)] for i in range(256)]

def perm_swap(f):
    # swap each pair (2i,2i+1)
    g = [0] * 256
    for i in range(0, 256, 2):
        g[i], g[i + 1] = f[i + 1], f[i]
    return g

def perm_halves(f):
    return f[128:] + f[:128]

candidates = {
    "plain": raw,
    "bitrev7": perm_br(raw),
    "pairswap": perm_swap(raw),
    "halves": perm_halves(raw),
    "br+swap": perm_swap(perm_br(raw)),
}
results = []
for name, inp in candidates.items():
    for k0 in (0, 1):
        ref = ntt_gen(inp, k0=k0)
        for oname, out in (("out-plain", ref), ("out-br", perm_br(ref)), ("out-swap", perm_swap(ref))):
            bad = sum(1 for a, b in zip(ref, dut) if a != b)
            results.append((bad, name, f"k0={k0}", oname))
results.sort()
for r in results[:12]:
    print(r)