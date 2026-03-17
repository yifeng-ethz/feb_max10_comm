# RTL Note — feb_max10_comm

Date: 2026-03-16
Author: Codex

## 0. Summary

- Scope: standalone Quartus sign-off iteration for `feb_max10_comm`, Qsys regeneration into FEB firmware, and board-level synthesis/fitter recheck with SignalTap disabled.
- Sign-off status: partial. RTL simulation and Qsys/package parity are closed; standalone Quartus timing improved to a near-clean single-corner miss but still does not meet the 10% timing margin gate; full FEB board timing remains dominated by unrelated system clocks.
- Key deltas vs `RTL_PLAN.md`:
  - Added standalone `syn/quartus/` Arria V harness and constraints.
  - Added `STATUS_POLL_LIMIT` generic override for simulation only; synthesis default remains `50000`.
  - Tightened local IP SDC coverage for explicit CDC paths (toggle syncs, debug mirror syncs, reset sync).
  - Disabled FEB SignalTap by default in the board build to reduce integration overhead and fit pressure.

## 1. Targets (from `RTL_PLAN.md`)

- Device / speed grade / temp: Arria V `5AGXBA7D4F31C5`, slow `1100mV 85C` corner used as the primary closure target.
- Sign-off clock(s):
  - `csr_clk` at approximately `156.25 MHz`
  - `link_clk` at approximately `50 MHz`
- Target frequency:
  - `csr_clk`: `156.25 MHz` (`Tclk = 6.400 ns`)
  - `link_clk`: `50 MHz` (`Tclk = 20.000 ns`)
- Timing margin rule:
  - Require `WNS >= +0.10 × Tclk`
  - Therefore require:
    - `csr_clk` WNS `>= +0.640 ns`
    - `link_clk` WNS `>= +2.000 ns`
- Resource estimate reference: `RTL_PLAN.md` does not currently provide explicit ALM/FF/RAM/DSP estimates, so ratio-based resource sign-off could not be applied directly.

## 2. DV sign-off (RTL simulation)

- Testbench entrypoints:
  - `tb/sim/`
  - `tb/uvm/`
- `DV_PLAN.md` checklist:
  - No `DV_PLAN.md` file is present in this IP tree. Existing verification evidence was taken from the checked-in regression outputs and README status.
- Evidence:
  - `tb/sim`: all `8` deterministic `SIM_*` cases are marked passing in [README.md](/home/yifeng/packages/mu3e_ip_dev/mu3e-ip-cores/feb_max10_comm/README.md)
  - Representative logs exist under:
    - [vsim.log](/home/yifeng/packages/mu3e_ip_dev/mu3e-ip-cores/feb_max10_comm/tb/sim/work_sim_001_reset_defaults/vsim.log)
    - [vsim.log](/home/yifeng/packages/mu3e_ip_dev/mu3e-ip-cores/feb_max10_comm/tb/sim/work_sim_008_fault_injection/vsim.log)
  - `tb/uvm`: all `128` runnable `UVM_*` cases are marked passing in [README.md](/home/yifeng/packages/mu3e_ip_dev/mu3e-ip-cores/feb_max10_comm/README.md)
  - Representative regression logs exist under:
    - [UVM_001_RESET_DEFAULTS.log](/home/yifeng/packages/mu3e_ip_dev/mu3e-ip-cores/feb_max10_comm/tb/uvm/regression_logs_20260316/UVM_001_RESET_DEFAULTS.log)
    - [UVM_128_RANDOM_15.log](/home/yifeng/packages/mu3e_ip_dev/mu3e-ip-cores/feb_max10_comm/tb/uvm/regression_logs_20260316_rerun/UVM_128_RANDOM_15.log)
  - Qsys/package parity:
    - parity regeneration script passed earlier in the 2026-03-16 closure
    - source script: [check_synthesis_parity.py](/home/yifeng/packages/mu3e_ip_dev/mu3e-ip-cores/feb_max10_comm/tb/uvm/check_synthesis_parity.py)

## 3. Timing closure (mini Quartus project in `syn/quartus/`)

- Project location: [syn/quartus/](/home/yifeng/packages/mu3e_ip_dev/mu3e-ip-cores/feb_max10_comm/syn/quartus)
- Target device matches main project: yes
- Build commands:
  - `quartus_sh --flow compile feb_max10_comm_syn`
  - `quartus_sta -t /tmp/fm10_timing_report.tcl`
- Compile time:
  - standalone full compile completed in approximately `1m56s` on 2026-03-16

### 3.1 Timing results

- Setup summary after the latest RTL + SDC updates:
  - Slow `1100mV 85C`
    - `csr_clk`: WNS `-0.046 ns`, TNS `-0.046 ns`
    - `link_clk`: WNS `+12.510 ns`, TNS `0.000 ns`
  - Slow `1100mV 0C`
    - `csr_clk`: WNS `+0.094 ns`, TNS `0.000 ns`
    - `link_clk`: WNS `+12.655 ns`, TNS `0.000 ns`
  - Fast corners passed
- Hold summary:
  - standalone hold is clean at all reported corners
