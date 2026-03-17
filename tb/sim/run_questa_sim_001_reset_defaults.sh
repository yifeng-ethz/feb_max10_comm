#!/usr/bin/env bash
set -euo pipefail
"$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/run_questa_case.sh" 1 "SIM_001_RESET_DEFAULTS_PASS" "work_sim_001_reset_defaults"
