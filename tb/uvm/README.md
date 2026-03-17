# `feb_max10_comm` UVM Area

This directory contains the UVM layer for `feb_max10_comm`.

The environment binds the new FEB-side programming bridge to the proven
downstream MAX10/flash compatibility chain and keeps the register surface
limited to the programming window `0x000..0x05F`. Boot-history is deferred in
this stage and is not part of the UVM surface here.

Contents:

- `feb_max10_comm_if.sv`
  - shared interface for CSR access, resets, timing knobs, injections, link
    monitors, diagnostics, and flash probes
- `feb_max10_comm_pkg.sv`
  - CSR agent, monitor, scoreboard, directed tests `UVM_001..UVM_018`, and the
    shared table-driven test base
- `feb_max10_comm_matrix_tests.svh`
  - generated matrix wrappers `UVM_019..UVM_128`
- `feb_max10_comm_uvm_tb.sv`
  - top-level UVM testbench
- `../common/feb_max10_comm_model_wrapper.vhd`
  - VHDL wrapper that binds the DUT to the downstream MAX10/flash models
- `run_uvm_feb_max10_comm.sh`
  - compile/run entry point
- `check_synthesis_parity.py`
  - regenerates `debug_sc_system.qsys` and `feb_system.qsys` and checks that the
    packaged IP, Qsys instance replacement, SDC propagation, and top-level MAX10
    wiring remain intact

Runnable matrix:

- `UVM_001..UVM_016`
  - reset defaults, versioning, CSR semantics, staged-word/readback rules
- `UVM_017..UVM_048`
  - legal programming flows across lengths, alignments, and last-word widths
- `UVM_049..UVM_072`
  - overlap, snapshot reuse, clear-page, clear-addr, clear-status behavior
- `UVM_073..UVM_096`
  - clock-ratio and reset-phase stress
- `UVM_097..UVM_112`
  - timeout, CRC, nSTATUS-low, conflict, underrun, and reset-drain scenarios
- `UVM_113..UVM_128`
  - longer randomized and recovery-oriented regressions

Run examples:

- compile only
```bash
RUN_SYNTH_PARITY_CHECKS=0 UVM_RUN_MODE=compile ./run_uvm_feb_max10_comm.sh +UVM_TESTNAME=UVM_001_RESET_DEFAULTS
```
- full UVM run
```bash
RUN_SYNTH_PARITY_CHECKS=0 ./run_uvm_feb_max10_comm.sh +UVM_TESTNAME=UVM_001_RESET_DEFAULTS
```

License/runtime note:

- The runner follows the `online_sc` workspace guidance in
  `/home/yifeng/packages/online_sc/workspace_tooling.md`.
- For UVM it uses the Pro Questa chain:
  - `LM_LICENSE_FILE=/data1/intelFPGA_pro/23.1/questa_fse/LR-287689_License.dat:8161@lic-mentor.ethz.ch`
  - `TB_SIM_FLAVOR=mentor`
  - `TB_UVM_SRC_DIR=/data1/intelFPGA_pro/23.1/questa_fse/verilog_src/uvm-1.2/src`
- `run_uvm_feb_max10_comm.sh` now auto-sanitizes the stale Quartus 18.1 license
  path `/data1/intelFPGA/LR-121070_License.dat` and mirrors the corrected chain
  into `MGLS_LICENSE_FILE`.

Simulation note:

- The shared model wrapper sets `STATUS_POLL_LIMIT=1024` for simulation only so
  link-timeout scenarios finish in practical wall-clock time.
- The RTL default remains `STATUS_POLL_LIMIT=50000`, so synthesis behavior is
  unchanged.

Current status:

- `UVM_RUN_MODE=compile` passes on this machine.
- Full execution of all `128` runnable tests now passes on this machine.
- Latest clean sweep logs are under `regression_logs_20260317_final_rerun_134431/`.
