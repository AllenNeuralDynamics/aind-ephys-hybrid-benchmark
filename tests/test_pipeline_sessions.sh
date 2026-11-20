#!/usr/bin/env bash
# Sorters benchmark on a sessions_file listing two NWB sessions (one job_dispatch task each).
# Extra arguments are passed to nextflow (e.g. -resume).
set -e
source "$(dirname "$(realpath "$0")")/_common.sh"

create_nwb_sample
# two sessions with different names, hard-linked to the same sample file
# (not symlinks: the container may not see their target)
SESSIONS_PATH="$SAMPLE_DATASET_PATH/nwb_sessions"
mkdir -p "$SESSIONS_PATH"
for name in sessionA sessionB; do
    ln -f "$SAMPLE_DATASET_PATH/nwb/session1.nwb" "$SESSIONS_PATH/$name.nwb" 2>/dev/null ||
        cp "$SAMPLE_DATASET_PATH/nwb/session1.nwb" "$SESSIONS_PATH/$name.nwb"
done
printf "# test sessions\n%s\n%s\n" "$SESSIONS_PATH/sessionA.nwb" "$SESSIONS_PATH/sessionB.nwb" > "$SESSIONS_PATH/sessions.txt"

run_pipeline "$SESSIONS_PATH" "$SAMPLE_DATASET_PATH/nwb/results_sessions" \
    --sessions_file "$SESSIONS_PATH/sessions.txt" --sorters spykingcircus2 $TEST_ARGS "$@"
