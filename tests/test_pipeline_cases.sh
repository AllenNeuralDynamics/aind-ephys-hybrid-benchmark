#!/usr/bin/env bash
# Explicit sorting_cases on the NWB sample: highpass vs bandpass, plus a compressed bandpass case
# (sc2_bandpass and sc2_bandpass_wv3 differ in compression, so 3 preprocessing variants).
# Extra arguments are passed to nextflow (e.g. -resume).
set -e
source "$(dirname "$(realpath "$0")")/_common.sh"

SORTING_CASES='{
"sc2_highpass": {"preprocessing": {"params": {"filter_type": "highpass"}}, "spikesort_spykingcircus2": {}},
"sc2_bandpass": {"preprocessing": {"params": {"filter_type": "bandpass"}}, "spikesort_spykingcircus2": {}},
"sc2_bandpass_wv3": {"compress_wavpack": {"params": {"bps": 3}}, "preprocessing": {"params": {"filter_type": "bandpass"}}, "spikesort_spykingcircus2": {}}
}'

create_nwb_sample
run_pipeline "$SAMPLE_DATASET_PATH/nwb" "$SAMPLE_DATASET_PATH/nwb/results_cases" \
    --sorting_cases "$SORTING_CASES" $TEST_ARGS "$@"
