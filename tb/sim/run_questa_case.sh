#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 3 ]; then
    echo "usage: $0 <case-id> <pass-token> <work-name>" >&2
    exit 2
fi

case_id="$1"
pass_token="$2"
work_name="$3"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ip_dir="$(cd "${script_dir}/../.." && pwd)"
common_tb_dir="${ip_dir}/tb/common"
legacy_sim_dir="${ip_dir}/legacy/max10_prog_avmm/tb/sim"
work_dir="${TB_WORK_DIR:-${script_dir}/${work_name}}"
source "${ip_dir}/../scripts/questa_one_env.sh"

tb_top="feb_max10_comm_case_tb"

online_dpv2_root="${ONLINE_DPV2_ROOT:-/home/yifeng/packages/online_dpv2}"
run_synth_parity_checks="${RUN_SYNTH_PARITY_CHECKS:-1}"
synth_parity_skip_regenerate="${SYNTH_PARITY_SKIP_REGENERATE:-0}"

vlib_cmd="${VLIB}"
vmap_cmd="${VMAP}"
vcom_cmd="${VCOM}"
vsim_cmd="${VSIM}"

if [ "${run_synth_parity_checks}" != "0" ]; then
    synth_parity_args=()
    if [ "${synth_parity_skip_regenerate}" != "0" ]; then
        synth_parity_args+=(--skip-regenerate)
    fi
    python3 "${script_dir}/../uvm/check_synthesis_parity.py" \
        --ip-root "${ip_dir}" \
        --online-root "${online_dpv2_root}/online" \
        "${synth_parity_args[@]}"
fi

rm -rf -- "${work_dir}"
mkdir -p -- "${work_dir}"
cd -- "${work_dir}"

"${vlib_cmd}" work
"${vlib_cmd}" altera_mf
"${vmap_cmd}" -c >/dev/null
modelsim_ini="${work_dir}/modelsim.ini"
"${vmap_cmd}" -modelsimini "${modelsim_ini}" work work >/dev/null
"${vmap_cmd}" -modelsimini "${modelsim_ini}" altera_mf altera_mf >/dev/null

"${vcom_cmd}" -2008 -modelsimini "${modelsim_ini}" -work altera_mf -quiet "${legacy_sim_dir}/compat/altera_mf_components.vhd"
"${vcom_cmd}" -2008 -modelsimini "${modelsim_ini}" -work altera_mf -quiet "${legacy_sim_dir}/compat/dcfifo.vhd"
"${vcom_cmd}" -2008 -modelsimini "${modelsim_ini}" -work altera_mf -quiet "${legacy_sim_dir}/compat/scfifo.vhd"
"${vcom_cmd}" -2008 -modelsimini "${modelsim_ini}" -work work      -quiet "${legacy_sim_dir}/compat/scfifo.vhd"
"${vcom_cmd}" -2008 -modelsimini "${modelsim_ini}" -work work      -quiet "${legacy_sim_dir}/compat/mudaq.vhd"
"${vcom_cmd}" -2008 -modelsimini "${modelsim_ini}" -work work      -quiet "${legacy_sim_dir}/compat/feb_sc_registers.vhd"
"${vcom_cmd}" -2008 -modelsimini "${modelsim_ini}" -work work      -quiet "${ip_dir}/rtl/dcfifo_40x128.vhd"
"${vcom_cmd}" -2008 -modelsimini "${modelsim_ini}" -work work      -quiet "${ip_dir}/rtl/max10_spi_split.vhd"
"${vcom_cmd}" -2008 -modelsimini "${modelsim_ini}" -work work      -quiet "${ip_dir}/rtl/max10_link.vhd"
"${vcom_cmd}" -2008 -modelsimini "${modelsim_ini}" -work work      -quiet "${ip_dir}/rtl/max10_controller.vhd"
"${vcom_cmd}" -2008 -modelsimini "${modelsim_ini}" -work work      -quiet "${ip_dir}/rtl/feb_max10_comm.vhd"
"${vcom_cmd}" -2008 -modelsimini "${modelsim_ini}" -work work      -quiet "${online_dpv2_root}/online/fe_board/firmware/FEB_common/max10_interface/max10_spi.vhd"
"${vcom_cmd}" -2008 -modelsimini "${modelsim_ini}" -work work      -quiet "${legacy_sim_dir}/compat/spi_arria.vhd"
"${vcom_cmd}" -2008 -modelsimini "${modelsim_ini}" -work work      -quiet "${online_dpv2_root}/online/fe_board/fe_max10/spiflash/passive_parallel_programmer.vhd"
"${vcom_cmd}" -2008 -modelsimini "${modelsim_ini}" -work work      -quiet "${online_dpv2_root}/online/fe_board/fe_max10/spiflash/spiflash.vhd"
"${vcom_cmd}" -2008 -modelsimini "${modelsim_ini}" -work work      -quiet "${legacy_sim_dir}/compat/flashprogramming_block.vhd"
"${vcom_cmd}" -2008 -modelsimini "${modelsim_ini}" -work work      -quiet "${legacy_sim_dir}/compat/max10_prog_flash_model.vhd"
"${vcom_cmd}" -2008 -modelsimini "${modelsim_ini}" -work work      -quiet "${legacy_sim_dir}/compat/max10_prog_downstream_wrapper.vhd"
"${vcom_cmd}" -2008 -modelsimini "${modelsim_ini}" -work work      -quiet "${common_tb_dir}/feb_max10_comm_model_wrapper.vhd"
"${vcom_cmd}" -2008 -modelsimini "${modelsim_ini}" -work work      -quiet "${script_dir}/feb_max10_comm_tb_pkg.vhd"
"${vcom_cmd}" -2008 -modelsimini "${modelsim_ini}" -work work      -quiet "${script_dir}/feb_max10_comm_case_tb.vhd"

log_file="${work_dir}/vsim.log"
"${vsim_cmd}" -modelsimini "${modelsim_ini}" -c -quiet -suppress 3116 "work.${tb_top}" -gCASE_ID_G="${case_id}" -do "run -all; quit -f" | tee "${log_file}"

if rg -n "\\*\\* Fatal:|\\*\\* Error:|^Fatal:" "${log_file}" >/dev/null; then
    echo "FAIL: ${tb_top} case ${case_id}" >&2
    exit 1
fi
if ! rg -q "${pass_token}" "${log_file}"; then
    echo "FAIL: ${tb_top} case ${case_id} (pass token missing)" >&2
    exit 1
fi

echo "PASS: ${tb_top} case ${case_id}"
