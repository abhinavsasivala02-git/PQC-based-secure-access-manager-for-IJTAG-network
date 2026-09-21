import hashlib
from ref_std import keygen, encaps

q = 3329

stream = hashlib.shake_128().digest(1184)
d = stream[0:32]
m = stream[64:96]

ek, rho, sigma = keygen(d)
h = hashlib.sha3_256(ek).digest()
G = hashlib.sha3_512(m + h).digest()
K, r = G[:32], G[32:64]

Kv, ct = encaps(ek, m)

assert Kv == K, "K mismatch"

def wmem(name, data):
    with open(name, 'w') as f:
        for b in data:
            f.write(f"{b:02x}\n")

wmem('kat_pk.mem', ek)
wmem('kat_msg.mem', m)
wmem('kat_r.mem', r)
wmem('kat_ct.mem', ct)

print("d   :", d.hex())
print("m   :", m.hex())
print("rho :", rho.hex())
print("ek[0:8]:", ek[:8].hex())
print("r   :", r.hex())
print("ct[0:8]:", ct[:8].hex())
print("ct[1080:]:", ct[1080:].hex())
print("K   :", K.hex())
print("wrote kat_pk.mem kat_msg.mem kat_r.mem kat_ct.mem")
