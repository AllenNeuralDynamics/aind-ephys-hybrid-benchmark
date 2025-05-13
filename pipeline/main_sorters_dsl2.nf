#!/usr/bin/env nextflow
// Content primarily from main_sorters_slurm.nf, adapted for DSL2 and subworkflow includes.

nextflow.enable.dsl = 2 // Retaining DSL2 for this file

// Include subworkflows from the updated sorters_workflows.nf
include { spike_sorting_kilosort25 } from './sorters_workflows.nf'
include { spike_sorting_kilosort4 } from './sorters_workflows.nf'
include { spike_sorting_spykingcircus2 } from './sorters_workflows.nf'

// Params from main_sorters_slurm.nf
params.ecephys_path = DATA_PATH

println "DATA_PATH: ${DATA_PATH}"
println "RESULTS_PATH: ${RESULTS_PATH}"
println "PARAMS: ${params}"

params.capsule_versions = "${baseDir}/capsule_versions.env" // Assuming baseDir is appropriate here
// params.job_dispatch_args = ""
// params.hybrid_generation_args = ""
// params.hybrid_evaluation_args = "" // Note: slurm script had ./run without args for this
// params.RESULTS_PATH = "./results"

// It's good practice to define all expected params, even if with defaults
params.job_dispatch_args = params.job_dispatch_args ?: ""
params.hybrid_generation_args = params.hybrid_generation_args ?: ""
params.preprocess_args = params.preprocess_args ?: "" // Though preprocess is in subworkflow, its params might be set here
params.spikesort_kilosort25_args = params.spikesort_kilosort25_args ?: ""
params.spikesort_kilosort4_args = params.spikesort_kilosort4_args ?: ""
params.spikesort_spykingcircus2_args = params.spikesort_spykingcircus2_args ?: ""
params.hybrid_evaluation_args = params.hybrid_evaluation_args ?: ""
params.RESULTS_PATH = params.RESULTS_PATH ?: "./results_dsl2"


// Read versions from main_sorters_slurm.nf - this needs to be accessible by included workflows too.
// One way is to pass it to subworkflows if they need it, or ensure it's globally available.
// For simplicity here, we'll assume processes in sorters_workflows.nf can access `versions` if defined globally before workflow block.
// However, explicit passing to subworkflows is safer.
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
    // Provide default empty versions for critical keys if necessary for processes to not fail immediately
    versions['JOB_DISPATCH'] = versions['JOB_DISPATCH'] ?: 'main'
    versions['HYBRID_GENERATION'] = versions['HYBRID_GENERATION'] ?: 'main'
    versions['PREPROCESSING'] = versions['PREPROCESSING'] ?: 'main'
    versions['SPIKESORT_KS25'] = versions['SPIKESORT_KS25'] ?: 'main'
    versions['SPIKESORT_KS4'] = versions['SPIKESORT_KS4'] ?: 'main'
    versions['SPIKESORT_SC2'] = versions['SPIKESORT_SC2'] ?: 'main'
    versions['HYBRID_EVALUATION'] = versions['HYBRID_EVALUATION'] ?: 'main'
}
params.container_tag = params.container_tag ?: "si-${versions.get('SPIKEINTERFACE_VERSION', 'latest')}" // Default if not in versions


// Process definitions from main_sorters_slurm.nf (job_dispatch, hybrid_generation, hybrid_evaluation)
// Adapted for DSL2 syntax where necessary (e.g., container definition)

process job_dispatch {
    tag "job_dispatch-${task.index ?: ''}"
    container "ghcr.io/allenneuraldynamics/aind-ephys-pipeline-base:${params.container_tag}"

    input:
    path ecephys_session_input from Channel.fromPath(params.ecephys_path + "/", type: 'any').collect()

    output:
    path "capsule/results/*"

    script:
    """
    #!/usr/bin/env bash
    set -e

    mkdir -p capsule
    mkdir -p capsule/data && ln -s \$PWD/capsule/data /data
    mkdir -p capsule/results && ln -s \$PWD/capsule/results /results
    mkdir -p capsule/scratch && ln -s \$PWD/capsule/scratch /scratch
    
    mkdir -p capsule/data/ecephys_session
    cp -RL ${ecephys_session_input}/* capsule/data/ecephys_session/

    echo "[${task.tag}] cloning git repo..."
    git clone "https://github.com/AllenNeuralDynamics/aind-ephys-job-dispatch.git" capsule-repo
    git -C capsule-repo -c core.fileMode=false checkout ${versions['JOB_DISPATCH']} --quiet
    mv capsule-repo/code capsule/code
    rm -rf capsule-repo

    echo "[${task.tag}] running capsule..."
    cd capsule/code
    chmod +x run
    ./run ${params.job_dispatch_args}

    echo "[${task.tag}] completed!"
    """
}