- Worst failing paths and fixes:
  - Fixed synthesis blocker in `proc_stage_store` by replacing a Quartus-rejected unbounded `while` loop with a bounded, synthesis-friendly valid-mask scan in [max10_controller.vhd](/home/yifeng/packages/mu3e_ip_dev/mu3e-ip-cores/feb_max10_comm/rtl/max10_controller.vhd)
  - Fixed previously missing CDC constraints for:
    - debug mirror buses
    - CSR-to-link reset synchronizer
    - file: [feb_max10_comm.sdc](/home/yifeng/packages/mu3e_ip_dev/mu3e-ip-cores/feb_max10_comm/feb_max10_comm.sdc)
  - Remaining real standalone setup miss is the `csr_clk` PAGE_DATA write/decode path into `stage_store.staged_words_count[0]`, reported from `avs_csr_address[*]` into that counter register.
- Timing gate result:
  - FAIL for standalone sign-off margin, because `csr_clk` is below the required `+0.640 ns` margin.

## 4. Resource usage

| Resource | RTL_PLAN estimate | Actual | Ratio | Pass (0.5×–3.0×) | Notes |
|:---------|:------------------|:-------|:------|:-----------------|:------|
| ALMs | N/A | `2,123` | N/A | N/A | From standalone fitter summary |
| FFs | N/A | `3,931` | N/A | N/A | From standalone fitter summary |
| RAM blocks | N/A | `1` | N/A | N/A | From standalone fitter summary |
| RAM bits | N/A | `4,096` | N/A | N/A | From standalone fitter summary |
| DSP blocks | N/A | `0` | N/A | N/A | From standalone fitter summary |

Resource evidence:
- [feb_max10_comm_syn.fit.summary](/home/yifeng/packages/mu3e_ip_dev/mu3e-ip-cores/feb_max10_comm/syn/quartus/output_files/feb_max10_comm_syn.fit.summary)

## 5. Gate-level simulation sign-off

- Netlist/SDF generation: not run in this turn
- TB runner used: N/A
- Status: open

## 6. Optional hardware validation (driver + SignalTap)

- Hardware validation was not run in this turn.
- SignalTap was intentionally disabled by default for the FEB board build to reduce fit pressure while integrating the new IP.

## 7. RTL changes (iteration history)

- Iteration 1:
  - Fixed invalid sequential VHDL assignments inside CSR read logic so Quartus synthesis would accept the controller.
- Iteration 2:
  - Added `staged_words_count` into `stage_store` state and removed the previous long combinational count path from CSR status/error packing.
- Iteration 3:
  - Reworked `proc_stage_store` into a bounded valid-mask scan after Quartus rejected the earlier `while` loop during synthesis elaboration.
- Iteration 4:
  - Added explicit SDC coverage for debug mirror CDC and CSR-to-link reset synchronizer paths to remove false async timing failures from the standalone reports.
- Iteration 5:
  - Disabled SignalTap by default in FEB build files and regenerated `debug_sc_system.qsys` plus `feb_system.qsys` so the board project picks up the updated IP cleanly.

## 8. Integration evidence

- Qsys regeneration succeeded on 2026-03-16 for:
  - [debug_sc_system_generation.rpt](/home/yifeng/packages/online_dpv2/online/fe_board/fe_scifi/debug_sc_system/debug_sc_system_generation.rpt)
  - [feb_system_generation.rpt](/home/yifeng/packages/online_dpv2/online/fe_board/fe_scifi/feb_system/feb_system_generation.rpt)
- Both systems instantiate `max10_prog_avmm_0` as `feb_max10_comm`.
- Full FEB top synthesis with SignalTap disabled succeeded on 2026-03-16 after regeneration.
- Full FEB fitter and STA also succeeded to completion on the regenerated board project using the same integration path:
  - fitter summary: [top.fit.summary](/home/yifeng/packages/online_dpv2/online/fe_board/fe_scifi/output_files/top.fit.summary)
  - STA summary: [top.sta.summary](/home/yifeng/packages/online_dpv2/online/fe_board/fe_scifi/output_files/top.sta.summary)
- Board-level timing remains dominated by unrelated top-level clocks/domains:
  - `spare_clk_osc`: WNS `-4.352 ns`, TNS `-25.299 ns`
  - `q_feb_system ... pll_sclk ... divclk`: WNS `-4.155 ns`, TNS `-4625.848 ns`
  - `transceiver_pll_clock[0]`: WNS `-1.591 ns`, TNS `-172.430 ns`
  - `lvds_firefly_clk`: WNS `-0.493 ns`, TNS `-13.973 ns`
  - `q_feb_system ... pll_156t40 ... divclk`: setup WNS `+1.141 ns`, recovery WNS `-4.406 ns`

## 9. Open items

- Standalone `csr_clk` timing still needs another RTL iteration to turn the remaining `-0.046 ns` miss into the required `+0.640 ns` sign-off margin.
- Board-level timing closure remains open and is dominated by other FEB clocks/domains outside this IP.
- Gate-level simulation has not been executed for this IP.
- `DV_PLAN.md` is missing and should be added if formal sign-off traceability is required.
