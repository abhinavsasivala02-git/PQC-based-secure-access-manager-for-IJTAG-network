q = 3329
RINV = pow(2, -16, q)

def br7(i):
    return int(f"{i:07b}"[::-1], 2)

R = 2285
zetas = [pow(17, br7(i), q) * R % q for i in range(128)]

def mont_mul(a, b):
    return (a * b * RINV) % q

def ntt(f):
    f = f[:]; k = 1; L = 128
    while L >= 2:
        for s in range(0, 256, 2 * L):
            z = zetas[k]; k += 1
            for j in range(s, s + L):
                t = mont_mul(z, f[j + L])
                f[j + L] = (f[j] - t) % q
                f[j] = (f[j] + t) % q
        L >>= 1
    return f

def intt(f):
    f = f[:]; k = 127; L = 2
    while L <= 128:
        for s in range(0, 256, 2 * L):
            z = zetas[k]; k -= 1
            for j in range(s, s + L):
                a = f[j]
                b = f[j + L]
                f[j] = (a + b) % q
                f[j + L] = mont_mul(z, (b - a) % q)
        L <<= 1
    return [mont_mul(x, 1441) for x in f]

def load(marker):
    txt = open("iso_out.txt", "rb").read()
    if txt[:2] in (b"\xff\xfe", b"\xfe\xff"):
        txt = txt.decode("utf-16")
    else:
        txt = txt.decode("utf-8", "ignore")
    lines = [l for l in txt.splitlines() if l.strip() != ""]
    for i, l in enumerate(lines):
        if marker in l:
            return [int(x, 16) for x in lines[i + 1].strip().split()]
    raise SystemExit(f"{marker} not found")

raw = [i % 7 for i in range(256)]
fwd = load("OUTPUT:")
rt = load("ROUNDTRIP:")

ref_fwd = ntt(raw)
ref_rt = intt(ref_fwd)
print("forward match:", sum(1 for a, b in zip(fwd, ref_fwd) if a == b), "/256")
print("roundtrip  match:", sum(1 for a, b in zip(rt, ref_rt) if a == b), "/256")
print("roundtrip==input:", sum(1 for a, b in zip(rt, raw) if a == b), "/256")