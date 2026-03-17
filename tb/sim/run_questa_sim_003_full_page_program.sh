#!/usr/bin/env bash
set -euo pipefail
"$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/run_questa_case.sh" 3 "SIM_003_FULL_PAGE_PROGRAM_PASS" "work_sim_003_full_page_program"
