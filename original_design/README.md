# PQC-Protected JTAG Unlock
### Integrated ML-KEM + ML-DSA Secure Design-for-Debug

A JTAG/IJTAG unlock mechanism protected with post-quantum cryptography:
**ML-KEM-768** (FIPS 203) encapsulation for session-key distribution,
**ML-DSA-65** (FIPS 204) signature verification for test-command
authentication, per-session SHAKE-256 stream encryption of the scan-chain
output, and a factory-provisioned OTP key store.

Companion paper: [`PQC-Based_Secure_Access_Manager_for_IJTAG_Network.pdf`](../PQC-Based_Secure_Access_Manager_for_IJTAG_Network.pdf).

---

## Results

Vivado XSim 2023.2, 100 MHz TCK, reset to `UNLOCKED`
(transcript: [`vivado_sim_3349us.log`](vivado_sim_3349us.log)):

| Phase | Cycles | Time | Paper (Sec. IV-C) |
|-------|--------|------|-------------------|
| OTP provisioning (testbench) | 3,186 | 32 µs | - |
| ML-KEM encapsulation (CT shifted out on TDO concurrently) | 49,656 | 497 µs | ~500 µs |
| 26,567-bit unlock frame shift-in | 26,567 | 266 µs | ~265 µs |
| ML-DSA-65 verification | 255,449 | 2,554 µs | 1.5-2.5 ms |
| **Total authentication latency** | **334,858** | **3.35 ms** | **~3.35 ms** |

Testbench result: **47 PASS**, `TB: PASS - ALL TEST CASES PASSED`.

| Configuration | ML-DSA verify | Total unlock |
|-------|---------------|--------------|
| Before this work | 3,329 µs | 4.94 ms |
| **This design** | **2,554 µs** | **3.35 ms** |
| Optimized design (companion folder) | 1,091 µs | 1.89 ms |

---

## This Design

This folder is the **original design**: the full authentication takes the
~3.35 ms reported in the paper. A companion folder, `optimized_design`, holds
the same RTL running at maximum throughput, 1.89 ms.

Both folders contain the same corrected, pipelined RTL and produce
bit-identical results; they are configured for different verification speeds.

---

## How It Works

```
    JTAG/IJTAG scan chain (TCK/TMS/TDI/TDO)
        |
        +--> boot-load (pk_reg, vksign, cluster key, inst, data)
        +--> ML-KEM encapsulate  ->  session KDF key
        +--> ML-DSA verify block ->  validates the unlock frame
        +--> priority decoder    ->  maps inst_idx -> priority & DONE
        +--> SHAKE-256 stream    ->  encrypts eligible cluster TDO output
        +--> OTP                 ->  irrevocable key_state latch
```

- **Provisioning:** the OTP is programmed and locked with `ek`, `vksign`, the
  cluster key, instrument select and data.
- **Unlock:** on a valid signature `key_state` is set to 1 irrevocably and
  survives reset.
- **Cluster selection:** `CLUS_SEL` picks cluster 0-3; high-priority
  instruments are encrypted on TDO, low-priority ones stay raw.
- **Replay resistance:** every unlock session latches a fresh TRNG IV, so
  keystreams differ across sessions.
- **Two-phase key protocol:** on the first reset (`key_state = 0`) the AM
  accepts the factory cluster key; afterwards every reset requires the
  TRNG-derived KDF key, so the factory key cannot be replayed.

### Shared Keccak-f[1600]

The design contains **one** Keccak permutation core
(`PQC_integrated/design/keccak_shared.v`). Six hash users arbitrate for it:

| User | Where |
|------|-------|
| H (SHA3-256), G (SHA3-512) | `mlkem_encaps.v` |
| PRF (SHAKE-256) | `kpke_encrypt.v` |
| SampleNTT (SHAKE-128) | `sample_ntt.v` |
| ML-DSA ExpandA + SHAKE-256 | `shake_unified.v` |
| TDO stream cipher | `shake_stream.v` |

They are mutually exclusive in time, exactly as the paper describes. Each user
keeps its own 1600-bit sponge state and requests a permutation; the arbiter
grants one at a time with fixed priority. Sharing costs about 0.3% latency.

### OTP Key Store

`otp.v` is a write-once memory provisioned at the factory:

