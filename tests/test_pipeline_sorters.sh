#!/usr/bin/env bash
# Sorters benchmark on the NWB sample. Extra arguments are passed to nextflow (e.g. -resume, --sorters kilosort4).
set -e
source "$(dirname "$(realpath "$0")")/_common.sh"

create_nwb_sample
run_pipeline "$SAMPLE_DATASET_PATH/nwb" "$SAMPLE_DATASET_PATH/nwb/results_sorters" \
    --benchmark sorters --sorters spykingcircus2 $TEST_ARGS "$@"
