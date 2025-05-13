#!/usr/bin/env nextflow

nextflow.enable.dsl = 2 // Assuming DSL2 is still desired for this file

// Process definitions from main_sorters_slurm.nf
// Note: DSL version and specific Slurm configurations (like clusterOptions, module, queue) are kept as per main_sorters_slurm.nf
// If these are not applicable for the Code Ocean environment where sorters_workflows.nf might be included,
// they might need adjustment or conditional logic.

process preprocess {
    tag 'preprocess'
    // DSL1 style container definition from slurm script, adjust if necessary for DSL2 context
    def container_name = "ghcr.io/allenneuraldynamics/aind-ephys-pipeline-base:${params.container_tag}"
    container container_name

    cpus 32
    memory '128 GB'

    input:
    path hybrid_generation_recordings // Matched to subworkflow 'take'
    path ecephys_session_input      // Matched to subworkflow 'take'

    output:
    path "capsule/results/*"

    script:
    """
    #!/usr/bin/env bash
    set -e

    export CO_CAPSULE_ID=05eaf483-9ca3-4a9e-8da8-7d23717f6faf
    export CO_CPUS=${task.cpus}
    export CO_MEMORY=${task.memory.bytes}

    mkdir -p capsule
    mkdir -p capsule/data && ln -s \$PWD/capsule/data /data
    mkdir -p capsule/results && ln -s \$PWD/capsule/results /results
    mkdir -p capsule/scratch && ln -s \$PWD/capsule/scratch /scratch

    # Link input data correctly
    # Assuming hybrid_generation_recordings is a directory of files
    cp -RL ${hybrid_generation_recordings}/* capsule/data/
    # Assuming ecephys_session_input is a directory
    mkdir -p capsule/data/ecephys_session
    cp -RL ${ecephys_session_input}/* capsule/data/ecephys_session/


    echo "[${task.tag}] cloning git repo..."
    git clone "https://github.com/AllenNeuralDynamics/aind-ephys-preprocessing.git" capsule-repo
    git -C capsule-repo -c core.fileMode=false checkout ${versions['PREPROCESSING']} --quiet
    mv capsule-repo/code capsule/code
    rm -rf capsule-repo

    echo "[${task.tag}] running capsule..."
    cd capsule/code
    chmod +x run
    ./run ${params.preprocess_args ?: ''}

    echo "[${task.tag}] completed!"
    """
}

process spikesort_kilosort25 {
    tag 'spikesort_kilosort25'
    def container_name = "ghcr.io/allenneuraldynamics/aind-ephys-spikesort-kilosort25:${params.container_tag}"
    container container_name
    containerOptions '--nv' // From slurm script
    clusterOptions '--gres=gpu:1' // From slurm script
    module 'cuda' // From slurm script
    // queue params.gpu_queue ?: params.default_queue // From slurm script, may need params.default_queue defined

    cpus 16
    memory '64 GB' // Adjusted from 61GB in previous dsl2 to 64GB from slurm

    input:
    path preprocess_results // Matched to subworkflow connection

    output:
    path "capsule/results/*"

    script:
    """
    #!/usr/bin/env bash
    set -e

    export CO_CAPSULE_ID=9c169ec3-5933-4b10-808b-6fa4620e37b7
    export CO_CPUS=${task.cpus}
    export CO_MEMORY=${task.memory.bytes} // slurm script had 68719476736 (64GB)

    mkdir -p capsule
    mkdir -p capsule/data && ln -s \$PWD/capsule/data /data
    mkdir -p capsule/results && ln -s \$PWD/capsule/results /results
    mkdir -p capsule/scratch && ln -s \$PWD/capsule/scratch /scratch

    # Link input data correctly
    cp -RL ${preprocess_results}/* capsule/data/

    echo "[${task.tag}] cloning git repo..."
    git clone "https://github.com/AllenNeuralDynamics/aind-ephys-spikesort-kilosort25.git" capsule-repo
    git -C capsule-repo -c core.fileMode=false checkout ${versions['SPIKESORT_KS25']} --quiet
    mv capsule-repo/code capsule/code
    rm -rf capsule-repo

    echo "[${task.tag}] running capsule..."
    cd capsule/code
    chmod +x run
    ./run ${params.spikesort_kilosort25_args ?: ''}

    echo "[${task.tag}] completed!"
    """
}

