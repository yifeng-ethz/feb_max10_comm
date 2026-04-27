#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ip_dir="$(cd "${script_dir}/../.." && pwd)"
common_tb_dir="${ip_dir}/tb/common"
legacy_sim_dir="${ip_dir}/legacy/max10_prog_avmm/tb/sim"
source "${ip_dir}/../scripts/questa_one_env.sh"

MODELSIM_BIN="${MODELSIM_BIN:-$(dirname "${VSIM}")}"

UVM_HOME="${UVM_HOME:-${QUESTA_UVM_HOME}}"
ONLINE_DPV2_ROOT="${ONLINE_DPV2_ROOT:-/home/yifeng/packages/online_dpv2}"
RUN_SYNTH_PARITY_CHECKS="${RUN_SYNTH_PARITY_CHECKS:-1}"
UVM_RUN_MODE="${UVM_RUN_MODE:-run}"
export TB_UVM_SRC_DIR="${TB_UVM_SRC_DIR:-${UVM_HOME:+${UVM_HOME}/src}}"

if [[ ! -x "${MODELSIM_BIN}/vsim" ]]; then
  echo "ModelSim not found at: ${MODELSIM_BIN}" >&2
  exit 1
fi

if [[ "${UVM_RUN_MODE}" != "run_only" && "${RUN_SYNTH_PARITY_CHECKS}" != "0" ]]; then
  python3 "${script_dir}/check_synthesis_parity.py" \
    --ip-root "${ip_dir}" \
    --online-root "${ONLINE_DPV2_ROOT}/online"
fi

cd "${script_dir}"

modelsim_ini="${script_dir}/modelsim.ini"
ARGS=("$@")