| Address range | Contents |
|----------------|----------|
| `0x000-0x49F` | ML-KEM encapsulation key `ek` (1184 B) |
| `0x800-0xF9F` | ML-DSA verification key `vksign` (1952 B) |
| `0xFA0-0xFA3` | Cluster key (4 B) |
| `0xFA4-0xFB3` | Cluster unlock instructions (4 x 32 b) |
| `0xFB4-0xFC3` | Valid data patterns (4 x 31 b + pad) |

Once `prog_lock` is pulsed the memory is permanently write-protected, and
`key_state` is set-only.

### Access Manager FSM

`am_pqc.v` drives a 6-state Access Manager:

```
LOCK -> SIG_VERIFY -> KEY_COMP -> INSTN_COMP -> DATA_COMP -> UNLOCK
```

| State | Behaviour |
|-------|-----------|
| `SIG_VERIFY` | Full FIPS 204 verification (SHAKE-128 ExpandA, SHAKE-256, matrix NTT, hint check) gates the key compare via `SVAL` |
| `KEY_COMP` | `key_out == (key_state ? kdf_key : cluster_key)` |
| `INSTN_COMP` / `DATA_COMP` | Unlock instruction / data pattern compared against the OTP words |
| `DATA_COMP` (success) | `key_state` is set to 1 in the OTP |

---

## Running It

The testbench reads its `.mem` vectors from the current working directory when
compiled with `-d XSIM`, and from `../tb/` otherwise, so run the scripts from
the directories shown.

**Vivado XSim 2023.2** - full system testbench:

```
run_xsim.bat
```

Compiles `rtl_mldsa/`, `rtl_mlkem/`, `design/`, the `AM_ijtag/` chain and the
testbench, runs from `PQC_integrated\tb`, and leaves the transcript in
`PQC_integrated\tb\sim.log`. Edit the `settings64.bat` path if Vivado is not
on `D:`.

**Icarus Verilog** - same testbench:

```
cd PQC_integrated/run
run_iverilog.bat
```

**ML-KEM known-answer test** - 3 FIPS 203 vectors, ciphertext and shared secret:

```
cd PQC_integrated/tb/kem_kat
run_kem_kat.bat
```

**Xcelium:**

```
cd PQC_integrated/run
sh run_xrun.sh
```

Latency is fixed by the RTL cycle count and the 100 MHz clock - it does not
depend on the simulator. Icarus, XSim and Xcelium all report the same cycles.

---

## What the Testbench Covers

`PQC_integrated/tb/integrated_top_tb.v` is self-checking (47 checks):

| # | Scenario | Verified behaviour |
|---|----------|--------------------|
| 1 | Keccak / SHAKE-256 reference | Matches NIST vectors |
| 2 | OTP provisioning | Programmed and locked, contents match |
| 3 | Boot-load | `pk_reg` / `vksign` / key / inst / data latched |
| 4 | ML-KEM encaps | KDF key nonzero, 1,088-byte CT shifted out on TDO |
| 5 | Unlock frame (26,567-bit) | Genuine NIST signature -> UNLOCKED |
| 6 | Clusters 0-3 | Each selected, priority-based encryption |
| 7 | Key state | Irrevocable in OTP, persists across reset |
| 8 | Session replay | Fresh TRNG IV per session, no keystream reuse |
| 9 | Negative tests | Wrong signature / key / instruction / data stay LOCKED, TDO junk-masked |

The keystream is checked against an independent SHAKE-256 model inside the
testbench. Expected final line:

```
TB: PASS - ALL TEST CASES PASSED (provision, boot, KEM, unlock x4, encryption, priority decoder, IV replay, negatives)
```

Beyond the system testbench:

- **ML-KEM** is checked against the FIPS 203 reference by
  `PQC_integrated/tb/kem_kat/` (3 vectors, ciphertext **and** shared secret K).
  This is the only ML-KEM correctness gate, because the system testbench seeds
  encapsulation from the on-chip TRNG and so cannot compare against a fixed
  vector.
- **Both NTT rewrites** were diffed cycle-by-cycle against the original cores
  on random polynomials, forward and inverse: bit-identical.
- **ML-DSA verification** is exercised with the genuine NIST KAT signature
  (accepted) and a corrupted one (rejected).

---

## Fixes Applied to the Original RTL

