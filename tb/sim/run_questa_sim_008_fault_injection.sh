#!/usr/bin/env bash
set -euo pipefail
"$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/run_questa_case.sh" 8 "SIM_008_FAULT_INJECTION_PASS" "work_sim_008_fault_injection"
