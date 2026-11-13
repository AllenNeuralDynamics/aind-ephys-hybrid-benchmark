#!/usr/bin/env bash
# Lossy compression benchmark on the NWB sample. Extra arguments are passed to nextflow (e.g. -resume).
set -e
source "$(dirname "$(realpath "$0")")/_common.sh"

create_nwb_sample
run_pipeline "$SAMPLE_DATASET_PATH/nwb" "$SAMPLE_DATASET_PATH/nwb/results_lossy" \
    --benchmark lossy --sorter spykingcircus2 --compression_cases lossless,3 $TEST_ARGS "$@"