**ML-KEM was not FIPS 203 compliant.** The H()/G() feed in `mlkem_encaps.v`
used a skewed valid/ready handshake, so SHA3-256 absorbed 1,185 bytes with
`ek[0]` repeated instead of 1,184 - giving a wrong `H(ek)`, and therefore wrong
`K` and `r`. A second unrequested "priming" read fed K-PKE another duplicated
byte, corrupting `t_hat` and the `v` half of the ciphertext. The result was a
ciphertext no standard implementation could decapsulate. Both are fixed and the
core now matches the reference on all three KAT vectors.

**ML-DSA compared only two-thirds of the challenge hash.** `VF_COMPARE` in
`verify_ctrl.v` tested `c_tilde[255:0]`, but ML-DSA-65 uses a 48-byte (384-bit)
c-tilde, leaving 128 bits unchecked. All 384 bits are now compared.

**Build fixes:** `PQC_integrated/rtl_mldsa/` was missing from the repository
(nothing could compile); `run_xsim.bat` looked for the `.mem` vectors in the
wrong directory; `run_xrun.sh` had `//` comments before its shebang and used
`XCELIUM_HOME` as if it were the `xrun` binary path.

---

## Repository Layout

```
.
+-- AM_ijtag/                     0) Baseline IJTAG chain (pre-PQC)
|   +-- design/                      MSIB.v, SiB.v, TDR.v, mux21.v, AM.v, ...
|   +-- tb/                          AM_tb.v, TDR_tb.v, Top_module_tb.v
+-- MLDSA_verify/                 1) Standalone ML-DSA-65 verify datapath
+-- MLKEM_encapsuation/           2) Standalone ML-KEM-768 encaps datapath
|   +-- go/ python/                  Reference models used to cross-check it
+-- PQC_integrated/               3) Integration
|   +-- design/
|   |   +-- integrated_top.v          Top-level integration
|   |   +-- am_pqc.v                  Access-manager / PQC control FSM
|   |   +-- keccak_shared.v           The design's single Keccak-f[1600]
|   |   +-- ext_sipo.v                26,567-bit unlock-frame capture register
|   |   +-- inst_priority_decoder.v   Instrument priority decode
|   |   +-- j_trng.v                  TRNG (per-session IV)
|   |   +-- mldsa_verify_block.v      ML-DSA signature verify
|   |   +-- mlkem_encaps_wrapper.v    ML-KEM encapsulation wrapper
|   |   +-- otp.v                     One-time-programmable key store
|   |   +-- shake_stream.v            SHAKE-256 stream cipher for TDO
|   +-- rtl_mldsa/                    ML-DSA-65 verification core
|   +-- rtl_mlkem/                    ML-KEM-768 encapsulation core
|   +-- tb/
|   |   +-- integrated_top_tb.v       Self-checking system testbench
|   |   +-- kem_kat/                  ML-KEM FIPS 203 KAT (3 vectors, CT + K)
|   +-- run/                          run_iverilog.bat, run_xrun.sh
+-- run_xsim.bat                  Vivado xsim run script
+-- SNAPSHOT.txt                  Build summary and verification record
```

The integrated cores in `PQC_integrated/rtl_mldsa/` and `rtl_mlkem/` started
from the standalone directories but have since been extended (full FIPS 204
verification, FIPS 203 H/G hashing) and pipelined, so they are no longer
file-identical to them - the integrated copies are the reference.

---

## Known Gaps

- **Area, power and the 100 MHz critical path are not verified here.** Those
  figures in the paper come from Genus with the SAED 90nm library; only
  simulation was run for this work. Now that the Keccak core is genuinely
  shared, the area numbers are worth re-running.
- **Two baseline testbenches fail on their own**, both pre-existing and
  unrelated to the PQC design: `AM_ijtag/tb/TDR_tb.v` never instantiates the
  inverter instrument it expects to read back, and `AM_ijtag/tb/Top_module_tb.v`
  shifts data without opening the SIB hierarchy first. `AM_tb.v` passes, and the
  same chain blocks are exercised properly by the system testbench.
- `MLDSA_verify/mldsa/verify_tb.v` reports PASS vacuously: it drives
  `c_tilde_orig = c_tilde_prime = 0`, so "valid" only compares zeros. The real
  ML-DSA check is the system testbench.

---

## License

See the [LICENSE](../LICENSE) file.
