# ML-KEM Encapsulation — Required Changes for Correct FIPS-203 Output

## Objective

Make `mlkem_encaps_top` (K-PKE.Encrypt, ML-KEM-768) produce **bit-exact** output matching
the NIST KAT vector (`kat_ct.mem` in project root / `D:\mlkem_kat_xsim`), instead of the
current broken behaviour (runs to completion but emits undefined/incorrect ciphertext).

ML-KEM-768: `K=3, ETA2=2, DU=10, DV=4`. Ciphertext = 1088 bytes
(`3 * 320` for `u` + `128` for `v`).

---

## 1. Bugs found (root-cause summary)

| # | File | Bug | Effect |
|---|------|-----|--------|
| 1 | `kpke/kpke_encrypt_shared.v` | `t_hat` never loaded into `ram4` | `v` computed with zero/undefined key |
| 2 | `kpke/kpke_encrypt_shared.v` | `m` never mixed in (`Decompress_1(m)` missing) | `v` missing message term `μ` |
| 3 | `kpke/kpke_encrypt_shared.v` | arith `a`/`b` inputs hardwired wrong (`arith_b_rdata=ram5`); basemul result overwrote accumulator instead of accumulating | `u`/`v` accumulation wrong |
| 4 | `math/ntt_core.v` | Butterfly `a±t` / `a+b` not reduced mod q; written to 12-bit RAM | coefficients exceed q (up to 2q=6658), truncate → corrupt NTT |
| 5 | `math/poly_basemul.v` | `c0 = mont(a0b0)+mont(a1b1*γ)` and `c1 = ...+...` not reduced mod q; written 12-bit | base-mul results exceed 12-bit → corrupt |

Bugs 1–3 are **fixed** (see §2). Bugs 4–5 are **outstanding** (see §3).

---

## 2. Changes already made

### `kpke/kpke_encrypt_shared.v` (rewritten control/datapath)

- Added FSM states:
  - `ST_DEC_T` / `ST_DEC_T_W` — `ByteDecode_12` of `ek[0:384K]` into `ram4`
    (via `byte_decode` module, byte-feed driven by `ek_rdata`/`ek_addr`).
  - `ST_T_NTT` / `ST_WAIT_T_NTT` — forward NTT of each `t[i]` in-place in `ram4`
    (`ntt_ram_sel = 3` routing added for ram4).
  - `ST_MU_RD` / `ST_MU_WR` — compute `w = e2 + μ` into `ram6` (`μ[i] = (m bit i) ? 1665 : 0`).
  - `ST_CLR_V`, `ST_BMUL_V`, `ST_ADD_V`, `ST_INTT_V`, `ST_ADD_W`, `ST_COMP_V`, `ST_ENC_V`
    — full `v` path: `v = INTT(Σ t_hat[j]·r_hat[j]) + e2 + μ`.
- `e2` is now sampled **after** the `u` phase (`ST_PRF_E2`, index `2K`) so it does not
  collide with `u`-phase use of `ram6`.
- Basemul product for `u` routed to `ram6` (scratch) then accumulated into `ram2` via arith;
  for `v` routed to `ram0` then accumulated into `ram3`.
- `arith_a_rdata` / `arith_b_rdata` now muxed per operation (ram2/ram3 for `a`,
  ram6/ram5/ram0 for `b`).

## 3. Changes still required

### `math/ntt_core.v` — reduce butterfly outputs mod q

Current (lines ~103–113):
```verilog
// forward (CT)
bfly_a_out <= bfly_a_in + ct_t;      // range [0,2q)  -> overflows 12-bit
bfly_b_out <= bfly_a_in - ct_t;      // range (-q,q)  -> negative, wrong in 12-bit
// inverse (GS)
bfly_a_out <= bfly_a_in + bfly_b_in; // range [0,2q)  -> overflows
bfly_b_out <= mont(zeta*(a-b));      // ok (montgomery reduces)
```
Required fix:
- Forward `a_out = barrett_reduce(a + t)`; `b_out = (a - t) < 0 ? (a - t + q) : (a - t)`.
- Inverse `a_out = barrett_reduce(a + b)`.
- Keep `b_out` (GS) as montgomery result (already reduced).
- Store reduced values so RAM coefficients stay in `[0, q)` (12 bits).

### `math/poly_basemul.v` — reduce base-mul accumulations mod q

Current:
```verilog
S_COMP_C0: c0_val <= m_a0b0 + m_a1b1g;   // [0,2q) -> 12-bit truncation
S_COMP_C1: c1_val <= m_a0b1 + m_a1b0;   // [0,2q) -> 12-bit truncation
S_WR_C0:   c_wdata <= c0_val[11:0];
S_WR_C1:   c_wdata <= c1_val[11:0];
```
Required fix:
- `c0 = barrett_reduce(m_a0b0 + m_a1b1g)`, `c1 = barrett_reduce(m_a0b1 + m_a1b0)`
  before writing to the 12-bit output.

### (Optional) confirm `montgomery_reduce` signed-input behaviour
- Used for `GS` path (`zeta * (a-b)` where `(a-b)` can be negative) and basemul.
- Current module maps negative residues back to `[0,q)` via `r<0 ? r+q : ...` — appears
  correct, but re-verify with a couple of scalar test vectors during KAT debugging.

---

## 4. Verification plan

1. Rebuild with iverilog:
   ```
   iverilog -I pkg -o tb_kat -g2012 <all .v> tb_kem_kat.v
   vvp tb_kat
   ```
2. Expect `KEM-KAT PASS: ciphertext (1088B) matches NIST vector`.
3. If FAIL, use `tb_debug.v` (add RAM dumps at correct FSM points) to isolate which
   polynomial (r_hat / t_hat / u / v) diverges.
4. Re-run in Vivado xsim via `run_xsim.bat` (switch testbench to `tb_kem_kat.v`) to confirm
   the same bit-exact result in the FPGA tool flow.
