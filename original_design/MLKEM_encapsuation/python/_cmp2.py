import hashlib
exec(open('ref_ct.py').read().split('# ---- inputs ----')[0])
from kyber_py.ml_kem import ML_KEM_768
ky = ML_KEM_768

stream = hashlib.shake_128().digest(64)
d = stream[:32]
rho, sigma = hashlib.sha3_512(d + bytes([3])).digest()[:32], hashlib.sha3_512(d + bytes([3])).digest()[32:]
A_hat = ky._generate_matrix_from_seed(rho)
m = b'\x01\x02\x03' + b'\x00'*29
r = bytes(range(32))

# kyber internal encrypt pieces
r_vec, _ = ky._generate_error_vector(r, 2, 0)
r_hat = r_vec.to_ntt()
e1, _ = ky._generate_error_vector(r, 2, 3)
e2, _ = ky._generate_error_vector(r, 3, 6)
# u: A^T @ r_hat + e1 ; A^T[i][j]=A[j][i]
u_hat = A_hat.T @ r_hat
# v part uses t_hat; here use t_hat loaded from standard ek
s, _ = ky._generate_error_vector(sigma, 2, 0)
e, _ = ky._generate_error_vector(sigma, 2, 3)
t_hat = (A_hat @ s.to_ntt() + e.to_ntt())

# mine rhat
rhat = [ntt(cbd2(hashlib.shake_256(r + bytes([i])).digest(256))) for i in range(3)]
out = []
out.append('ky r_hat[0][:4]=%s' % [int(x) for x in r_hat[0,0].coeffs][:4])
out.append('my rhat[0][:4] =%s' % rhat[0][:4])
out.append('r_hat match: %s' % ([int(x) for x in r_hat[0,0].coeffs] == rhat[0]))
# single product via kyber: A[0,0]*r_hat[0]
p = A_hat[0,0] * r_hat[0,0]
out.append('ky A[0,0]*rhat0[:4]=%s' % [int(x) for x in p.coeffs][:4])
# mine single basemul product A[0,0] with rhat0
A00 = sntt(hashlib.shake_128(rho + bytes([0,0])).digest(2000))
out.append('my basemul(A00,rhat0)[:4]=%s' % basemul(A00, rhat[0])[:4])
# kyber u_hat[0] = (A.T @ r_hat)[0]
out.append('ky u_hat[0][:4]=%s' % [int(x) for x in u_hat[0,0].coeffs][:4])
# mine u_hat[0]: sum_j basemul(A[0][j]?? transpose) 
#   A^T[i][j] = A[j][i] ; (A^T@r_hat)[i] = sum_j A^T[i][j]*r_hat[j] = sum_j A[j][i]*r_hat[j]
uh = [0]*256
for j in range(3):
    Aji = sntt(hashlib.shake_128(rho + bytes([i0:=0, j])).digest(2000))
    b = basemul(Aji, rhat[j]); uh = [(x+y) % q for x, y in zip(uh, b)]
out.append('my u_hat[0][:4]  =%s' % uh[:4])
open('_cmp2.txt','w').write('\n'.join(out))
print('done')