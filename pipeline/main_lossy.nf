#!/usr/bin/env nextflow
// Content primarily from main_sorters_slurm.nf, adapted for DSL2 and subworkflow includes.

nextflow.enable.dsl = 2 // Retaining DSL2 for this file

// Include subworkflows from the updated sorters_workflows.nf
include { lossless } from './spike_sorting_cases.nf'
include { wavpack_3 } from './spike_sorting_cases.nf'
include { wavpack_2_5 } from './spike_sorting_cases.nf'
include { wavpack_2_25 } from './spike_sorting_cases.nf'

// Params from main_sorters_slurm.nf
params.ecephys_path = DATA_PATH

println "DATA_PATH: ${DATA_PATH}"
println "RESULTS_PATH: ${RESULTS_PATH}"
println "PARAMS: ${params}"

params.capsule_versions = "${baseDir}/capsule_versions.env" // Assuming baseDir is appropriate here
// Read versions from main_sorters_slurm.nf - this needs to be accessible by included workflows too.
def versions = [:]
if (file(params.capsule_versions).exists()) {
    file(params.capsule_versions).eachLine { line ->
        if (line.contains('=')) {
            def (key, value) = line.tokenize('=')
            versions[key.trim()] = value.trim()
        }
    }
} else {
    println "Warning: Capsule versions file not found at ${params.capsule_versions}. Using empty versions map."
    versions['JOB_DISPATCH'] = versions['JOB_DISPATCH'] ?: 'main'
    versions['HYBRID_GENERATION'] = versions['HYBRID_GENERATION'] ?: 'main'
    versions['PREPROCESSING'] = versions['PREPROCESSING'] ?: 'main'
    versions['SPIKESORT_KS25'] = versions['SPIKESORT_KS25'] ?: 'main'
    versions['SPIKESORT_KS4'] = versions['SPIKESORT_KS4'] ?: 'main'
    versions['SPIKESORT_SC2'] = versions['SPIKESORT_SC2'] ?: 'main'
    versions['HYBRID_EVALUATION'] = versions['HYBRID_EVALUATION'] ?: 'main'
}
params.versions = versions

params.container_tag = "si-${params.versions['SPIKEINTERFACE_VERSION']}"
println "CONTAINER TAG: ${params.container_tag}"


// It's good practice to define all expected params, even if with defaults
if (!params.containsKey('job_dispatch_args')) {
    job_dispatch_args = "--multi-session"
}
else {
    job_dispatch_args = params.job_dispatch_args
}
if (!params.containsKey('preprocessing_args')) {
    preprocessing_args = ""
}
else {
    preprocessing_args = params.preprocessing_args
}
if (!params.containsKey('hybrid_generation_args')) {
    hybrid_generation_args = ""
}
else {
    hybrid_generation_args = params.hybrid_generation_args
}
if (!params.containsKey('spikesorting_args')) {
    spikesorting_args = ""
}
else {
    spikesorting_args = params.spikesorting_args
}
if (!params.containsKey('hybrid_evaluation_args')) {
    hybrid_evaluation_args = ""
}
else {
    hybrid_evaluation_args = params.hybrid_evaluation_args
}
// make it multi-session by default
if (!job_dispatch_args.contains("--multi-session")) {
    println "Adding --multi-session to job_dispatch_args"
    job_dispatch_args += " --multi-session"
    println "job_dispatch_args: ${job_dispatch_args}"
}

if (!params.containsKey("sorting_cases")){
    params.sorting_cases = "lossless+wv-3+wv-2.5+wv-2.25"
}
else {
    println "Using sorting cases from params"
}

println "Sorter to run: ${params.sorter}"
def sorting_cases_list = params.sorting_cases.split('\\+')
println "Spike sorting cases to run: ${sorting_cases_list}"

process job_dispatch {
    tag 'job-dispatch'
    def container_name = "ghcr.io/allenneuraldynamics/aind-ephys-pipeline-base:${params.container_tag}"
    container container_name

    input:
    path input_folder, stageAs: 'capsule/data/ecephys_session'
    
    output:
    path 'capsule/results/*', emit: results
    path 'max_duration.txt', emit: max_duration_file

    script:
    """
    #!/usr/bin/env bash
    set -e

    mkdir -p capsule
    mkdir -p capsule/data
    mkdir -p capsule/results
    mkdir -p capsule/scratch

    if [[ \$(params.executor ?: '') == "slurm" ]]; then
        echo "[${task.tag}] allocated task time: ${task.time}"
    fi

    TASK_DIR=\$(pwd)

    echo "[${task.tag}] cloning git repo..."
    git clone "https://github.com/AllenNeuralDynamics/aind-ephys-job-dispatch.git" capsule-repo
    git -C capsule-repo -c core.fileMode=false checkout ${params.versions['JOB_DISPATCH']}  --quiet
    mv capsule-repo/code capsule/code
    rm -rf capsule-repo

    echo "[${task.tag}] running capsule..."
    cd capsule/code
    chmod +x run
    ./run ${job_dispatch_args}

    MAX_DURATION_MIN=\$(python get_max_recording_duration_min.py)

    cd \$TASK_DIR
    echo "\$MAX_DURATION_MIN" > max_duration.txt

    echo "[${task.tag}] completed!"
    """
}

