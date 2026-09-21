import hashlib
exec(open('ref_ct.py').read().split('# ---- inputs ----')[0])

stream = hashlib.shake_128().digest(1184)
seed = stream[:64]
d, z = seed[:32], seed[32:]
msg = stream[64:96]
ct1 = stream[96:1184]

rho_sigma = hashlib.sha3_512(d + bytes([3])).digest()
rho, sigma = rho_sigma[:32], rho_sigma[32:]
shat = [ntt(cbd2(hashlib.shake_256(sigma + bytes([i])).digest(256))) for i in range(3)]
e = [ntt(cbd2(hashlib.shake_256(sigma + bytes([3 + i])).digest(256))) for i in range(3)]
t_ntt = []
for i in range(3):
    th = [0]*256
    for j in range(3):
        Aij = sntt(hashlib.shake_128(rho + bytes([j, i])).digest(2000))
        b = basemul(Aij, shat[j]); th = [(x + y) % q for x, y in zip(th, b)]
    t_ntt.append([(x + e[i][k]) % q for k, x in enumerate(th)])
t = [frommont(intt(x)) for x in t_ntt]
ek = b''.join(byte_encode(x, 12) for x in t) + rho

h = hashlib.sha3_256(ek).digest()
G = hashlib.sha3_512(msg + h).digest()
K, r = G[:32], G[32:64]
that = [ntt(bd12(ek[384*i:384*(i+1)])) for i in range(3)]
rhat = [ntt(cbd2(hashlib.shake_256(r + bytes([i])).digest(256))) for i in range(3)]
e1 = [cbd2(hashlib.shake_256(r + bytes([3+i])).digest(256)) for i in range(3)]
e2 = cbd2(hashlib.shake_256(r + bytes([6])).digest(256))
mu = [(1665 if ((msg[i//8] >> (i%8)) & 1) else 0) for i in range(256)]
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
ct = b''.join(byte_encode([compress_d(x, 10) for x in ui], 10) for ui in u)
ct += byte_encode([compress_d(x, 4) for x in v], 4)
k1 = hashlib.shake_256(z + ct1).digest(32)

go_ek = bytes.fromhex('7820320230238e447acfa99b6332b7531c7ce542031b93ca14258f5f98b30c87')
go_ct = bytes.fromhex('1d3be04a6a14b498')
go_K = bytes.fromhex('fe627621fe296186fce32243dd554bdda38971b47f18461f21323782dfe5ff89')
go_k1 = bytes.fromhex('b877da792d89f28049b590121601202d2bc8f5f1af8382bf4f3941050dd5172b')
print('rho settle:', rho.hex()[:16], 'go ek rho:', go_ek[-16:].hex() if False else '')
print('my ek[0:8] :', ek[:8].hex())
print('go ek[0:8] :', go_ek[:8].hex())
print('ek headmatch:', ek[:16] == go_ek)
print('ct match:', ct == go_ct, ' my ct[0:8]:', ct[:8].hex())
print('K match:', K == go_K)
print('k1 match:', k1 == go_k1)
print('rho from go ek? G(d||3)[:32]=', rho.hex()[:16])