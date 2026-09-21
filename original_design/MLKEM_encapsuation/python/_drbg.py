from Crypto.Cipher import AES

class DrbgCtx:
    def __init__(self):
        self.reseed_counter = 0
        self.key = bytearray(32)
        self.ctr = bytearray(16)

    def inc(self):
        for i in range(16):
            j = 15 - i
            if self.ctr[j] == 0xFF:
                self.ctr[j] = 0
            else:
                self.ctr[j] = self.ctr[j] + 1
                break

    def process_aes_block(self):
        e = AES.new(bytes(self.key), AES.MODE_ECB)
        return e.encrypt(bytes(self.ctr))

    def update(self, seed):
        t = bytearray(48)
        for i in range(3):
            self.inc()
            t[i*16:(i+1)*16] = self.process_aes_block()
        for i in range(len(seed)):
            t[i] ^= seed[i]
        self.key = t[0:32]
        self.ctr = t[32:48]

    def init(self, entropy, diversifier=b""):
        m = bytearray(entropy[:48])
        if len(diversifier) >= 48:
            for i in range(48):
                m[i] ^= diversifier[i]
        self.key = bytearray(32)
        self.ctr = bytearray(16)
        self.update(bytes(m))
        self.reseed_counter = 1

    def get_random(self, n):
        data = bytearray()
        l = n
        while l > 0:
            self.inc()
            b = self.process_aes_block()
            take = min(l, 16)
            data += b[:take]
            l -= take
        self.update(b"")
        self.reseed_counter += 1
        return bytes(data)

if __name__ == "__main__":
    magic = bytes.fromhex("60496cd0a12512800a79161189b055ac3996ad24e578d3c5fc57c1e60fa2eb4e550d08e51e9db7b67f1a616681d9182d")
    drbg = DrbgCtx()
    drbg.init(magic, b"")
    entropy0 = drbg.get_random(48)
    kem = DrbgCtx()
    kem.init(entropy0, b"")
    z = kem.get_random(32)
    d = kem.get_random(32)
    msg = kem.get_random(32)
    print("z   :", z.hex())
    print("d   :", d.hex())
    print("msg :", msg.hex())
    print("match z   :", z.hex() == "f696484048ec21f96cf50a56d0759c448f3779752f0383d37449690694cf7a68")
    print("match d   :", d.hex() == "6dbbc4375136df3b07f7c70e639e223e177e7fd53b161b3f4d57791794f12624")
    print("match msg :", msg.hex() == "20a7b7e10f70496cc38220b944def699bf14d14e55cf4c90a12c1b33fc80ffff")
    kem.init(entropy0, b"")
    d_key = kem.get_random(32)
    z_key = kem.get_random(32)
    m_enc = kem.get_random(32)
    print("d_keygen:", d_key.hex())
    print("z_keygen:", z_key.hex())
    print("m_encap :", m_enc.hex())
