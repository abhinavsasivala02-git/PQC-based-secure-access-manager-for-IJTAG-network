import hashlib
exec(open('ref_ct.py').read().split('# ---- inputs ----')[0])
from kyber_py.ml_kem import ML_KEM_768

for run in (1, 2):
    ky = ML_KEM_768
    stream = hashlib.shake_128().digest(64)
    d = stream[:32]
    rho, sigma = hashlib.sha3_512(d + bytes([3])).digest()[:32], hashlib.sha3_512(d + bytes([3])).digest()[32:]
    A_hat = ky._generate_matrix_from_seed(rho)
    s, _ = ky._generate_error_vector(sigma, 2, 0)
    e, _ = ky._generate_error_vector(sigma, 2, 3)
    s_hat = s.to_ntt(); e_hat = e.to_ntt()
    t_hat = A_hat @ s_hat + e_hat
    print('run %d: A[0,0][:4]=%s' % (run, [int(x) for x in A_hat[0,0].coeffs][:4]))
    print('run %d: s_hat[0][:4]=%s' % (run, [int(x) for x in s_hat[0,0].coeffs][:4]))
    print('run %d: e_hat[0][:4]=%s' % (run, [int(x) for x in e_hat[0,0].coeffs][:4]))
    print('run %d: t_hat[0][:4]=%s enc=%s' % (run, [int(x) for x in t_hat[0,0].coeffs][:4], t_hat.encode(12)[:8].hex()))

# mine for reference
stream = hashlib.shake_128().digest(64)
d = stream[:32]
rho, sigma = hashlib.sha3_512(d + bytes([3])).digest()[:32], hashlib.sha3_512(d + bytes([3])).digest()[32:]
shat = [ntt(cbd2(hashlib.shake_256(sigma + bytes([i])).digest(256))) for i in range(3)]
ehat = [ntt(cbd2(hashlib.shake_256(sigma + bytes([3+i])).digest(256))) for i in range(3)]
t = []
for i in range(3):
    th = [0]*256
    for j in range(3):
        Aij = sntt(hashlib.shake_128(rho + bytes([j, i])).digest(2000))
        b = basemul(Aij, shat[j]); th = [(x+y) % q for x, y in zip(th, b)]
    t.append([(x + ehat[i][k]) % q for k, x in enumerate(th)])
print('mine: s_hat[0][:4]=%s' % shat[0][:4])
print('mine: e_hat[0][:4]=%s' % ehat[0][:4])
print('mine: t[0][:4]=%s enc=%s' % (t[0][:4], byte_encode(t[0], 12)[:8].hex()))