process spikesort_kilosort4 {
    tag 'spikesort_kilosort4'
    def container_name = "ghcr.io/allenneuraldynamics/aind-ephys-spikesort-kilosort4:${params.container_tag}"
    container container_name
    containerOptions '--nv' // From slurm script
    clusterOptions '--gres=gpu:1' // From slurm script
    module 'cuda' // From slurm script
    // queue params.gpu_queue ?: params.default_queue // From slurm script

    cpus 16
    memory '64 GB'

    input:
    path preprocess_results // Matched to subworkflow connection

    output:
    path "capsule/results/*"

    script:
    """
    #!/usr/bin/env bash
    set -e

    export CO_CAPSULE_ID=e41ff24a-791c-4a11-a810-0106707d3617
    export CO_CPUS=${task.cpus}
    export CO_MEMORY=${task.memory.bytes}

    mkdir -p capsule
    mkdir -p capsule/data && ln -s \$PWD/capsule/data /data
    mkdir -p capsule/results && ln -s \$PWD/capsule/results /results
    mkdir -p capsule/scratch && ln -s \$PWD/capsule/scratch /scratch

    # Link input data correctly
    cp -RL ${preprocess_results}/* capsule/data/

    echo "[${task.tag}] cloning git repo..."
    git clone "https://github.com/AllenNeuralDynamics/aind-ephys-spikesort-kilosort4.git" capsule-repo
    git -C capsule-repo -c core.fileMode=false checkout ${versions['SPIKESORT_KS4']} --quiet
    mv capsule-repo/code capsule/code
    rm -rf capsule-repo

    echo "[${task.tag}] running capsule..."
    cd capsule/code
    chmod +x run
    ./run ${params.spikesort_kilosort4_args ?: ''}

    echo "[${task.tag}] completed!"
    """
}

process spikesort_spykingcircus2 {
    tag 'spikesort_spykingcircus2'
    def container_name = "ghcr.io/allenneuraldynamics/aind-ephys-spikesort-spykingcircus2-dev:${params.container_tag}"
    container container_name

    cpus 32
    memory '128 GB'

    input:
    path preprocess_results // Matched to subworkflow connection

    output:
    path "capsule/results/*"

    script:
    """
    #!/usr/bin/env bash
    set -e

    export CO_CAPSULE_ID=b68f9aec-7e8d-4862-865a-38081f5a6aeb
    export CO_CPUS=${task.cpus}
    export CO_MEMORY=${task.memory.bytes}

    mkdir -p capsule
    mkdir -p capsule/data && ln -s \$PWD/capsule/data /data
    mkdir -p capsule/results && ln -s \$PWD/capsule/results /results
    mkdir -p capsule/scratch && ln -s \$PWD/capsule/scratch /scratch

    # Link input data correctly
    cp -RL ${preprocess_results}/* capsule/data/

    echo "[${task.tag}] cloning git repo..."
    git clone "https://github.com/AllenNeuralDynamics/aind-ephys-spikesort-spykingcircus2.git" capsule-repo
    git -C capsule-repo -c core.fileMode=false checkout ${versions['SPIKESORT_SC2']} --quiet
    mv capsule-repo/code capsule/code
    rm -rf capsule-repo

    echo "[${task.tag}] running capsule..."
    cd capsule/code
    chmod +x run
    ./run ${params.spikesort_spykingcircus2_args ?: ''}

    echo "[${task.tag}] completed!"
    """
}

// Subworkflow for preprocess + Kilosort2.5
workflow spike_sorting_kilosort25 {
    take:
        hybrid_recordings_ch // Channel: output from hybrid_generation (recordings)
        ecephys_input_ch     // Channel: ecephys session input

    main:
        // Ensure versions map is available if params.capsule_versions is used by processes
        // This might require passing 'versions' or making it globally available if not already
        def versions_map = [:]
        if (params.capsule_versions) {
            file(params.capsule_versions).eachLine { line ->
                def (key, value) = line.tokenize('=')
                versions_map[key] = value
            }
        } else {
            // Define default versions or handle error if versions are crucial
            println "Warning: params.capsule_versions not defined. Processes might fail if they rely on 'versions'."
        }
        
        preprocess_ch = preprocess(
            hybrid_recordings_ch.flatten(), 
            ecephys_input_ch.collect()      
        )
        // Pass versions to process if it's scoped locally, or ensure it's global
        spikesort_kilosort25_ch = spikesort_kilosort25(preprocess_ch.out)

    emit:
        kilosort25_results = spikesort_kilosort25_ch.out
}

// Subworkflow for preprocess + Kilosort4
workflow spike_sorting_kilosort4 {
    take:
        hybrid_recordings_ch 
        ecephys_input_ch     

    main:
        def versions_map = [:]
        if (params.capsule_versions) {
            file(params.capsule_versions).eachLine { line ->
                def (key, value) = line.tokenize('=')
                versions_map[key] = value
            }
        }
        
        preprocess_ch = preprocess(
            hybrid_recordings_ch.flatten(),
            ecephys_input_ch.collect()
        )
        spikesort_kilosort4_ch = spikesort_kilosort4(preprocess_ch.out)

    emit:
        kilosort4_results = spikesort_kilosort4_ch.out
}

// Subworkflow for preprocess + SpykingCircus2
workflow spike_sorting_spykingcircus2 {
    take:
        hybrid_recordings_ch 
        ecephys_input_ch     

    main:
        def versions_map = [:]
        if (params.capsule_versions) {
            file(params.capsule_versions).eachLine { line ->
                def (key, value) = line.tokenize('=')
                versions_map[key] = value
            }
        }

        preprocess_ch = preprocess(
            hybrid_recordings_ch.flatten(),
            ecephys_input_ch.collect()
        )
        spikesort_spykingcircus2_ch = spikesort_spykingcircus2(preprocess_ch.out)

    emit:
        spykingcircus2_results = spikesort_spykingcircus2_ch.out
}
