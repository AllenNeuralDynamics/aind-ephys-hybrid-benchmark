# Shared setup for the local test scripts (sourced, not run).
# Needs an env with spikeinterface/pynwb/neuroconv to create the sample data, plus Docker and Nextflow >= 25.10.

SCRIPT_PATH="$(realpath "$0")"
TESTS_PATH="$(dirname "$SCRIPT_PATH")"
PIPELINE_PATH="$(realpath "$TESTS_PATH/..")"
SAMPLE_DATASET_PATH="$PIPELINE_PATH/sample_dataset"
echo "Pipeline path: $PIPELINE_PATH"

# check if nextflow_local_custom.config exists
if [ -f "$PIPELINE_PATH/pipeline/nextflow_local_custom.config" ]; then
    CONFIG_FILE="$PIPELINE_PATH/pipeline/nextflow_local_custom.config"
else
    CONFIG_FILE="$PIPELINE_PATH/pipeline/nextflow_local.config"
fi
echo "Using config file: $CONFIG_FILE"

# the strict syntax parser (default in Nextflow >= 26.04) rejects main.nf
export NXF_SYNTAX_PARSER=v1

# small and fast: clipped sessions, 2 hybrid cases, no motion, no channel removal (synthetic data)
TEST_ARGS="--job_dispatch.input=nwb --job_dispatch.debug=true --job_dispatch.debug_duration=60 \
--hybrid_generation.num_cases=2 --hybrid_generation.correct_motion=false \
--preprocessing.remove_out_channels=false --preprocessing.remove_bad_channels=false"

create_nwb_sample() {
    if [ ! -f "$SAMPLE_DATASET_PATH/nwb/session0.nwb" ]; then
        echo "$SAMPLE_DATASET_PATH/nwb/session0.nwb not found: creating it"
        python "$SAMPLE_DATASET_PATH/create_test_nwb.py"
    fi
}

# run_pipeline DATA_PATH RESULTS_PATH [nextflow args...]
run_pipeline() {
    local data_path="$1"
    local results_path="$2"
    shift 2
    mkdir -p "$results_path/nextflow"
    DATA_PATH="$data_path" RESULTS_PATH="$results_path" nextflow \
        -C "$CONFIG_FILE" -log "$results_path/nextflow/nextflow.log" \
        run "$PIPELINE_PATH/pipeline/main.nf" "$@"
}
