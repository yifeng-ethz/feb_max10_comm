#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
online_dpv2_root="${ONLINE_DPV2_ROOT:-/home/yifeng/packages/online_dpv2}"
synth_parity_skip_regenerate="${SYNTH_PARITY_SKIP_REGENERATE:-0}"

synth_parity_args=()
if [ "${synth_parity_skip_regenerate}" != "0" ]; then
    synth_parity_args+=(--skip-regenerate)
fi

python3 "${script_dir}/../uvm/check_synthesis_parity.py" \
    --ip-root "$(cd "${script_dir}/../.." && pwd)" \
    --online-root "${online_dpv2_root}/online" \
    "${synth_parity_args[@]}"

RUN_SYNTH_PARITY_CHECKS=0 "${script_dir}/run_questa_sim_001_reset_defaults.sh"
RUN_SYNTH_PARITY_CHECKS=0 "${script_dir}/run_questa_sim_002_csr_stage_prefix.sh"
RUN_SYNTH_PARITY_CHECKS=0 "${script_dir}/run_questa_sim_003_full_page_program.sh"
RUN_SYNTH_PARITY_CHECKS=0 "${script_dir}/run_questa_sim_004_partial_odd.sh"
RUN_SYNTH_PARITY_CHECKS=0 "${script_dir}/run_questa_sim_005_back_to_back_snapshot.sh"
RUN_SYNTH_PARITY_CHECKS=0 "${script_dir}/run_questa_sim_006_launch_rejects.sh"
RUN_SYNTH_PARITY_CHECKS=0 "${script_dir}/run_questa_sim_007_sw_reset_flush.sh"
RUN_SYNTH_PARITY_CHECKS=0 "${script_dir}/run_questa_sim_008_fault_injection.sh"

echo "PASS: feb_max10_comm tb/sim quick regression"
