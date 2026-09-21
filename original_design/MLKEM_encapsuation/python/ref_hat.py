import hashlib, re

q = 3329

def load(tag):
    txt = open("dbg_out.txt", "rb").read()
    if txt[:2] in (b"\xff\xfe", b"\xfe\xff"):
        txt = txt.decode("utf-16")
    else:
        txt = txt.decode("utf-8", "ignore")
    lines = txt.splitlines()
    for i, l in enumerate(lines):
        if l.startswith(tag + " t="):
            return [int(x, 16) for x in lines[i + 1].strip().split()]
    raise SystemExit(f"marker {tag} not found")

def sntt(bs):
    b = bytearray(bs)
    out = []; i = 0
    while len(out) < 256:
        b0 = b[i]; b1 = b[i + 1]; b2 = b[i + 2]
        d1 = b0 | ((b1 & 0x0F) << 8)
        d2 = (b1 >> 4) | (b2 << 4)
        if d1 < q:
            out.append(d1)
        if d2 < q:
            out.append(d2)
        i += 3
    return out

mem = [int(x, 16) for x in open("kat_pk.mem").read().split()]
rho = bytes(mem[1152:1184])

def comp(tag, a, b):
    bad = sum(1 for x, y in zip(a, b) if x != y)
    print(f"{tag}: {len(a)-bad}/{len(a)}")

for (i, j) in [(0,0),(1,0),(0,1),(2,2),(1,2)]:
    A = load(f"A_{i}_{j}")
    comp(f"A[{i}][{j}] rho||j||i ", sntt(hashlib.shake_128(rho + bytes([j,i])).digest(2000)), A)
    comp(f"A[{i}][{j}] rho||i||j ", sntt(hashlib.shake_128(rho + bytes([i,j])).digest(2000)), A)

def br7(i): return int(f"{i:07b}"[::-1], 2)
zetas = [pow(17, br7(i), q) for i in range(128)]
RINV = pow(2, -16, q)

def mont_mul(a, b): return (a * b * RINV) % q

def ntt(f):
    f = f[:]; k = 1; L = 128
    while L >= 2:
        for s in range(0, 256, 2 * L):
            z = pow(17, br7(k), q) * 2285 % q; k += 1
            for j in range(s, s + L):
                t = mont_mul(z, f[j + L])
                f[j + L] = (f[j] - t) % q
                f[j] = (f[j] + t) % q
        L >>= 1
    return f

# t_hat: NTT(ByteDecode_12(ek[0:1152]))
def bd12(bs):
    bits = ''.join(f"{b:08b}"[::-1] for b in bs)
    return [int(bits[12*i:12*i+12][::-1], 2) for i in range(256)]

that_all = load("THAT ALL")
ek = bytes(mem[0:1152])
for r in range(3):
    t = bd12(ek[r*384:(r+1)*384])
    comp(f"t_hat[{r}] == NTT(decode12)", ntt(t), that_all[r*256:(r+1)*256])