if [[ "${UVM_RUN_MODE}" != "run_only" ]]; then
  rm -rf work_uvm_feb_max10_comm altera_mf
  rm -f "${modelsim_ini}"
  "${MODELSIM_BIN}/vlib" work_uvm_feb_max10_comm
  "${MODELSIM_BIN}/vlib" altera_mf
  "${MODELSIM_BIN}/vmap" -c >/dev/null
  "${MODELSIM_BIN}/vmap" -modelsimini "${modelsim_ini}" work_uvm_feb_max10_comm work_uvm_feb_max10_comm >/dev/null
  "${MODELSIM_BIN}/vmap" -modelsimini "${modelsim_ini}" altera_mf altera_mf >/dev/null

  UVM_INCDIR_ARGS=()
  if [[ -n "${UVM_HOME}" ]]; then
    UVM_SRC="${UVM_HOME}/src"
    "${MODELSIM_BIN}/vlog" -modelsimini "${modelsim_ini}" -sv -work work_uvm_feb_max10_comm +incdir+"${UVM_SRC}" "${UVM_SRC}/uvm_pkg.sv"
    UVM_INCDIR_ARGS+=(+incdir+"${UVM_SRC}")
  fi

  "${MODELSIM_BIN}/vcom" -modelsimini "${modelsim_ini}" -2008 -work altera_mf "${legacy_sim_dir}/compat/altera_mf_components.vhd"
  "${MODELSIM_BIN}/vcom" -modelsimini "${modelsim_ini}" -2008 -work altera_mf "${legacy_sim_dir}/compat/dcfifo.vhd"
  "${MODELSIM_BIN}/vcom" -modelsimini "${modelsim_ini}" -2008 -work altera_mf "${legacy_sim_dir}/compat/scfifo.vhd"
  "${MODELSIM_BIN}/vcom" -modelsimini "${modelsim_ini}" -2008 -work work_uvm_feb_max10_comm "${legacy_sim_dir}/compat/scfifo.vhd"
  "${MODELSIM_BIN}/vcom" -modelsimini "${modelsim_ini}" -2008 -work work_uvm_feb_max10_comm "${legacy_sim_dir}/compat/mudaq.vhd"
  "${MODELSIM_BIN}/vcom" -modelsimini "${modelsim_ini}" -2008 -work work_uvm_feb_max10_comm "${legacy_sim_dir}/compat/feb_sc_registers.vhd"
  "${MODELSIM_BIN}/vcom" -modelsimini "${modelsim_ini}" -2008 -work work_uvm_feb_max10_comm "${ip_dir}/rtl/dcfifo_40x128.vhd"
  "${MODELSIM_BIN}/vcom" -modelsimini "${modelsim_ini}" -2008 -work work_uvm_feb_max10_comm "${ip_dir}/rtl/max10_spi_split.vhd"
  "${MODELSIM_BIN}/vcom" -modelsimini "${modelsim_ini}" -2008 -work work_uvm_feb_max10_comm "${ip_dir}/rtl/max10_link.vhd"
  "${MODELSIM_BIN}/vcom" -modelsimini "${modelsim_ini}" -2008 -work work_uvm_feb_max10_comm "${ip_dir}/rtl/max10_controller.vhd"
  "${MODELSIM_BIN}/vcom" -modelsimini "${modelsim_ini}" -2008 -work work_uvm_feb_max10_comm "${ip_dir}/rtl/feb_max10_comm.vhd"
  "${MODELSIM_BIN}/vcom" -modelsimini "${modelsim_ini}" -2008 -work work_uvm_feb_max10_comm "${ONLINE_DPV2_ROOT}/online/fe_board/firmware/FEB_common/max10_interface/max10_spi.vhd"
  "${MODELSIM_BIN}/vcom" -modelsimini "${modelsim_ini}" -2008 -work work_uvm_feb_max10_comm "${legacy_sim_dir}/compat/spi_arria.vhd"
  "${MODELSIM_BIN}/vcom" -modelsimini "${modelsim_ini}" -2008 -work work_uvm_feb_max10_comm "${ONLINE_DPV2_ROOT}/online/fe_board/fe_max10/spiflash/passive_parallel_programmer.vhd"
  "${MODELSIM_BIN}/vcom" -modelsimini "${modelsim_ini}" -2008 -work work_uvm_feb_max10_comm "${ONLINE_DPV2_ROOT}/online/fe_board/fe_max10/spiflash/spiflash.vhd"
  "${MODELSIM_BIN}/vcom" -modelsimini "${modelsim_ini}" -2008 -work work_uvm_feb_max10_comm "${legacy_sim_dir}/compat/flashprogramming_block.vhd"
  "${MODELSIM_BIN}/vcom" -modelsimini "${modelsim_ini}" -2008 -work work_uvm_feb_max10_comm "${legacy_sim_dir}/compat/max10_prog_flash_model.vhd"
  "${MODELSIM_BIN}/vcom" -modelsimini "${modelsim_ini}" -2008 -work work_uvm_feb_max10_comm "${legacy_sim_dir}/compat/max10_prog_downstream_wrapper.vhd"
  "${MODELSIM_BIN}/vcom" -modelsimini "${modelsim_ini}" -2008 -work work_uvm_feb_max10_comm "${common_tb_dir}/feb_max10_comm_model_wrapper.vhd"

  "${MODELSIM_BIN}/vlog" -modelsimini "${modelsim_ini}" -sv -work work_uvm_feb_max10_comm \
    "${UVM_INCDIR_ARGS[@]}" \
    +incdir+"${script_dir}" \
    feb_max10_comm_if.sv \
    feb_max10_comm_pkg.sv \
    feb_max10_comm_uvm_tb.sv
else
  if [[ ! -f "${modelsim_ini}" || ! -d work_uvm_feb_max10_comm || ! -d altera_mf ]]; then
    echo "UVM run_only mode requires an existing compiled workspace in ${script_dir}" >&2
    exit 1
  fi
fi

if [[ "${UVM_RUN_MODE}" == "compile" ]]; then
  echo "UVM compile completed."
  exit 0
fi

"${MODELSIM_BIN}/vsim" -modelsimini "${modelsim_ini}" -c -suppress 19 -suppress 3009 -sv_lib "${QUESTA_UVM_DPI_LIB}" -voptargs="+acc" work_uvm_feb_max10_comm.feb_max10_comm_uvm_tb "${ARGS[@]}" -do "run -all; quit"
