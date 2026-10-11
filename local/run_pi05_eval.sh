#!/usr/bin/env bash
set -euo pipefail

source "/home/myx/RoboLab/local/pi05_env.sh"
backend="${PI05_EVAL_BACKEND:-isaac60}"
case "$backend" in
    isaac60)
        launcher=(bash "/home/myx/RoboLab/local/run_isaac60_container.sh")
        ;;
    native51)
        export CUDA_DEVICE_ORDER=PCI_BUS_ID
        export CUDA_VISIBLE_DEVICES="${PI05_EVAL_GPU:-1}"
        launcher=("/mnt/38_store/myx/robolab/venv-robolab-51/bin/python")
        ;;
    *)
        printf 'Unknown PI05_EVAL_BACKEND: %s (expected isaac60 or native51)\n' "$backend" >&2
        exit 2
        ;;
esac

log_dir="$ROBO_DATA_ROOT/logs"
mkdir -p "$log_dir"
log_file="$log_dir/pi05-eval-$(date -u +%Y%m%dT%H%M%SZ)-$$.log"

cd "/home/myx/RoboLab"
printf 'Pi0.5 evaluation started (%s, GPU %s). Full log: %s\n' "$backend" "${PI05_EVAL_GPU:-1}" "$log_file"

PYTHONUNBUFFERED=1 "${launcher[@]}" \
    "policies/pi0_family/run.py" --policy pi05 --headless \
    --task BananaInBowlTask RubiksCubeAndBananaTask \
    --device cuda:0 "$@" 2>&1 | tee "$log_file"