process hybrid_generation {
    tag "hybrid_generation-${task.index ?: ''}"
    container "ghcr.io/allenneuraldynamics/aind-ephys-hybrid-generation-dev:${params.container_tag}"

    input:
    path job_dispatch_results from job_dispatch.out.flatten()
    path ecephys_session_input from Channel.fromPath(params.ecephys_path + "/", type: 'any').collect()

    output:
    path "capsule/results/recordings/*"
    path "capsule/results/flattened/*"

    script:
    """
    #!/usr/bin/env bash
    set -e

    mkdir -p capsule
    mkdir -p capsule/data && ln -s \$PWD/capsule/data /data
    mkdir -p capsule/results && ln -s \$PWD/capsule/results /results
    mkdir -p capsule/scratch && ln -s \$PWD/capsule/scratch /scratch

    cp -RL ${job_dispatch_results} capsule/data/
    mkdir -p capsule/data/ecephys_session
    cp -RL ${ecephys_session_input}/* capsule/data/ecephys_session/

    echo "[${task.tag}] cloning git repo..."
    git clone "https://github.com/AllenNeuralDynamics/aind-ephys-hybrid-generation.git" capsule-repo
    git -C capsule-repo -c core.fileMode=false checkout ${versions['HYBRID_GENERATION']} --quiet
    mv capsule-repo/code capsule/code
    rm -rf capsule-repo

    echo "[${task.tag}] running capsule..."
    cd capsule/code
    chmod +x run
    ./run ${params.hybrid_generation_args}

    echo "[${task.tag}] completed!"
    """
}

process hybrid_evaluation {
    tag "hybrid_evaluation-${task.index ?: ''}"
    container "ghcr.io/allenneuraldynamics/aind-ephys-hybrid-evaluation-dev:${params.container_tag}"

    publishDir "${params.RESULTS_PATH}", mode: 'copy', saveAs: { filename -> new File(filename).getName() }

    input:
    path sc2_results from spike_sorting_spykingcircus2.out.spykingcircus2_results.collect()
    path ecephys_session_input from Channel.fromPath(params.ecephys_path + "/", type: 'any').collect()
    path hybrid_generation_flattened from hybrid_generation.out[1].collect() 
    path ks4_results from spike_sorting_kilosort4.out.kilosort4_results.collect()
    path ks25_results from spike_sorting_kilosort25.out.kilosort25_results.collect()


    output:
    path "capsule/results/*"

    script:
    """
    #!/usr/bin/env bash
    set -e

    mkdir -p capsule
    mkdir -p capsule/data && ln -s \$PWD/capsule/data /data
    mkdir -p capsule/results && ln -s \$PWD/capsule/results /results
    mkdir -p capsule/scratch && ln -s \$PWD/capsule/scratch /scratch

    mkdir -p capsule/data/sc2
    cp -RL ${sc2_results}/* capsule/data/sc2/
    mkdir -p capsule/data/ecephys_session
    cp -RL ${ecephys_session_input}/* capsule/data/ecephys_session/
    mkdir -p capsule/data/hybrid_gen_flattened 
    cp -RL ${hybrid_generation_flattened}/* capsule/data/hybrid_gen_flattened/
    mkdir -p capsule/data/ks4
    cp -RL ${ks4_results}/* capsule/data/ks4/
    mkdir -p capsule/data/ks25
    cp -RL ${ks25_results}/* capsule/data/ks25/

    echo "[${task.tag}] cloning git repo..."
    git clone "https://github.com/AllenNeuralDynamics/aind-ephys-hybrid-evaluation.git" capsule-repo
    git -C capsule-repo -c core.fileMode=false checkout ${versions['HYBRID_EVALUATION']} --quiet
    mv capsule-repo/code capsule/code
    rm -rf capsule-repo

    echo "[${task.tag}] running capsule..."
    cd capsule/code
    chmod +x run
    ./run ${params.hybrid_evaluation_args} # slurm script had no args here, dsl2 had params.hybrid_evaluation_args

    echo "[${task.tag}] completed!"
    """
}

workflow {
    // Channel definitions from main_sorters_slurm.nf, adapted for DSL2
    // These are effectively the inputs to the first processes or subworkflows
    main_ecephys_ch = Channel.fromPath(params.ecephys_path + "/", type: 'any')

    // Call processes
    job_dispatch_output_ch = job_dispatch(main_ecephys_ch)
    
    hybrid_generation_output_ch = hybrid_generation(
        job_dispatch_output_ch, // Implicit .out
        main_ecephys_ch
    )

    // Common ecephys input for sorter subworkflows
    ecephys_input_for_sorters_ch = Channel.fromPath(params.ecephys_path + "/", type: 'any')

    // Call subworkflows
    // Pass the 'versions' map to subworkflows if their processes need it and it's not globally visible
    // For now, assuming 'versions' is globally accessible from the definition above the workflow block.
    // If subworkflow processes cannot see 'versions', it must be passed explicitly.
    // e.g. results_ks25 = spike_sorting_kilosort25 (hybrid_generation_output_ch[0], ecephys_input_for_sorters_ch, versions)
    
    results_ks25 = spike_sorting_kilosort25 (
        hybrid_generation_output_ch[0], // recordings
        ecephys_input_for_sorters_ch
    )

    results_ks4 = spike_sorting_kilosort4 (
        hybrid_generation_output_ch[0], // recordings
        ecephys_input_for_sorters_ch
    )

    results_sc2 = spike_sorting_spykingcircus2 (
        hybrid_generation_output_ch[0], // recordings
        ecephys_input_for_sorters_ch
    )

    hybrid_evaluation_output_ch = hybrid_evaluation(
        results_sc2.spykingcircus2_results,
        main_ecephys_ch, // Specific ecephys input for hybrid_evaluation
        hybrid_generation_output_ch[1], // flattened
        results_ks4.kilosort4_results,
        results_ks25.kilosort25_results
    )
}
