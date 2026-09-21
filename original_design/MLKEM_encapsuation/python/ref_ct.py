import hashlib, sys
sys.stdout.reconfigure(encoding="utf-8")

q = 3329
R = 2285
RINV = pow(R, -1, q)

def br7(i): return int(f"{i:07b}"[::-1], 2)
zetas = [pow(17, br7(i), q) * R % q for i in range(128)]

def mont_mul(a, b): return (a * b * RINV) % q

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
                a, b = f[j], f[j + L]
                f[j] = (a + b) % q
                f[j + L] = mont_mul(z, (b - a) % q)
        L <<= 1
    return [mont_mul(x, 1441) for x in f]

def frommont(f): return [mont_mul(x, 1) for x in f]

def basemul(A, B):
    out = [0]*256
    for p in range(128):
        a0, a1 = A[2*p], A[2*p+1]
        b0, b1 = B[2*p], B[2*p+1]
        gamma = zetas[(64 + p) & 127]
        out[2*p]   = (mont_mul(a0, b0) + mont_mul(mont_mul(a1, b1), gamma)) % q
        out[2*p+1] = (mont_mul(a0, b1) + mont_mul(a1, b0)) % q
    return out

def sntt(bs):
    b = bytearray(bs); out = []; i = 0
    while len(out) < 256:
        b0, b1, b2 = b[i], b[i+1], b[i+2]
        d1 = b0 | ((b1 & 0x0F) << 8)
        d2 = (b1 >> 4) | (b2 << 4)
        if d1 < q: out.append(d1)
        if d2 < q: out.append(d2)
        i += 3
    return out

def cbd2(bs):
    bits = ''.join(f"{b:08b}"[::-1] for b in bs[:128])
    out = []
    for i in range(256):
        w = bits[4*i:4*i+4]
        x = (int(w[0]) + int(w[1])) - (int(w[2]) + int(w[3]))
        out.append(x % q)
    return out

def bd12(bs):
    bits = ''.join(f"{b:08b}"[::-1] for b in bs)
    return [int(bits[12*i:12*i+12][::-1], 2) for i in range(256)]

def compress_d(x, d):
    return ((x << d) + 1664) // q & ((1 << d) - 1)

def byte_encode(coeffs, d):
    bits = ''.join(f"{c:0{d}b}"[::-1] for c in coeffs)
    return bytes(int(bits[8*i:8*i+8][::-1], 2) for i in range(len(bits)//8))

# ---- inputs ----
mem = [int(x, 16) for x in open("kat_pk.mem").read().split()]
ek = bytes(mem[0:1152]); rho = bytes(mem[1152:1184])
r = bytes([int(x, 16) for x in open("kat_r.mem").read().split()])
m = bytes([int(x, 16) for x in open("kat_msg.mem").read().split()])

that = [ntt(bd12(ek[384*i:384*(i+1)])) for i in range(3)]
rhat = [ntt(cbd2(hashlib.shake_256(r + bytes([i])).digest(256))) for i in range(3)]
e1 = [cbd2(hashlib.shake_256(r + bytes([3+i])).digest(256)) for i in range(3)]
e2 = cbd2(hashlib.shake_256(r + bytes([6])).digest(256))
frommsg = [(1665 if ((m[i // 8] >> (i % 8)) & 1) else 0) for i in range(256)]

# ---- u ----
u = []
for i in range(3):
    uh = [0]*256
    for j in range(3):
        Aij = sntt(hashlib.shake_128(rho + bytes([i, j])).digest(2000))
        b = basemul(Aij, rhat[j])
        uh = [(x + y) % q for x, y in zip(uh, b)]
    ui = frommont(intt(uh))
    u.append([(x + e1[i][k]) % q for k, x in enumerate(ui)])

# ---- v ----
vh = [0]*256
for j in range(3):
    b = basemul(that[j], rhat[j])
    vh = [(x + y) % q for x, y in zip(vh, b)]
v = frommont(intt(vh))
v = [(x + e2[k] + frommsg[k]) % q for k, x in enumerate(v)]

# ---- ct ----
ct = b""
for i in range(3):
    cu = [compress_d(x, 10) for x in u[i]]
    ct += byte_encode(cu, 10)
cv = [compress_d(x, 4) for x in v]
ct += byte_encode(cv, 4)

exp = bytes([int(x, 16) for x in open("kat_ct.mem").read().split()])
print("ref ct len:", len(ct))
print("ref vs NIST exp:", sum(1 for a, b in zip(ct, exp) if a == b), f"/{len(ct)}")
print("ref[0:8] :", ct[:8].hex())
print("exp[0:8] :", exp[:8].hex())

got = bytes([int(x, 16) for x in open("kat_got_ct.mem").read().split()])
print("ref vs design got:", sum(1 for a, b in zip(ct, got) if a == b), f"/{len(got)}")
print("got[0:8] :", got[:8].hex())
print("u-region bad vs got:", sum(1 for a, b in zip(ct[:960], got[:960]) if a != b))
print("v-region bad vs got:", sum(1 for a, b in zip(ct[960:], got[960:]) if a != b))
