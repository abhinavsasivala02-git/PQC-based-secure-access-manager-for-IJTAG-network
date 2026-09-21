q, R = 3329, 2285
RINV = pow(R, -1, q)

def br7(i): return int(f"{i:07b}"[::-1], 2)
zetas = [pow(17, br7(i), q) * R % q for i in range(128)]

def fqmul(a, b): return a * b % q * RINV % q

def ntt(f):
    r = f[:]; k = 1; L = 128
    while L >= 2:
        for start in range(0, 256, 2 * L):
            z = zetas[k]; k += 1
            for j in range(start, start + L):
                t = fqmul(z, r[j + L])
                r[j + L] = (r[j] - t) % q
                r[j] = (r[j] + t) % q
        L >>= 1
    return r

def intt(r):
    k = 127; L = 2
    while L <= 128:
        for start in range(0, 256, 2 * L):
            z = zetas[k]; k -= 1
            for j in range(start, start + L):
                a = r[j]
                b = r[j + L]
                r[j] = (a + b) % q
                r[j + L] = fqmul(z, (b - a) % q)
        L <<= 1
    return [fqmul(v, 1441) for v in r]

f = [i % 7 for i in range(256)]
h = intt(ntt(f))
print("intt∘ntt == input:", sum(1 for a, b in zip(h, f) if a == b))
print("first 8 h:", h[:8])
print("first 8 f:", f[:8])