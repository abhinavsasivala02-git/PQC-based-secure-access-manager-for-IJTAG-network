# PQC-Based Secure Access Manager for IJTAG Networks

A JTAG/IJTAG unlock mechanism protected with post-quantum cryptography:
**ML-KEM-768** (FIPS 203) encapsulation for session-key distribution,
**ML-DSA-65** (FIPS 204) signature verification for test-command
authentication, per-session SHAKE-256 stream encryption of the scan-chain
output, and a factory-provisioned OTP key store.

Companion paper: [`PQC-Based_Secure_Access_Manager_for_IJTAG_Network.pdf`](PQC-Based_Secure_Access_Manager_for_IJTAG_Network.pdf).

---

## Two Designs

The repository holds the design in two configurations, each complete and
runnable on its own with its own README and results.

| Folder | Total unlock latency | ML-DSA verify |
|--------|---------------------|---------------|
| [`original_design/`](original_design) | **3.35 ms** - the latency reported in the paper | 2,554 µs |
| [`optimized_design/`](optimized_design) | **1.89 ms** - maximum throughput | 1,091 µs |

The two share the same RTL and produce bit-identical results; only the timing
differs.

---

## Results at a Glance

Vivado XSim 2023.2, 100 MHz TCK, measured from reset to `UNLOCKED`:

| Phase | original_design | optimized_design | Paper (Sec. IV-C) |
|-------|-------------|------------|-------------------|
| OTP provisioning (testbench) | 32 µs | 32 µs | - |
| ML-KEM encapsulation (CT out on TDO concurrently) | 497 µs | 497 µs | ~500 µs |
| 26,567-bit unlock frame shift-in | 266 µs | 266 µs | ~265 µs |
| ML-DSA-65 verification | 2,554 µs | 1,091 µs | 1.5-2.5 ms |
| **Total** | **3.35 ms** | **1.89 ms** | **~3.35 ms** |

Both designs pass the self-checking system testbench: **47 PASS**,
`TB: PASS - ALL TEST CASES PASSED`.

Before this work the design took 4.94 ms, so the original design is 1.5x faster
and the optimized design 2.6x faster.

---

## Design Summary

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

The Access Manager only unlocks an instrument cluster when a 26,567-bit frame
carrying a genuine ML-DSA-65 signature is verified on-chip. High-priority
instrument output is then encrypted on TDO with a SHAKE-256 stream keyed by the
ML-KEM session key and a fresh TRNG IV, so each session's keystream differs.

A single Keccak-f[1600] core (`PQC_integrated/design/keccak_shared.v`) serves
all six hash users - ML-KEM's H, G, PRF and SampleNTT, ML-DSA's ExpandA and
SHAKE-256, and the stream cipher - since they are mutually exclusive in time.

---

## Running It

From either design folder:

```
run_xsim.bat                          Vivado XSim, full system testbench
cd PQC_integrated/run && run_iverilog.bat        Icarus, same testbench
cd PQC_integrated/tb/kem_kat && run_kem_kat.bat  ML-KEM FIPS 203 KAT
cd PQC_integrated/run && sh run_xrun.sh          Xcelium
```

Latency is fixed by the RTL cycle count and the 100 MHz clock - it does not
depend on which simulator is used.

---

## Verification

- Self-checking system testbench, 47 checks: OTP provisioning and locking,
  boot-load, ML-KEM encapsulation with the ciphertext shifted out on TDO,
  unlock with a genuine NIST ML-DSA signature, clusters 0-3, priority-based
  encryption against an independent SHAKE-256 model, irrevocable key state,
  per-session IV replay resistance, and negative tests for wrong
  signature/key/instruction/data.
- ML-KEM checked against the FIPS 203 reference on 3 vectors, ciphertext and
  shared secret K (`PQC_integrated/tb/kem_kat/`).
- Both NTT cores diffed cycle-by-cycle against the pre-optimisation versions on
  random polynomials, forward and inverse: bit-identical.

Area, power and the 100 MHz critical path are not verified in this repository;
those figures come from Genus with the SAED 90nm library.

---

## Repository Layout

```
.
+-- PQC-Based_Secure_Access_Manager_for_IJTAG_Network.pdf   The paper
+-- LICENSE
+-- original_design/         The latency reported in the paper
+-- optimized_design/        Maximum throughput
```

Each design folder contains:

```
+-- AM_ijtag/                Baseline IJTAG chain (pre-PQC)
+-- MLDSA_verify/            Standalone ML-DSA-65 verify datapath
+-- MLKEM_encapsuation/      Standalone ML-KEM-768 encaps datapath
+-- PQC_integrated/          The integrated design, testbenches and run scripts
+-- README.md                Full results and details for that design
+-- SNAPSHOT.txt             Summary and verification record
+-- vivado_sim_*.log         Vivado transcript for that design
```

---

## License

See the [LICENSE](LICENSE) file.
