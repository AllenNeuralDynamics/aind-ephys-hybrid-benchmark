# this needs to run in an env with spikeinterface/pynwb/neuroconv installed

NXF_VER=25.04.1

# get all input arguments into a variable
INPUT_ARGS="$@"
echo "Input arguments: $INPUT_ARGS"

SCRIPT_PATH="$(realpath "$0")"
echo "Running script at: $SCRIPT_PATH"

SAMPLE_DATASET_PATH="$(realpath $(dirname "$SCRIPT_PATH")/../sample_dataset)"
echo "Sample dataset path: $SAMPLE_DATASET_PATH"

PIPELINE_PATH="$(realpath $(dirname "$SCRIPT_PATH")/..)"
echo "Pipeline path: $PIPELINE_PATH"

# check if sample_dataset/nwb/sample.nwb exists
if [ ! -f "$SAMPLE_DATASET_PATH/nwb/sample.nwb" ]; then
    echo "$SAMPLE_DATASET_PATH/nwb/sample.nwb not found"
    python $SAMPLE_DATASET_PATH/create_test_nwb.py
else
    echo "$SAMPLE_DATASET_PATH/nwb/sample.nwb exists"
fi

# define INPUT and OUTPUT directories
DATA_PATH="$SAMPLE_DATASET_PATH/nwb"
RESULTS_PATH="$SAMPLE_DATASET_PATH/nwb/results"

# run pipeline
NXF_VER=$NXF_VER DATA_PATH=$DATA_PATH RESULTS_PATH=$RESULTS_PATH nextflow \
    -C $PIPELINE_PATH/pipeline/nextflow_local.config \
    -log $RESULTS_PATH/nextflow/nextflow.log \
    run $PIPELINE_PATH/pipeline/main_sorters_dsl2.nf \
    --job_dispatch_args "--input nwb" --hybrid_generation_args "--num-cases 2 --skip-correct-motion" \
    --preprocessing_args "--no-remove-out-channels --no-remove-bad-channels" $INPUT_ARGS