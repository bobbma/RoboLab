#!/usr/bin/env bash
set -euo pipefail

# Start the policy server separately before running this script:
# CUDA_DEVICE_ORDER=PCI_BUS_ID PI05_SERVER_GPU=3 \
#   bash /home/myx/RoboLab/local/run_pi05_server.sh --port=8030
# Defaults use GPU 3 for inference and GPUs 4-7 for simulation.
# To reuse a policy server on GPU 2 / port 8000 with five simulation GPUs:
# PI05_FULL_EVAL_GPUS=3,4,5,6,7 PI05_REMOTE_PORT=8000 bash "$0"

if [[ "${1:-}" == "--help" ]]; then
    cat <<'HELP'
Usage: bash /home/myx/RoboLab/local/run_pi05_full_eval.sh

Start the Pi0.5 server separately first:
  CUDA_DEVICE_ORDER=PCI_BUS_ID PI05_SERVER_GPU=3 \
    bash /home/myx/RoboLab/local/run_pi05_server.sh --port=8030

Environment variables:
  PI05_FULL_EVAL_GPUS     Simulation GPU indices, comma-separated (4,5,6,7)
  PI05_REMOTE_PORT       Existing local policy server port (8030)
  PI05_EPISODES_PER_TASK  Fixed episodes per task (100)
  PI05_VIDEO_MODE        none, all, viewport, or sensor (none)

Runs all benchmark tasks, then writes success_rate_cp95.csv in a new
directory under /mnt/38_store/myx/robolab/output. Each worker has its own
output directory, log, and GPU-specific cache. Does not start a policy server.

Per-task intervals are two-sided 95% Clopper-Pearson intervals. The pooled
interval assumes a common binomial probability; it is not an exact interval
for the equal-weight mean of heterogeneous task success probabilities.
HELP
    exit 0
fi
if (($#)); then
    printf 'Unexpected argument. Use --help or the documented environment variables.\n' >&2
    exit 2
fi

IFS=',' read -r -a GPUS <<< "${PI05_FULL_EVAL_GPUS:-4,5,6,7}"
PORT="${PI05_REMOTE_PORT:-8030}"
export N="${PI05_EPISODES_PER_TASK:-10}"
VIDEO_MODE="${PI05_VIDEO_MODE:-none}"
PY="/mnt/38_store/myx/robolab/venv-robolab-51/bin/python"
LAUNCHER="/home/myx/RoboLab/local/run_isaac60_container.sh"

[[ "$N" =~ ^[1-9][0-9]*$ && "$PORT" =~ ^[1-9][0-9]*$ ]] || {
    printf 'Episode count and port must be positive integers.\n' >&2
    exit 2
}
case "$VIDEO_MODE" in
    none|all|viewport|sensor) ;;
    *) printf 'Invalid PI05_VIDEO_MODE: %s\n' "$VIDEO_MODE" >&2; exit 2 ;;
esac
declare -A SELECTED_GPUS=()
for gpu in "${GPUS[@]}"; do
    [[ "$gpu" =~ ^[0-9]+$ && -z "${SELECTED_GPUS[$gpu]:-}" ]] || {
        printf 'GPU indices must be nonempty, numeric, and unique: %s\n' "$gpu" >&2
        exit 2
    }
    SELECTED_GPUS[$gpu]=1
