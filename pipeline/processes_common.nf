#!/usr/bin/env nextflow

nextflow.enable.dsl = 2 // Assuming DSL2 is still desired for this file

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
    versions['JOB_DISPATCH_HYBRID'] = versions['JOB_DISPATCH_HYBRID'] ?: 'main'
    versions['HYBRID_GENERATION'] = versions['HYBRID_GENERATION'] ?: 'main'
    versions['HYBRID_EVALUATION'] = versions['HYBRID_EVALUATION'] ?: 'main'
}
params.versions = versions

params.container_tag = "si-${params.versions['SPIKEINTERFACE_VERSION']}"
println "CONTAINER TAG: ${params.container_tag}"

process job_dispatch {
    tag 'job-dispatch'
    def container_name = "ghcr.io/allenneuraldynamics/aind-ephys-pipeline-base:${params.container_tag}"
    container container_name

    input:
    path input_folder, stageAs: 'capsule/data/ecephys_session'
    val job_dispatch_args
    
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


process job_dispatch_hybrid {
    tag 'job-dispatch-hybrid'
    def container_name = "ghcr.io/allenneuraldynamics/aind-ephys-pipeline-base:${params.container_tag}"
    container container_name

    input:
    path input_folder, stageAs: 'capsule/data/ecephys_session'
    val job_dispatch_args
    
    output:
    path 'capsule/results/recordings/*', emit: recordings
    path 'capsule/results/flattened/*', emit: flattened
    path 'max_duration.txt', emit: max_duration_file

    script:
    """
    #!/usr/bin/env bash
    set -e

    if [[ ${params.executor} == "slurm" ]]; then
        # make sure N_JOBS matches allocated CPUs on SLURM
        export CO_CPUS=${task.cpus}
    fi

    mkdir -p capsule
    mkdir -p capsule/data
    mkdir -p capsule/results
    mkdir -p capsule/scratch

    if [[ \$(params.executor ?: '') == "slurm" ]]; then
        echo "[${task.tag}] allocated task time: ${task.time}"
    fi

    TASK_DIR=\$(pwd)

    echo "[${task.tag}] cloning git repo..."
    git clone "https://github.com/AllenNeuralDynamics/aind-ephys-hybrid-job-dispatch.git" capsule-repo
    git -C capsule-repo -c core.fileMode=false checkout ${params.versions['JOB_DISPATCH_HYBRID']}  --quiet
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
    val hybrid_generation_args

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
        val hybrid_evaluation_args

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
