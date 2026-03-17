#!/usr/bin/env bash
set -euo pipefail
"$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/run_questa_case.sh" 4 "SIM_004_PARTIAL_ODD_PASS" "work_sim_004_partial_odd"