done
((${#GPUS[@]})) || { printf 'No simulation GPUs selected.\n' >&2; exit 2; }

export RUN="pi05-full-$(date -u +%Y%m%dT%H%M%SZ)-$$"
export ROOT="/mnt/38_store/myx/robolab/output/$RUN"
mkdir -p "$ROOT"

# Discover class names without importing Isaac Sim or starting a renderer.
"$PY" - <<'PY'
import ast
import os
from pathlib import Path

root = Path("/home/myx/RoboLab/robolab/tasks/benchmark")
names = []
for path in sorted(root.rglob("*.py")):
    relative = path.relative_to(root)
    if any(p.startswith("_") or p in {"tmp", "not_used"}
           for p in relative.parts[:-1]):
        continue
    if path.name.startswith(".") or path.name == "__init__.py":
        continue
    classes = [
        node.name for node in ast.parse(path.read_text()).body
        if isinstance(node, ast.ClassDef)
        and any(isinstance(base, ast.Name) and base.id == "Task"
                for base in node.bases)
    ]
    assert len(classes) == 1, (path, classes)
    names.extend(classes)

assert names and len(names) == len(set(names))
Path(os.environ["ROOT"], "tasks.txt").write_text(
    "\n".join(sorted(names)) + "\n"
)
print(f"Tasks: {len(names)}; episodes per task: {os.environ['N']}")
PY

mapfile -t ALL_TASKS < "$ROOT/tasks.txt"
PIDS=()
for index in "${!GPUS[@]}"; do
    gpu="${GPUS[$index]}"
    TASKS=()
    for ((j=index; j<${#ALL_TASKS[@]}; j+=${#GPUS[@]})); do
        TASKS+=("${ALL_TASKS[$j]}")
    done
    ((${#TASKS[@]})) || continue

    (
        export PI05_EVAL_GPU="$gpu"
        # Transform only this invocation; leave the shared launcher unchanged.
        # Background jobs cannot use Docker -it. Isolate caches between GPUs.
        sed \
          -e 's/run -it --rm/run --rm/' \
          -e 's|^base=.*|base="/mnt/38_store/myx/robolab/docker/isaac60/gpu${PI05_EVAL_GPU}"|' \
          "$LAUNCHER" |
        bash -s -- \
          "policies/pi0_family/run.py" \
          --policy pi05 --headless --device cuda:0 \
          --remote-host localhost --remote-port "$PORT" \
          --task-dirs benchmark --task "${TASKS[@]}" \
          --num-envs 1 --num-runs "$N" \
          --video-mode "$VIDEO_MODE" \
          --output-folder-name "$RUN/gpu$gpu"
    ) > "$ROOT/gpu$gpu.log" 2>&1 &

    PIDS+=("$!")
    printf 'GPU %s: %s tasks. Log: %s\n' \
      "$gpu" "${#TASKS[@]}" "$ROOT/gpu$gpu.log"
done

failed=0
for pid in "${PIDS[@]}"; do
    wait "$pid" || failed=1
done
if ((failed)); then
    printf 'An evaluation worker failed. Check logs in %s; no full-run summary generated.\n' "$ROOT" >&2
    exit 1
fi

"$PY" - <<'PY'
import csv
import json
import os
from collections import defaultdict
from pathlib import Path

from scipy.stats import beta

root = Path(os.environ["ROOT"])
expected_n = int(os.environ["N"])
expected_tasks = set((root / "tasks.txt").read_text().splitlines())
groups = defaultdict(list)
seen = set()

for path in sorted(root.glob("gpu*/episode_results.jsonl")):
    for line in path.read_text().splitlines():
        row = json.loads(line)
        key = (row["env_name"], row["episode"])
        assert key not in seen, f"Duplicate episode: {key}"
        seen.add(key)
        assert isinstance(row["success"], bool), row
        groups[row["task_name"]].append(int(row["success"]))

assert set(groups) == expected_tasks, "Missing or unexpected tasks"
assert all(len(v) == expected_n for v in groups.values()), \
    "Incomplete episode counts"

def summarize(name, values):
    k, n = sum(values), len(values)
    lo = 0.0 if k == 0 else beta.ppf(0.025, k, n-k+1)
    hi = 1.0 if k == n else beta.ppf(0.975, k+1, n-k)
    return [name, k, n, 100*k/n, 100*lo, 100*hi]

rows = [summarize(name, groups[name]) for name in sorted(groups)]
total = summarize(
    "POOLED_BINOMIAL",
    [value for values in groups.values() for value in values],
)
rows.append(total)

path = root / "success_rate_cp95.csv"
with path.open("w", newline="") as f:
    writer = csv.writer(f)
    writer.writerow([
        "task", "successes", "episodes", "success_rate_pct",
        "cp95_low_pct", "cp95_high_pct",
    ])
    writer.writerows(rows)

print(f"Completed: {len(groups)} tasks, {total[2]} episodes")
print(f"Overall success rate: {total[3]:.2f}% ({total[1]}/{total[2]})")
print(f"Pooled-binomial 95% CP CI: [{total[4]:.2f}%, {total[5]:.2f}%]")
print("Pooled CI assumes a common binomial probability across episodes; "
      "it is not an exact CI for a heterogeneous task mean.")
print(f"Per-task and pooled results: {path}")
PY