process hybrid_generation {
    tag 'hybrid_generation'
    def container_name = "ghcr.io/allenneuraldynamics/aind-ephys-pipeline-base:${params.container_tag}"
    container container_name

    input:
    val max_duration_minutes
    path ecephys_session_input, stageAs: 'capsule/data/ecephys_session'
    path job_dispatch_results, stageAs: 'capsule/data/*'

    output:
    path 'capsule/results/recordings/*', emit: recordings
    path 'capsule/results/flattened/*', emit: flattened

    script:
    """
    #!/usr/bin/env bash
    set -e

    mkdir -p capsule
    mkdir -p capsule/data
    mkdir -p capsule/results
    mkdir -p capsule/scratch

    echo "[${task.tag}] cloning git repo..."
    git clone "https://github.com/AllenNeuralDynamics/aind-ephys-hybrid-generation.git" capsule-repo
    git -C capsule-repo -c core.fileMode=false checkout ${params.versions['HYBRID_GENERATION']} --quiet
    mv capsule-repo/code capsule/code
    rm -rf capsule-repo

    echo "[${task.tag}] running capsule..."
    cd capsule/code
    chmod +x run
    ./run ${hybrid_generation_args}

    echo "[${task.tag}] completed!"
    """
}

process hybrid_evaluation {
    tag 'hybrid_evaluation'
    def container_name = "ghcr.io/allenneuraldynamics/aind-ephys-pipeline-base:${params.container_tag}"
        container container_name

        publishDir "$RESULTS_PATH", saveAs: { filename -> new File(filename).getName() }

    input:
        val max_duration_minutes
        path ecephys_session_input, stageAs: 'capsule/data/ecephys_session'
        path hybrid_gen_results, stageAs: 'capsule/data/*'
        val sorter_results_list

    output:
        path 'capsule/results/*', emit: results

    script:
        // sorter_results_list is expected to be a flat list: [name1, path1, name2, path2, ...]
        // Convert it to a series of cp commands
        def stage_sorter_dirs_str = ""
        def sorter_names = []
        if (sorter_results_list && sorter_results_list.size() > 0 && sorter_results_list.size() % 2 == 0) {
            for (int i = 0; i < sorter_results_list.size(); i += 2) {
                def sorter_name = sorter_results_list[i]
                def sorter_path = sorter_results_list[i+1] // This is a Path object
                if (!sorter_names.contains(sorter_name)) {
                    sorter_names.add(sorter_name)
                    stage_sorter_dirs_str += "mkdir capsule/data/${sorter_name} && "
                }
                // Ensure sorter_path is converted to string for shell command
                stage_sorter_dirs_str += "cp -r ${sorter_path.toString()}/* capsule/data/${sorter_name}/"
                if (i < sorter_results_list.size() - 2) {
                    stage_sorter_dirs_str += " && "
                }
            }
        }
        else {
            stage_sorter_dirs_str = "echo 'Warning: sorter_results_list is empty or null: ${sorter_results_list}'\\n"
        }
        """
        #!/usr/bin/env bash
        set -e

        mkdir -p capsule
        mkdir -p capsule/data
        mkdir -p capsule/results
        mkdir -p capsule/scratch

        echo "Copying output directories"
        ${stage_sorter_dirs_str}

        echo "[${task.tag}] cloning git repo..."
        git clone "https://github.com/AllenNeuralDynamics/aind-ephys-hybrid-evaluation.git" capsule-repo
        git -C capsule-repo -c core.fileMode=false checkout ${params.versions['HYBRID_EVALUATION']} --quiet
        mv capsule-repo/code capsule/code
        rm -rf capsule-repo

        echo "[${task.tag}] running capsule..."
        cd capsule/code
        chmod +x run
        ./run ${hybrid_evaluation_args}

        echo "[${task.tag}] completed!"
        """
}

workflow {
    ecephys_ch = Channel.fromPath(params.ecephys_path + "/", type: 'any')

    job_dispatch_out = job_dispatch(ecephys_ch.collect())

    max_duration_file = job_dispatch_out.max_duration_file
    max_duration_minutes = max_duration_file.map { it.text.trim() }
    max_duration_minutes.view { "Max recording duration: ${it}min" }
    
    hybrid_generation_out = hybrid_generation(
        max_duration_minutes,
        ecephys_ch.collect(),
        job_dispatch_out.results.flatten()
    )

    def sorter_results_ch = Channel.empty()

    if ('lossless' in sorting_cases_list) {
        lossless_output_ch = lossless(
            max_duration_minutes,
            ecephys_ch.collect(),
            hybrid_generation_out.recordings.flatten(),
            params.sorter,
            preprocessing_args,
            spikesorting_args
        )
        sorter_results_ch = sorter_results_ch.mix(lossless_output_ch)
    }
    if ('wv-3' in sorting_cases_list) {
        wv3_output_ch = wavpack_3(
            max_duration_minutes,
            ecephys_ch.collect(),
            hybrid_generation_out.recordings.flatten(),
            params.sorter,
            preprocessing_args,
            spikesorting_args
        )
        sorter_results_ch = sorter_results_ch.mix(wv3_output_ch)
    }
    if ('wv-2.5' in sorting_cases_list) {
        wv25_output_ch = wavpack_2_5(
            max_duration_minutes,
            ecephys_ch.collect(),
            hybrid_generation_out.recordings.flatten(),
            params.sorter,
            preprocessing_args,
            spikesorting_args
        )
        sorter_results_ch = sorter_results_ch.mix(wv25_output_ch)
    }
    if ('wv-2.25' in sorting_cases_list) {
        wv225_output_ch = wavpack_2_25(
            max_duration_minutes,
            ecephys_ch.collect(),
            hybrid_generation_out.recordings.flatten(),
            params.sorter,
            preprocessing_args,
            spikesorting_args
        )
        sorter_results_ch = sorter_results_ch.mix(wv225_output_ch)
    }

    all_sorter_results = sorter_results_ch.collect() // Collects all sorter outputs into a single list emission

    hybrid_evaluation_output_ch = hybrid_evaluation(
        max_duration_minutes,
        ecephys_ch.collect(),
        hybrid_generation_out.flattened.collect(),
        all_sorter_results
    )
}
