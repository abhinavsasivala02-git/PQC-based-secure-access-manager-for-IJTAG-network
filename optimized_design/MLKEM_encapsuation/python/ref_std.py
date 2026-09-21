import hashlib

# ---------------------------------------------------------------------------
# ref_std.py — FIPS-203 ML-KEM-768 reference, EXACTLY mirroring
# Go crypto/internal/fips140/mlkem (plain arithmetic, Barrett mod q).
# Convention clues from cb-offline: all coefficients PLAIN (<q), no Montgomery.
# zetas[k] = 17^BR7(k) mod q ; gammas[p] = 17^(2*BR7(p)+1) mod q
# intt scales by 3303 = 128^-1 mod q.
# pk = ByteEncode_12(t_hat) || rho  (t_hat in NTT domain, SMALL)
# encaps uses t_hat = ByteDecode_12(ek) DIRECTLY (see gammas/BR7 note).
# ---------------------------------------------------------------------------

q = 3329
BR7 = [int(f"{i:07b}"[::-1], 2) for i in range(128)]
ZETAS = [pow(17, BR7[i], q) for i in range(128)]       # NTT butterflies
GAMMAS = [pow(17, 2 * BR7[i] + 1, q) for i in range(128)]  # basemul per pair
INTT_SCALE = 3303  # 128^-1 mod 3329


def ntt(f):
    f = list(f)
    k = 1
    L = 128
    while L >= 2:
        for s in range(0, 256, 2 * L):
            z = ZETAS[k]; k += 1
            for j in range(s, s + L):
                t = z * f[j + L] % q
                f[j + L] = (f[j] - t) % q
                f[j] = (f[j] + t) % q
        L >>= 1
    return f


def intt(f):
    f = list(f)
    k = 127
    L = 2
    while L <= 128:
        for s in range(0, 256, 2 * L):
            z = ZETAS[k]; k -= 1
            for j in range(s, s + L):
                a, b = f[j], f[j + L]
                f[j] = (a + b) % q
                f[j + L] = (z * (b - a)) % q
        L <<= 1
    return [(x * INTT_SCALE) % q for x in f]


def basemul(A, B):
    out = [0] * 256
    for p in range(128):
        g = GAMMAS[p]
        a0, a1 = A[2 * p], A[2 * p + 1]
        b0, b1 = B[2 * p], B[2 * p + 1]
        out[2 * p] = (a0 * b0 + g * a1 * b1) % q
        out[2 * p + 1] = (a1 * b0 + a0 * b1) % q
    return out


def sntt(rho, j, i):
    b = bytearray(hashlib.shake_128(rho + bytes([j, i])).digest(2000))
    out = []; k = 0
    while len(out) < 256:
        b0, b1, b2 = b[k], b[k + 1], b[k + 2]
        d1 = b0 | ((b1 & 0x0F) << 8)
        d2 = (b1 >> 4) | (b2 << 4)
        if d1 < q: out.append(d1)
        if d2 < q: out.append(d2)
        k += 3
    return out


def cbd2(bs):
    bits = ''.join(f"{b:08b}"[::-1] for b in bs[:128])
    out = []
    for i in range(256):
        w = bits[4 * i:4 * i + 4]
        out.append((int(w[0]) + int(w[1]) - int(w[2]) - int(w[3])) % q)
    return out


def bd12(bs):
    bits = ''.join(f"{b:08b}"[::-1] for b in bs)
    return [int(bits[12 * i:12 * i + 12][::-1], 2) for i in range(256)]


def compress_d(x, d):
    return ((x << d) + 1664) // q & ((1 << d) - 1)


def ddecompress(y, d):  # unneeded for encrypt, kept for completeness
    return (y * q + (1 << (d - 1))) >> d


def byte_encode(coeffs, d):
    bits = ''.join(f"{c:0{d}b}"[::-1] for c in coeffs)
    return bytes(int(bits[8 * i:8 * i + 8][::-1], 2) for i in range(len(bits) // 8))


def keygen(d):
    (rho, sigma) = hashlib.sha3_512(d + bytes([3])).digest()[:32], hashlib.sha3_512(d + bytes([3])).digest()[32:]
    shat = [ntt(cbd2(hashlib.shake_256(sigma + bytes([i])).digest(256))) for i in range(3)]
    e = [ntt(cbd2(hashlib.shake_256(sigma + bytes([3 + i])).digest(256))) for i in range(3)]
    t_hat = []
    for i in range(3):          # t_hat[i] = sum_j A[i][j] . s_hat[j] + e[i], A[i][j]=sntt(rho, j, i)
        th = [0] * 256
        for j in range(3):
            b = basemul(sntt(rho, j, i), shat[j]); th = [(x + y) % q for x, y in zip(th, b)]
        t_hat.append([(x + e[i][k]) % q for k, x in enumerate(th)])
    ek = b''.join(byte_encode(x, 12) for x in t_hat) + rho
    return ek, rho, sigma


def encaps(ek, m):
    rho = ek[1152:1184]
    h = hashlib.sha3_256(ek).digest()
    G = hashlib.sha3_512(m + h).digest()
    K, r = G[:32], G[32:64]
    t_hat = [bd12(ek[384 * i:384 * (i + 1)]) for i in range(3)]   # pk stores t_hat directly
    rhat = [ntt(cbd2(hashlib.shake_256(r + bytes([i])).digest(256))) for i in range(3)]
    e1 = [cbd2(hashlib.shake_256(r + bytes([3 + i])).digest(256)) for i in range(3)]
    e2 = cbd2(hashlib.shake_256(r + bytes([6])).digest(256))
    mu = [(1665 if ((m[i // 8] >> (i % 8)) & 1) else 0) for i in range(256)]
    u = []
    for i in range(3):          # u_hat[i] = sum_j A^T[i][j] . r_hat[j]; A^T[i][j]=sntt(rho, i, j)
        uh = [0] * 256
        for j in range(3):
            b = basemul(sntt(rho, i, j), rhat[j]); uh = [(x + y) % q for x, y in zip(uh, b)]
        ui = intt(uh)
        u.append([(x + e1[i][k]) % q for k, x in enumerate(ui)])
    vh = [0] * 256
    for j in range(3):
        b = basemul(t_hat[j], rhat[j]); vh = [(x + y) % q for x, y in zip(vh, b)]
    v = intt(vh)
    v = [(x + e2[k] + mu[k]) % q for k, x in enumerate(v)]
    ct = b''.join(byte_encode([compress_d(x, 10) for x in ui], 10) for ui in u)
    ct += byte_encode([compress_d(x, 4) for x in v], 4)
    return K, ct


if __name__ == "__main__":
    n = 100
    stream = hashlib.shake_128().digest(n * 1184)
    o = hashlib.shake_128()
    for i in range(n):
        off = 1184 * i
        seed = stream[off:off + 64]
        d, z = seed[:32], seed[32:]
        ek, rho, sigma = keygen(d)
        o.update(ek)
        msg = stream[off + 64:off + 96]
        K, ct = encaps(ek, msg)
        o.update(ct); o.update(K)
        ct1 = stream[off + 96:off + 1184]
        K1 = hashlib.shake_256(z + ct1).digest(32)
        o.update(K1)
        if i < 3:
            print(f"iter{i} ek[0:8]={ek[:8].hex()} ct[0:8]={ct[:8].hex()} K={K.hex()} k1={K1.hex()}")
    got = o.digest(32).hex()
    expected = "1114b1b6699ed191734fa339376afa7e285c9e6acf6ff0177d346696ce564415"
    print("accumulated:", got)
    print("expected   :", expected)
    print("MATCH" if got == expected else "MISMATCH")