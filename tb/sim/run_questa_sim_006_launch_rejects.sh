#!/usr/bin/env bash
set -euo pipefail
"$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/run_questa_case.sh" 6 "SIM_006_LAUNCH_REJECTS_PASS" "work_sim_006_launch_rejects"
