import hashlib
exec(open('ref_ct.py').read().split('# ---- inputs ----')[0])
from kyber_py.ml_kem import ML_KEM_768
ky = ML_KEM_768

stream = hashlib.shake_128().digest(64)
d = stream[:32]
rho, sigma = hashlib.sha3_512(d + bytes([3])).digest()[:32], hashlib.sha3_512(d + bytes([3])).digest()[32:]

# --- kyber-py path ---
A_hat = ky._generate_matrix_from_seed(rho)
s, _ = ky._generate_error_vector(sigma, 2, 0)
e, _ = ky._generate_error_vector(sigma, 2, 3)
s_hat = s.to_ntt(); e_hat = e.to_ntt()
t_hat = A_hat @ s_hat + e_hat
kt_coeffs = [int(x) for x in t_hat[0, 0].coeffs]
ky_enc = t_hat.encode(12)
ky_enc_fromntt = t_hat.from_ntt().encode(12)

# --- mine ---
shat = [ntt(cbd2(hashlib.shake_256(sigma + bytes([i])).digest(256))) for i in range(3)]
ehat = [ntt(cbd2(hashlib.shake_256(sigma + bytes([3+i])).digest(256))) for i in range(3)]
def sntt(rho, j, i):
    b = bytearray(hashlib.shake_128(rho + bytes([j, i])).digest(2000)); out = []; k = 0
    while len(out) < 256:
        b0, b1, b2 = b[k], b[k+1], b[k+2]
        x = b0 | ((b1 & 0x0F) << 8); y = (b1 >> 4) | (b2 << 4)
        if x < 3329: out.append(x)
        if y < 3329: out.append(y)
        k += 3
    return out
t = []
for i in range(3):
    th = [0]*256
    for j in range(3):
        Aij = sntt(rho, j, i); b = basemul(Aij, shat[j]); th = [(x+y) % q for x, y in zip(th, b)]
    t.append([(x + ehat[i][k]) % q for k, x in enumerate(th)])

out = []
out.append('ky t_hat[0,0][:6]   : %s' % kt_coeffs[:6])
out.append('ky .encode(12)[:8]  : %s' % ky_enc[:8].hex())
out.append('ky .from_ntt()[:6]  : %s' % [int(x) for x in t_hat[0,0].from_ntt().coeffs][:6])
out.append('ky from_ntt enc[:8] : %s' % ky_enc_fromntt[:8].hex())
out.append('my t[0][:6]         : %s' % t[0][:6])
out.append('my byte_encode[:8]  : %s' % byte_encode(t[0], 12)[:8].hex())
open('_enc_out.txt', 'w').write('\n'.join(out))
print('done')