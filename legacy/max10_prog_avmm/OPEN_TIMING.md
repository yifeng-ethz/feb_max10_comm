# `max10_prog_avmm` — Open Timing Issues

- status  : open
- author  : Yifeng Wang (yifenwan@phys.ethz.ch)
- opened  : 2026-04-15
- source  : FEB SciFi round-5 Option-C full compile
  (`online_dpv2/online/fe_board/fe_scifi`, Quartus Prime Standard 18.1,
  Arria V `5AGXBA7D4F31C5`, `transceiver_pll_clock[0]` = 156.25 MHz)

---

## 1. Summary

After closing the `sc_hub_core` soft-reset cone via the dedicated
`CORE_RESETTING` FSM state (slow-control_hub commit `38d8bc7`), the FEB SciFi
integration build's worst setup path moved into `max10_prog_avmm`. The
remaining violation is **-0.156 ns on Slow 1100mV 85C** on
`transceiver_pll_clock[0]`. All other corners (Slow 0C setup, Fast 85C/0C
setup, hold, recovery, removal, MPW) are clean.

| Corner | Setup slack | Note |
|---|---|---|
| Slow 1100mV 85C | **-0.156** | worst path inside `max10_prog_avmm` |
| Slow 1100mV 0C  | +0.061 | |
| Fast 1100mV 85C | +1.920 | |
| Fast 1100mV 0C  | +2.093 | |

The integration build is **currently shipped as-is**: the junction
temperature on the installed FEB SciFi boards stays well below the
Slow-85C corner at which the violation manifests, and every other check
(hold, recovery, removal, minimum pulse width) is positive across all
four corners.

---

## 2. Worst path (Slow 85C setup)

```
Path #1: Setup slack -0.156 (VIOLATED)
From: control_path_subsystem | max10_prog_avmm_0 | csr_read_addr_reg[5]~DUPLICATE
To:   control_path_subsystem | max10_prog_avmm_0 | csr_read_data[4]
Launch clock: transceiver_pll_clock[0]
Latch clock:  transceiver_pll_clock[0]
Setup Relationship: 6.400 ns
Clock Skew:         -0.101 ns
Data Delay:         6.405 ns
Number of Logic Levels: 5
```

Combinational chain (from STA `report_timing -detail full_path`):

```
csr_read_addr_reg[5]~DUPLICATE
  -> Equal30~0        (LUT, decode csr_read_addr == constant)
  -> Equal32~0        (LUT, second decode of the same address)
  -> Selector4606~29  (LUT, mux layer 1)
  -> Selector4606~33  (LUT, mux layer 2)
  -> Selector4606~34  (LUT, mux layer 3)
  -> csr_read_data[4] (register input)
```

Structurally: a **wide CSR read-data mux** over the CSR read address,
where `csr_read_addr[5]` is the late-arriving decode input that fans
into multiple `Selector4606~*` mux layers before landing on
`csr_read_data[*]`.

## 3. Other violators in the same cone

All top-5 worst paths from the round-5 build are inside the same
`max10_prog_avmm` readback / ingress cone:

| # | Slack  | From → To (abbrev.) |
|---|--------|---|
| 1 | -0.156 | `csr_read_addr_reg[5]~DUPLICATE` → `csr_read_data[4]` |
| 2 | -0.142 | `mm_interconnect_0.agent_pipeline_010.data1[44]` → `csr_pack.page_data[8][24]` |
| 3 | -0.106 | `csr_read_addr_reg[5]~DUPLICATE` → `csr_read_data[10]` |
| 5 | -0.105 | `mm_interconnect_0.agent_pipeline_010.data1[45]~DUPLICATE` → `csr_pack.page_data[8][24]` |

Path #4 (-0.106) is a `jtag_master` packets-to-fifo internal path and
does not belong to this IP.

---

## 4. Root cause read

- `csr_read_data` is assembled by a single wide combinational mux that
  switches on `csr_read_addr`. Quartus synthesised this as a multi-layer
  `Selector4606~*` chain with 5 logic levels of LUTs.
- `csr_read_addr_reg[5]` is late — it fans into two separate `Equal*`
  decoders before reaching the first selector stage, adding two extra
  LUT hops on top of the mux depth.
- `csr_pack.page_data[8][24]` is driven from the mm_interconnect agent
  pipeline with a combinational path through the ingress decode, which
  shows up as a parallel -0.14 ns violator (path #2).

## 5. Fix options (not yet applied)

1. **Register `csr_read_data` one cycle after `csr_read_addr`** — read
   becomes `addr → addr_q → data_q`. The CPU/Nios side already expects
   at least one wait-state on an AVMM read, so the extra latency is free
   at the ISA level. This collapses the 5-LUT mux into a balanced
   2-stage decode and removes `csr_read_addr[5]` from the direct arrival
   path to `csr_read_data`.
2. **Pre-decode the address into a one-hot vector** one cycle early
   (`addr_onehot <= decode(addr)`) and drive `csr_read_data` from a
   width-balanced AND-OR tree over `addr_onehot` instead of the
   address-indexed Selector cone. This keeps single-cycle reads but
   reduces the mux depth.
3. **Split the CSR space into banks** (`csr_read_data_bank0`,
   `csr_read_data_bank1`, ...) and mux the banks in a registered outer
   stage. Each bank has a narrower indexed mux.
4. **Add a multicycle path** of `-setup 2` on the
   `csr_read_addr_reg[*] → csr_read_data[*]` arc *only* if the firmware
   actually holds `read_addr` stable for more than one cycle on every
   CSR read. Requires explicit verification of the upstream control
   protocol — do not apply blindly.
5. **`csr_pack.page_data[8][24]` ingress path** (violators #2 and #5)
   needs an independent skid buffer at the agent_pipeline_010 boundary
   or a registered write-decode inside `max10_prog_avmm`. The current
   code appears to combinationally fan the interconnect `data1[44/45]`
   bits into a wide write-decode before the flop.

## 6. Acceptance criteria for closing this issue

- Slow 1100mV 85C setup on `transceiver_pll_clock[0]` ≥ 0 ns after the
  fix, verified in both:
  1. the IP's own standalone `syn/` project at 1.1× F_target sign-off
     (if one exists — add it if missing, matching the
     `slow-control_hub` `sc_hub_minimal_live.qsf` pattern), and
  2. the FEB SciFi integration build at 156.25 MHz target.
- No regression on the other three corners or on hold/recovery/removal/
  MPW checks.
- Standalone testbench (if present under `tb/`) still passes after the
  RTL edit.

Until those gates are cleared, the FEB SciFi ship build carries a
documented Slow-85C setup violation confined to this IP.

---

## 7. References

- FEB SciFi round-5 STA report: `online_dpv2/online/fe_board/fe_scifi/output_files/top.sta.rpt`
- Top-5 worst setup path detail dump: `/tmp/r5_worst5_setup_slow85.txt`
- Upstream sc_hub cone fix: `mu3e-ip-cores/slow-control_hub` commit `38d8bc7`
  ("sc_hub: CORE_RESETTING FSM state + avmm_handler v26.2.8 for FEB SciFi timing")
