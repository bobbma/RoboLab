#!/usr/bin/env bash
set -euo pipefail

mkdir -p "/mnt/38_store/myx/robolab/logs"
log_file="/mnt/38_store/myx/robolab/logs/isaac51-container-check-$(date -u +%Y%m%dT%H%M%SZ)-$$.log"
printf 'Isaac Sim container compatibility check. Full log: %s\n' "$log_file"
bash "/home/myx/RoboLab/local/run_isaac51_container.sh" \
    ./isaac-sim.compatibility_check.sh \
    --/app/quitAfter=10 --no-window "$@" 2>&1 | tee "$log_file"
