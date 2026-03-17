#!/usr/bin/env bash
set -euo pipefail
"$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/run_questa_case.sh" 2 "SIM_002_CSR_STAGE_PREFIX_PASS" "work_sim_002_csr_stage_prefix"
