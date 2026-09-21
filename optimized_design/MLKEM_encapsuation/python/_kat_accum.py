import hashlib
exec(open('ref_ct.py').read().split('# ---- inputs ----')[0])

def keygen(d: bytes) -> (bytes, bytes):
    rho_sigma = hashlib.sha3_512(d + bytes([3])).digest()
    rho, sigma = rho_sigma[:32], rho_sigma[32:]
    shat = [ntt(cbd2(hashlib.shake_256(sigma + bytes([i])).digest(256))) for i in range(3)]
    e = [ntt(cbd2(hashlib.shake_256(sigma + bytes([3 + i])).digest(256))) for i in range(3)]
    t_ntt = []
    for i in range(3):  # t = A . s + e  (A[row i][col j] = sntt(rho||j||i))
        th = [0]*256
        for j in range(3):
            Aij = sntt(hashlib.shake_128(rho + bytes([j, i])).digest(2000))
            b = basemul(Aij, shat[j]); th = [(x + y) % q for x, y in zip(th, b)]
        t_ntt.append([(x + e[i][k]) % q for k, x in enumerate(th)])
    t = [frommont(intt(x)) for x in t_ntt]
    ek = b''.join(byte_encode(x, 12) for x in t) + rho
    return ek, rho, sigma, t_ntt

def encaps(ek: bytes, m: bytes):
    rho = ek[1152:1184]
    h = hashlib.sha3_256(ek).digest()
    G = hashlib.sha3_512(m + h).digest()
    K, r = G[:32], G[32:64]
    that = [ntt(bd12(ek[384*i:384*(i+1)])) for i in range(3)]
    rhat = [ntt(cbd2(hashlib.shake_256(r + bytes([i])).digest(256))) for i in range(3)]
    e1 = [cbd2(hashlib.shake_256(r + bytes([3+i])).digest(256)) for i in range(3)]
    e2 = cbd2(hashlib.shake_256(r + bytes([6])).digest(256))
    mu = [(1665 if ((m[i//8] >> (i%8)) & 1) else 0) for i in range(256)]
    u = []
    for i in range(3):
        uh = [0]*256
        for j in range(3):
            Aij = sntt(hashlib.shake_128(rho + bytes([i, j])).digest(2000))
            b = basemul(Aij, rhat[j]); uh = [(x + y) % q for x, y in zip(uh, b)]
        ui = frommont(intt(uh))
        u.append([(x + e1[i][k]) % q for k, x in enumerate(ui)])
    vh = [0]*256
    for j in range(3):
        b = basemul(that[j], rhat[j]); vh = [(x + y) % q for x, y in zip(vh, b)]
    v = frommont(intt(vh))
    v = [(x + e2[k] + mu[k]) % q for k, x in enumerate(v)]
    ct = b''
    for i in range(3):
        ct += byte_encode([compress_d(x, 10) for x in u[i]], 10)
    ct += byte_encode([compress_d(x, 4) for x in v], 4)
    return K, ct

# For a valid ciphertext, decaps returns K; for the random invalid ct1 it
# returns the implicit-rejection J(z || ct1) = SHAKE-256(z||ct1)[:32].
n = 100
stream = hashlib.shake_128().digest(n * 1184)
o = hashlib.shake_128()
for i in range(n):
    off = 1184 * i
    seed = stream[off:off+64]
    d, z = seed[:32], seed[32:]
    ek, rho, sigma, _ = keygen(d)
    o.update(ek)
    msg = stream[off+64:off+96]
    K, ct = encaps(ek, msg)
    o.update(ct); o.update(K)
    ct1 = stream[off+96:off+1184]
    K1 = hashlib.shake_256(z + ct1).digest(32)
    o.update(K1)
expected = "1114b1b6699ed191734fa339376afa7e285c9e6acf6ff0177d346696ce564415"
got = o.digest(32).hex()
print("n=100 accumulated:", got)
print("expected          :", expected)
print("MATCH" if got == expected else "MISMATCH")
