import re, io

q = 3329
R = 2285
RINV = pow(R, -1, q)

rom = []
for line in open(r"pkg\ntt_rom.v", encoding="utf-8"):
    m = re.search(r"7'd(\d+):\s+zeta_comb\s*=\s*(-?16'sd)(\d+)", line)
    if m:
        rom.append((int(m.group(1)), -int(m.group(3)) if m.group(2).startswith("-") else int(m.group(3))))
zetas = [v % q for _, v in sorted(rom)]
assert len(zetas) == 128

def mont_mul(a, b):
    return (a * b * RINV) % q

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

def frommont(f):
    return [mont_mul(x, 1) for x in f]

def basemul(A, B):
    out = [0]*256
    for p in range(128):
        a0, a1 = A[2*p], A[2*p+1]
        b0, b1 = B[2*p], B[2*p+1]
        gamma = zetas[(64 + p) & 127]
        m0 = mont_mul(a0, b0)
        m1 = mont_mul(mont_mul(a1, b1), gamma)
        out[2*p]   = (m0 + m1) % q
        out[2*p+1] = (mont_mul(a0, b1) + mont_mul(a1, b0)) % q
    return out

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

def comp(name, a, b):
    bad = sum(1 for x, y in zip(a, b) if x != y)
    print(f"{name}: {len(a)-bad}/{len(a)}")

def poly(tag):
    return load(tag)

# ---- inputs ----
A = [[poly(f"A_{i}_{j}") for j in range(3)] for i in range(3)]
rhat = [poly("RHAT ALL")[r*256:(r+1)*256] for r in range(3)]
that = [poly("THAT ALL")[r*256:(r+1)*256] for r in range(3)]
e1   = [poly("E1 ALL")[r*256:(r+1)*256] for r in range(3)]
e2mu = poly("E2MU")

u_hat = poly("U_HAT_0"); u_mont = poly("U_MONT_0")
u_fm = poly("U_FM_0");   u_final = poly("U_FINAL_0")
v_hat = poly("V_HAT");   v_mont = poly("V_MONT")
v_fm = poly("V_FM");     v_final = poly("V_FINAL")

# ---- 1. u_hat == sum_j basemul(A[0][j], rhat[j]) ----
ref_u_hat = [0]*256
for j in range(3):
    b = basemul(A[0][j], rhat[j])
    ref_u_hat = [(x + y) % q for x, y in zip(ref_u_hat, b)]
comp("u_hat == sum basemul", u_hat, ref_u_hat)

# ---- 2. intt / frommont / add for u ----
comp("u_mont == intt(u_hat)", u_mont, intt(u_hat))
comp("u_fm == frommont(u_mont)", u_fm, frommont(u_mont))
ref_u_final = [(x + e1[0][i]) % q for i, x in enumerate(u_fm)]
comp("u_final == u_fm + e1", u_final, ref_u_final)

# ---- 3. v chain ----
ref_v_hat = [0]*256
for j in range(3):
    b = basemul(that[j], rhat[j])
    ref_v_hat = [(x + y) % q for x, y in zip(ref_v_hat, b)]
comp("v_hat == sum basemul", v_hat, ref_v_hat)
comp("v_mont == intt(v_hat)", v_mont, intt(v_hat))
comp("v_fm == frommont(v_mont)", v_fm, frommont(v_mont))
ref_v_final = [(x + e2mu[i]) % q for i, x in enumerate(v_fm)]
comp("v_final == v_fm + e2+mu", v_final, ref_v_final)
