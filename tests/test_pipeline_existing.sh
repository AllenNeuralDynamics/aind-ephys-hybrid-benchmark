#!/usr/bin/env bash
# Sorters benchmark on existing hybrid datasets (<session>/<case>/{recording,sorting}.zarr), generated here if missing.
# Extra arguments are passed to nextflow (e.g. -resume).
set -e
source "$(dirname "$(realpath "$0")")/_common.sh"

EXISTING_PATH="$SAMPLE_DATASET_PATH/hybrid_existing"
if [ ! -d "$EXISTING_PATH/session0" ]; then
    echo "$EXISTING_PATH not found: creating it"
    python - "$EXISTING_PATH" <<'EOF'
import sys
from pathlib import Path
import spikeinterface as si

root = Path(sys.argv[1])
for case in ["case0", "case1"]:
    recording, sorting = si.generate_ground_truth_recording(durations=[60], num_channels=32, num_units=10, seed=0)
    recording.save(folder=root / "session0" / case / "recording.zarr", format="zarr")
    sorting.save(folder=root / "session0" / case / "sorting.zarr", format="zarr")
EOF
fi

run_pipeline "$EXISTING_PATH" "$SAMPLE_DATASET_PATH/hybrid_existing_results" \
    --existing --benchmark sorters --sorters spykingcircus2 \
    --preprocessing.remove_out_channels=false --preprocessing.remove_bad_channels=false \
    --job_dispatch.debug=true --job_dispatch.debug_duration=60 "$@"
