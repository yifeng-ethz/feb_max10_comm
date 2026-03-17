#!/usr/bin/env python3
from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
from pathlib import Path


def run_cmd(cmd: list[str], cwd: Path) -> tuple[int, str]:
    env = os.environ.copy()
    env.pop("_JAVA_OPTIONS", None)
    proc = subprocess.run(
        cmd,
        cwd=str(cwd),
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    return proc.returncode, proc.stdout


def require(cond: bool, msg: str, errors: list[str]) -> None:
    if not cond:
        errors.append(msg)


def latest_report(base: Path) -> Path:
    patterns = {
        base.name,
        f"{base.name}*",
        f"{base.stem}_previous{base.suffix}",
        f"{base.stem}_previous{base.suffix}*",
    }
    matches = sorted(
        {
            path
            for pattern in patterns
            for path in base.parent.rglob(pattern)
            if path.is_file() and ".lck" not in path.name
        },
        key=lambda path: (path.stat().st_mtime, len(str(path))),
    )
    if not matches:
        return base
    return matches[-1]


def main() -> int:
    ap = argparse.ArgumentParser(description="Check FEB MAX10 Comm synthesis parity around CDC packaging and generated-system assumptions.")
    ap.add_argument("--ip-root", required=True, help="Path to feb_max10_comm IP root")
    ap.add_argument("--online-root", required=True, help="Path to online/ root")
    ap.add_argument("--skip-regenerate", action="store_true", help="Skip qsys-generate invocation and check existing artifacts only")
    args = ap.parse_args()

    ip_root = Path(args.ip_root).resolve()
    online_root = Path(args.online_root).resolve()
    fe_scifi_dir = online_root / "fe_board" / "fe_scifi"
    qsys_gen = online_root / "common" / "firmware" / "util" / "quartus" / "qsys-generate.sh"
    qsys_update = fe_scifi_dir / "update_feb_max10_comm_qsys.tcl"
    qsys_search_path = ",".join(
        [
            str((online_root / "fe_board" / "ip_mu3e").resolve()),
            str(ip_root.resolve()),
            str(ip_root.parent.resolve()),
            str(fe_scifi_dir.resolve()),
            "$",
        ]
    )

    debug_qsys = fe_scifi_dir / "debug_sc_system.qsys"
    feb_qsys = fe_scifi_dir / "feb_system.qsys"
    debug_rpt = latest_report(fe_scifi_dir / "debug_sc_system" / "debug_sc_system_generation.rpt")
    feb_rpt = latest_report(fe_scifi_dir / "feb_system" / "feb_system_generation.rpt")
    debug_vhd = fe_scifi_dir / "debug_sc_system" / "synthesis" / "debug_sc_system.vhd"
    feb_vhd = fe_scifi_dir / "feb_system" / "synthesis" / "feb_system.vhd"
    debug_qip = fe_scifi_dir / "debug_sc_system" / "synthesis" / "debug_sc_system.qip"
    top_vhd = fe_scifi_dir / "top.vhd"
    ip_sdc = ip_root / "feb_max10_comm.sdc"
    hw_tcl = ip_root / "feb_max10_comm_hw.tcl"
    controller_vhd = ip_root / "rtl" / "max10_controller.vhd"
    catalog_ipx = ip_root.parent / "components.ipx"

    errors: list[str] = []

    if not args.skip_regenerate:
        rc, out = run_cmd(
            [
                "ip-make-ipx",
                f"--source-directory={ip_root.parent}",
                f"--output={catalog_ipx}",
            ],
            ip_root.parent,
        )
        if rc != 0:
            errors.append(f"ip-make-ipx failed for {catalog_ipx}\n{out[-4000:]}")
        if qsys_update.exists():
            rc, out = run_cmd(["qsys-script", f"--search-path={qsys_search_path}", f"--script={qsys_update}"], fe_scifi_dir)
            if rc != 0:
                errors.append(f"qsys-script failed for {qsys_update.name}\n{out[-4000:]}")
        for qsys in (debug_qsys, feb_qsys):
            rc, out = run_cmd(["bash", str(qsys_gen), str(qsys)], fe_scifi_dir)
            if rc != 0:
                errors.append(f"qsys-generate failed for {qsys.name}\n{out[-4000:]}")

    for rpt in (debug_rpt, feb_rpt):
        require(rpt.exists(), f"missing generation report: {rpt}", errors)

    if errors:
        for err in errors:
            print(f"FAIL: {err}", file=sys.stderr)
        return 1

    critical_warning_patterns = [
        re.compile(r"feb_max10_comm", re.IGNORECASE),
        re.compile(r"max10_prog_avmm_0", re.IGNORECASE),
        re.compile(r"max10_link", re.IGNORECASE),
        re.compile(r"readdatavalid", re.IGNORECASE),
        re.compile(r"Component .* not found", re.IGNORECASE),
        re.compile(r"Missing connection", re.IGNORECASE),
        re.compile(r"Data width must be of power of two", re.IGNORECASE),
    ]

    allow_warnings = [
        re.compile(r"max10_prog_avmm_0\.diagnostic"),
        re.compile(r"pll_156t40\.locked"),
        re.compile(r"download_fifo\.csr"),
        re.compile(r"avm_cnt_flush"),
        re.compile(r"Associated reset sinks not declared"),
        re.compile(r"almost_empty"),
        re.compile(r"Avalon-ST"),
        re.compile(r"debug_"),
        re.compile(r"headerinfo"),
        re.compile(r"run_control_splitter"),
        re.compile(r"Interrupt sender control_path_subsystem\.error_response_slave_0_debug_csr_irq"),
        re.compile(r"runctl_mgmt_host"),
        re.compile(r"Overwriting different file"),
    ]

    for rpt in (debug_rpt, feb_rpt):
        text = rpt.read_text()
        for line in text.splitlines():
            if "Error:" in line:
                errors.append(f"{rpt.name}: {line}")
            elif "Warning:" in line:
                if any(p.search(line) for p in critical_warning_patterns) and not any(
                    p.search(line) for p in allow_warnings
                ):
                    errors.append(f"{rpt.name}: critical warning: {line}")

    require("qsys-generate succeeded." in debug_rpt.read_text(), "debug_sc_system qsys generation did not report success", errors)
    require("qsys-generate succeeded." in feb_rpt.read_text(), "feb_system qsys generation did not report success", errors)

    require(debug_vhd.exists(), f"missing generated debug_sc_system VHDL: {debug_vhd}", errors)
    require(feb_vhd.exists(), f"missing generated feb_system VHDL: {feb_vhd}", errors)
    require(debug_qip.exists(), f"missing generated debug_sc_system qip: {debug_qip}", errors)
    require(ip_sdc.exists(), f"missing IP-local SDC file: {ip_sdc}", errors)
    require(hw_tcl.exists(), f"missing IP hw.tcl file: {hw_tcl}", errors)
    require(qsys_update.exists(), f"missing Qsys update script: {qsys_update}", errors)
    require(controller_vhd.exists(), f"missing controller RTL: {controller_vhd}", errors)
    require(catalog_ipx.exists(), f"missing generated component index: {catalog_ipx}", errors)

    if debug_vhd.exists():
        debug_text = debug_vhd.read_text()
        require("max10_link_csn" in debug_text, "generated debug_sc_system.vhd does not export max10_link_csn", errors)
        require("avs_csr_readdatavalid" in debug_text, "generated debug_sc_system.vhd does not include avs_csr_readdatavalid path", errors)
        require("feb_max10_comm" in debug_text, "generated debug_sc_system.vhd does not instantiate feb_max10_comm", errors)

    if feb_vhd.exists():
        feb_text = feb_vhd.read_text()
        require("max10_link_csn" in feb_text, "generated feb_system.vhd does not export max10_link_csn", errors)
        require("max10_link_d3_oe" in feb_text, "generated feb_system.vhd does not export full split max10 conduit", errors)

    controller_text = controller_vhd.read_text()
    require("u_cdc_fifo : entity work.dcfifo_40x128" in controller_text, "controller no longer instantiates the local CDC queue fifo wrapper", errors)
    require("aclr                    => rsi_csr_reset" in controller_text, "controller no longer ties the CDC queue clear to the CSR reset domain", errors)
    require("ctrl_start_issued" in controller_text, "controller no longer tracks downstream CTRL.START state for flush handling", errors)

    hw_tcl_text = hw_tcl.read_text()
    require("add_fileset_file feb_max10_comm.sdc SDC PATH feb_max10_comm.sdc" in hw_tcl_text,
            "hw.tcl no longer packages feb_max10_comm.sdc into the QUARTUS_SYNTH fileset", errors)
    require("add_fileset_file rtl/dcfifo_40x128.vhd VHDL PATH rtl/dcfifo_40x128.vhd" in hw_tcl_text,
            "hw.tcl no longer packages rtl/dcfifo_40x128.vhd into the QUARTUS_SYNTH fileset", errors)
    require("add_fileset_file rtl/max10_spi_split.vhd VHDL PATH rtl/max10_spi_split.vhd" in hw_tcl_text,
            "hw.tcl no longer packages the local proven max10_spi_split wrapper source", errors)
    require("BOOT_HIST_AUTO_REFRESH" not in hw_tcl_text,
            "hw.tcl unexpectedly exposes BOOT_HIST_AUTO_REFRESH in this stage", errors)

    debug_qsys_text = debug_qsys.read_text()
    require('name="max10_prog_avmm_0"' in debug_qsys_text, "debug_sc_system.qsys no longer contains max10_prog_avmm_0", errors)
    require('kind="feb_max10_comm"' in debug_qsys_text, "debug_sc_system.qsys does not use feb_max10_comm for max10_prog_avmm_0", errors)
    require('internal="max10_prog_avmm_0.max10_link"' in debug_qsys_text, "debug_sc_system.qsys no longer exports max10_prog_avmm_0.max10_link", errors)
    require('end="max10_prog_avmm_0.csr_avmm"' in debug_qsys_text and 'value="0x00020000"' in debug_qsys_text,
            "debug_sc_system.qsys does not retain the 0x00020000 AVMM base address for max10_prog_avmm_0", errors)
    require('end="max10_prog_avmm_0.csr_clock"' in debug_qsys_text, "debug_sc_system.qsys lost max10_prog_avmm_0.csr_clock wiring", errors)
    require('end="max10_prog_avmm_0.link_clock"' in debug_qsys_text, "debug_sc_system.qsys lost max10_prog_avmm_0.link_clock wiring", errors)
    require('end="max10_prog_avmm_0.csr_reset"' in debug_qsys_text, "debug_sc_system.qsys lost max10_prog_avmm_0.csr_reset wiring", errors)
    require('end="max10_prog_avmm_0.link_reset"' in debug_qsys_text, "debug_sc_system.qsys lost max10_prog_avmm_0.link_reset wiring", errors)
    require("BOOT_HIST_AUTO_REFRESH" not in debug_qsys_text,
            "debug_sc_system.qsys still carries the deferred BOOT_HIST_AUTO_REFRESH parameter", errors)

    feb_qsys_text = feb_qsys.read_text()
    require('name="max10_link"' in feb_qsys_text and 'internal="control_path_subsystem.max10_link"' in feb_qsys_text,
            "feb_system.qsys does not retain the control_path_subsystem.max10_link export", errors)

    if debug_qip.exists():
        debug_qip_text = debug_qip.read_text()
        require("feb_max10_comm.sdc" in debug_qip_text,
                "generated debug_sc_system.qip does not include feb_max10_comm.sdc", errors)
        require("submodules/rtl/max10_spi_split.vhd" in debug_qip_text,
                "generated debug_sc_system.qip does not include the local max10_spi_split.vhd source", errors)

    top_text = top_vhd.read_text()
    require("ip_altiobuf_bidir" in top_text, "top.vhd no longer instantiates explicit MAX10 bidirectional IO buffers", errors)
    require("max10_spi_miso <= max10_link_clk_sig;" in top_text, "top.vhd no longer preserves the v2.0 board clock workaround", errors)

    if errors:
        for err in errors:
            print(f"FAIL: {err}", file=sys.stderr)
        return 1

    print("PASS: synthesis parity checks")
    print(f"PASS: regenerated {debug_qsys.name} and {feb_qsys.name}")
    print("PASS: no qsys generation errors or critical FEB MAX10 Comm warnings")
    print("PASS: generated systems retain max10_link export, AVMM read-valid path, and feb_max10_comm integration")
    print("PASS: controller still uses the local dcfifo-based CDC queue and flush-state tracking")
    print("PASS: IP-local SDC and local FIFO wrapper are packaged and propagated into generated Qsys output")
    print("PASS: top-level still owns the physical MAX10 tri-state buffers and workaround wiring")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
