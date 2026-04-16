# `max10_prog_avmm` — Standalone Sign-off Infrastructure (OPEN)

- status  : open
- author  : Yifeng Wang (yifenwan@phys.ethz.ch)
- opened  : 2026-04-15
- source  : FEB SciFi round-5 Option-C full compile follow-up
  (`OPEN_TIMING.md` worst-path fix on `csr_read_addr_reg[5] -> csr_read_data[4]`)

---

## 1. Why this file exists

The Slow-85C setup closure fix for this IP (RTL `Revision 26.1.0`,
`Date 20260415`) was landed and propagated directly into the FEB SciFi
`feb_system_v2/synthesis/submodules/` tree. The round-6 integration
compile is the **only** gate that validated the change.

The house rule in `CLAUDE.md` ("Standalone IP Rerun After RTL Fix")
requires both a **standalone tb/** and a **standalone syn/** gate at
`1.1× F_target` sign-off to run before an IP-level RTL change is
propagated into an integration build. For this legacy IP neither gate
exists today:

```
feb_max10_comm/legacy/max10_prog_avmm/
├── rtl/max10_prog_avmm.vhd         ← the IP
├── max10_prog_avmm_hw.tcl
├── max10_prog_avmm.sdc
├── OPEN_TIMING.md
├── TIMING_SYN_OPEN.md              ← this file
└── syn/quartus/db/                 ← stale db dir only, no .qpf/.qsf
```

There is no `tb/`, no `.qsf`, no `.qpf`, no `.qip` source list at this
level. The `slow-control_hub/syn/quartus/sc_hub_minimal_live.qsf`
referenced in `OPEN_TIMING.md` was the intended pattern but was never
replicated for this legacy IP.

## 2. What was skipped on 2026-04-15

Round-5 brought the worst path into this IP at Slow 85C setup
(-0.156 ns). The option-2 fix (per-bank pipelined CSR readback mux,
see `rtl/max10_prog_avmm.vhd` header) was applied and validated
**only at the integration level** via the FEB SciFi round-6 compile.
The standalone gates below were explicitly deferred:

1. **Standalone tb/** — a directed or UVM harness that exercises:
   - CSR writes to every register in the identity / ctrl / status /
     error / flash / xfer / max10 / last_error bank (`0x000..0x00E`)
   - PAGE_DATA burst writes across `0x020..0x05F`
   - Boot-history register reads across `0x060..0x074`
   - Bursted read back-to-back across bank boundaries (the `waitrequest`
     / burst FSM is what actually stresses the new 3-cycle AVMM read
     latency and the per-bank flop pipeline)
   - Both functional registers and error paths (`err_flags`, `last_error`,
     error-count saturation)
   - A `sw_reset` pulse mid-burst to ensure the pipeline drains cleanly
2. **Standalone syn/** — a minimal Quartus project matching the
   `sc_hub_minimal_live.qsf` template:
   - `.qsf` with `FAMILY "Arria V"`, target `5AGXBA7D4F31C5`
   - sign-off PLL at `172.5 MHz` (1.1 × 156.25 MHz) on
     `transceiver_pll_clock[0]`
   - `max10_prog_avmm.sdc` plus the PLL constraint
   - `.qip` aggregating just the IP RTL and its `work.mudaq` /
     `work.util_slv` dependencies
   - `quartus_sta` flow run against all four corners
     (Slow 1100mV 0C / 85C, Fast 1100mV 0C / 85C)

## 3. Acceptance criteria for closing

A future session should:

1. Build `tb/sim/` with a Makefile using the Questa FSE Starter setup
   from `CLAUDE.md` ("Questa FSE License Setup"). UVM harness if budget
   permits; directed VHDL `tb_max10_prog_avmm.vhd` is acceptable for
   first pass.
2. Build `syn/quartus/max10_prog_avmm_minimal.{qpf,qsf}` from the
   `sc_hub_minimal_live` pattern, with 1.1× sign-off PLL.
3. Re-run the CSR readback pipeline timing closure at standalone
   sign-off and capture the worst-path report under `syn/quartus/
   reports/`.
4. After both gates are clean, delete this file and the deferred-work
   note in `OPEN_TIMING.md` section 6 and 7.

Until then: **any RTL change to this IP must be validated directly
via an FEB SciFi integration compile round, which burns ~50 minutes
per debug loop**. That cost is the reason this file exists.

## 4. References

- `OPEN_TIMING.md` — the Slow-85C path that triggered the fix.
- `rtl/max10_prog_avmm.vhd` — header `Revision 26.1.0` contains the
  canonical description of the per-bank pipeline.
- `CLAUDE.md` section "Standalone IP Rerun After RTL Fix" — the house
  rule this file documents deviation from.
- `mu3e-ip-cores/slow-control_hub/syn/quartus/sc_hub_minimal_live.qsf`
  — template for the deferred standalone syn project.
