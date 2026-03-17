#!/usr/bin/env bash
set -euo pipefail
"$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/run_questa_case.sh" 5 "SIM_005_BACK_TO_BACK_SNAPSHOT_PASS" "work_sim_005_back_to_back_snapshot"
