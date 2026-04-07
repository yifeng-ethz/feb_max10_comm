#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ip_dir="$(cd "${script_dir}/../.." && pwd)"
common_tb_dir="${ip_dir}/tb/common"
legacy_sim_dir="${ip_dir}/legacy/max10_prog_avmm/tb/sim"

mentor_sim_bin_dir="/data1/intelFPGA_pro/23.1/questa_fse/bin"
ase_sim_root="/data1/intelFPGA/18.1/modelsim_ase"
ase_sim_bin_dir="${ase_sim_root}/linuxaloem"
if [[ ! -x "${ase_sim_bin_dir}/vsim" ]]; then
  ase_sim_bin_dir="${ase_sim_root}/bin"
fi

sim_flavor="${TB_SIM_FLAVOR:-auto}"
MODELSIM_BIN="${MODELSIM_BIN:-}"
if [[ -z "${MODELSIM_BIN}" ]]; then
  case "${sim_flavor}" in
    mentor) MODELSIM_BIN="${mentor_sim_bin_dir}" ;;
    ase)    MODELSIM_BIN="${ase_sim_bin_dir}" ;;
    auto)
      if [[ -x "${mentor_sim_bin_dir}/vsim" ]]; then
        MODELSIM_BIN="${mentor_sim_bin_dir}"
      elif [[ -x "${ase_sim_bin_dir}/vsim" ]]; then
        MODELSIM_BIN="${ase_sim_bin_dir}"
      else
        MODELSIM_BIN="$(dirname "$(command -v vsim)")"
      fi
      ;;
    *)
      echo "Unknown TB_SIM_FLAVOR='${sim_flavor}' (use: auto|mentor|ase)" >&2
      exit 2
      ;;
  esac
fi

UVM_HOME="${UVM_HOME:-}"
ONLINE_DPV2_ROOT="${ONLINE_DPV2_ROOT:-/home/yifeng/packages/online_dpv2}"
RUN_SYNTH_PARITY_CHECKS="${RUN_SYNTH_PARITY_CHECKS:-1}"
UVM_RUN_MODE="${UVM_RUN_MODE:-run}"

if [[ -z "${UVM_HOME}" ]]; then
  candidate="$(cd "${MODELSIM_BIN}/.." && pwd)/verilog_src/uvm-1.2"
  if [[ -f "${candidate}/src/uvm_pkg.sv" ]]; then
    UVM_HOME="${candidate}"
  fi
fi
export TB_UVM_SRC_DIR="${TB_UVM_SRC_DIR:-${UVM_HOME:+${UVM_HOME}/src}}"

if [[ ! -x "${MODELSIM_BIN}/vsim" ]]; then
  echo "ModelSim not found at: ${MODELSIM_BIN}" >&2
  exit 1
fi

questa_home="$(cd "${MODELSIM_BIN}/.." && pwd)"
default_local_lic="${questa_home}/LR-287689_License.dat"
default_chain="${default_local_lic}:8161@lic-mentor.ethz.ch"
legacy_bad_lic="/data1/intelFPGA/LR-121070_License.dat"

use_default_chain=0
if [[ -z "${LM_LICENSE_FILE:-}" ]]; then
  use_default_chain=1
elif [[ "${LM_LICENSE_FILE}" == *"${legacy_bad_lic}"* ]]; then
  use_default_chain=1
elif [[ "${MODELSIM_BIN}" == "${mentor_sim_bin_dir}" && "${LM_LICENSE_FILE}" != *"8161@lic-mentor.ethz.ch"* ]]; then
  use_default_chain=1
fi

if [[ "${use_default_chain}" == "1" ]]; then
  if [[ -x "${questa_home}/linux_x86_64/lmutil" && -f "${default_local_lic}" ]]; then
    diag_out="$("${questa_home}/linux_x86_64/lmutil" lmdiag -c "${default_chain}" -n intelqsimstarter 2>&1 || true)"
    if printf '%s\n' "${diag_out}" | rg -q "This license can be checked out|This is the correct node for this node-locked license"; then
      LM_LICENSE_FILE="${default_chain}"
    else
      LM_LICENSE_FILE="8182@lic-altera.ethz.ch"
    fi
  else
    LM_LICENSE_FILE="8182@lic-altera.ethz.ch"
  fi
fi
export LM_LICENSE_FILE
export MGLS_LICENSE_FILE="${LM_LICENSE_FILE}"

if [[ "${UVM_RUN_MODE}" != "run_only" && "${RUN_SYNTH_PARITY_CHECKS}" != "0" ]]; then
  python3 "${script_dir}/check_synthesis_parity.py" \
    --ip-root "${ip_dir}" \
    --online-root "${ONLINE_DPV2_ROOT}/online"
fi

cd "${script_dir}"

modelsim_ini="${script_dir}/modelsim.ini"

UVM_DEFINE_ARGS=(+define+UVM_NO_DPI)
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
    UVM_PATCH_DIR="work_uvm_feb_max10_comm/uvm_patched"
    rm -rf "${UVM_PATCH_DIR}"
    mkdir -p "${UVM_PATCH_DIR}"
    cp -a "${UVM_SRC}" "${UVM_PATCH_DIR}/"
    perl -pi -e 's/^export \"DPI-C\" function m__uvm_report_dpi;/`ifndef UVM_NO_DPI\nexport \"DPI-C\" function m__uvm_report_dpi;\n`endif/' "${UVM_PATCH_DIR}/src/base/uvm_globals.svh"
    "${MODELSIM_BIN}/vlog" -modelsimini "${modelsim_ini}" -sv -work work_uvm_feb_max10_comm "${UVM_DEFINE_ARGS[@]}" +incdir+"${UVM_PATCH_DIR}/src" "${UVM_PATCH_DIR}/src/uvm_pkg.sv"
    UVM_INCDIR_ARGS+=(+incdir+"${UVM_PATCH_DIR}/src")
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
    "${UVM_DEFINE_ARGS[@]}" \
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

"${MODELSIM_BIN}/vsim" -modelsimini "${modelsim_ini}" -c -suppress 19 -suppress 3009 -nodpiexports -voptargs="+acc" work_uvm_feb_max10_comm.feb_max10_comm_uvm_tb "${ARGS[@]}" -do "run -all; quit"
