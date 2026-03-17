#!/usr/bin/env bash
set -euo pipefail
"$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/run_questa_case.sh" 7 "SIM_007_SW_RESET_FLUSH_PASS" "work_sim_007_sw_reset_flush"
