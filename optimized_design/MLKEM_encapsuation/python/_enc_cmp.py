import hashlib
exec(open('ref_ct.py').read().split('# ---- inputs ----')[0])
from kyber_py.ml_kem import ML_KEM_768

ky = ML_KEM_768
stream = hashlib.shake_128().digest(64)
d = stream[:32]
rho, sigma = hashlib.sha3_512(d + bytes([3])).digest()[:32], hashlib.sha3_512(d + bytes([3])).digest()[32:]
A_hat = ky._generate_matrix_from_seed(rho)
s, _ = ky._generate_error_vector(sigma, 2, 0)
e, _ = ky._generate_error_vector(sigma, 2, 3)
s_hat = s.to_ntt(); e_hat = e.to_ntt()
t_hat = A_hat @ s_hat + e_hat
ek = t_hat.encode(12) + rho

m = b'\x01\x02\x03' + b'\x00' * 29
r = bytes(range(32))
ct_ky = ky._k_pke_encrypt(ek, m, r)

# my full encrypt with THIS ek
h = hashlib.sha3_256(ek).digest(); G = hashlib.sha3_512(m + h).digest()
K_my, r_my = G[:32], G[32:64]
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
        b = basemul(Aij, rhat[j]); uh = [(x+y) % q for x, y in zip(uh, b)]
    ui = frommont(intt(uh)); u.append([(x + e1[i][k]) % q for k, x in enumerate(ui)])
vh = [0]*256
for j in range(3):
    b = basemul(that[j], rhat[j]); vh = [(x+y) % q for x, y in zip(vh, b)]
v = frommont(intt(vh)); v = [(x + e2[k] + mu[k]) % q for k, x in enumerate(v)]
ct_my = b''.join(byte_encode([compress_d(x,10) for x in ui],10) for ui in u) + byte_encode([compress_d(x,4) for x in v],4)

open('_enc_cmp.txt','w').write(''.join([
 'ek[0:8]        : %s\n' % ek[:8].hex(),
 'ct_ky[0:8]     : %s\n' % ct_ky[:8].hex(),
 'ct_my[0:8]     : %s\n' % ct_my[:8].hex(),
 'match          : %s\n' % (ct_ky == ct_my),
]))