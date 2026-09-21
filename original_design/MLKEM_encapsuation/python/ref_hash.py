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

def cbd2(bs):
    # FIPS SamplePolyCBD_2: 128 bytes -> 256 coeffs, 4 bits each, little-endian
    bits = ''.join(f"{b:08b}"[::-1] for b in bs)
    out = []
    for i in range(256):
        w = bits[4*i:4*i+4]
        x = (int(w[0]) + int(w[1])) - (int(w[2]) + int(w[3]))
        out.append(x % q)
    return out

r = bytes([0x11]*32)

# r row 0: SHAKE-256(r || 0), 128 bytes
bs = hashlib.shake_256(r + bytes([0])).digest(128)
exp = cbd2(bs)
dut = load("CBD1 RAW")
bad = sum(1 for a, b in zip(exp, dut) if a != b)
print(f"r_hat[0] CBD vs hashlib: {256-bad}/256")

# e1 row 0: SHAKE-256(r || 3)
bs3 = hashlib.shake_256(r + bytes([3])).digest(128)
exp3 = cbd2(bs3)
e1 = load("E1 ALL")
dut_e1 = e1[0:256]
bad = sum(1 for a, b in zip(exp3, dut_e1) if a != b)
print(f"e1[0] CBD vs hashlib: {256-bad}/256")

# e2: SHAKE-256(r || 6)
bs6 = hashlib.shake_256(r + bytes([6])).digest(128)
exp6 = cbd2(bs6)
e2mu = load("E2MU")
# mu = Decompress_1(0) = 0 for all-zero message, so E2MU == e2
bad = sum(1 for a, b in zip(exp6, e2mu) if a != b)
print(f"e2 CBD vs hashlib (mu=0): {256-bad}/256")

# A[0][0]: SHAKE-128(rho || 0 || 0), FIPS SampleNTT
rho = load("")  # placeholder
