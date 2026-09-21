import hashlib, sys

src = open("ref_ct.py").read()
body = src.split("# ---- inputs ----")[0]
exec(body)  # defines q, ntt, intt, frommont, basemul, sntt, cbd2, bd12, compress_d, byte_encode

mem = [int(x, 16) for x in open("kat_pk.mem").read().split()]
ek = bytes(mem[0:1152]); rho = bytes(mem[1152:1184])
r = bytes([int(x, 16) for x in open("kat_r.mem").read().split()])
m = bytes([int(x, 16) for x in open("kat_msg.mem").read().split()])

rhat = [ntt(cbd2(hashlib.shake_256(r + bytes([i])).digest(256))) for i in range(3)]
e1 = [cbd2(hashlib.shake_256(r + bytes([3 + i])).digest(256)) for i in range(3)]

# fresh u[0]
uh = [0] * 256
for j in range(3):
    Aij = sntt(hashlib.shake_128(rho + bytes([j, 0])).digest(2000))
    b = basemul(Aij, rhat[j])
    uh = [(x + y) % q for x, y in zip(uh, b)]
u0 = [(x + e1[0][k]) % q for k, x in enumerate(frommont(intt(uh)))]
print("fresh u[0][0:3]:", [hex(x) for x in u0[:3]])
print("fresh A[0][0][0]:", hex(sntt(hashlib.shake_128(rho + bytes([0, 0])).digest(2000))[0]))
print("rho len:", len(rho), "r len:", len(r))
