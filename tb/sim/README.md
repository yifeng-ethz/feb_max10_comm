# `feb_max10_comm` Fast Sim Area

This directory contains the deterministic post-RTL simulation layer for
`feb_max10_comm`.

The fast sim harness reuses the downstream compatibility models from
`legacy/max10_prog_avmm/tb/sim/compat` and the shared
`tb/common/feb_max10_comm_model_wrapper.vhd`. It is intended for quick checks
after RTL edits and for verifying the packaged/Qsys-integrated source set.

Runnable cases:

- `SIM_001_RESET_DEFAULTS`
- `SIM_002_CSR_STAGE_PREFIX`
- `SIM_003_FULL_PAGE_PROGRAM`
- `SIM_004_PARTIAL_ODD`
- `SIM_005_BACK_TO_BACK_SNAPSHOT`
- `SIM_006_LAUNCH_REJECTS`
- `SIM_007_SW_RESET_FLUSH`
- `SIM_008_FAULT_INJECTION`

Run examples:

- single case
```bash
RUN_SYNTH_PARITY_CHECKS=0 ./run_questa_sim_003_full_page_program.sh
```
- all 8 cases with Qsys/package parity preflight
```bash
./run_questa_quick_regression.sh
```

Current status:

- all eight `SIM_*` cases pass
- `run_questa_quick_regression.sh` also passes after regenerating
  `debug_sc_system.qsys` and `feb_system.qsys`
- the shared model wrapper now overrides `STATUS_POLL_LIMIT=1024` for
  simulation only; the synthesized RTL default remains `50000`
