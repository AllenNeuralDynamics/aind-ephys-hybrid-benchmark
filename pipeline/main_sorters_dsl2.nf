#!/usr/bin/env nextflow
// Content primarily from main_sorters_slurm.nf, adapted for DSL2 and subworkflow includes.

nextflow.enable.dsl = 2 // Retaining DSL2 for this file

// Include subworkflows from the updated sorters_workflows.nf
// include { spike_sorting_kilosort25 } from './sorters_workflows.nf'
// include { spike_sorting_kilosort4 } from './sorters_workflows.nf'
// include { spike_sorting_spykingcircus2 } from './sorters_workflows.nf'

// Params from main_sorters_slurm.nf
params.ecephys_path = DATA_PATH

println "DATA_PATH: ${DATA_PATH}"
println "RESULTS_PATH: ${RESULTS_PATH}"
println "PARAMS: ${params}"

params.capsule_versions = "${baseDir}/capsule_versions.env" // Assuming baseDir is appropriate here

// It's good practice to define all expected params, even if with defaults
if (!params.containsKey('job_dispatch_args')) {
    params.job_dispatch_args = ""
}
if (!params.containsKey('preprocessing_args')) {
    params.preprocessing_args = ""
}
if (!params.containsKey('hybrid_generation_args')) {
    params.hybrid_generation_args = ""
}
if (!params.containsKey('spikesorting_args')) {
    params.spikesorting_args = ""
}
if (!params.containsKey('hybrid_evaluation_args')) {
    params.hybrid_evaluation_args = ""
}

if (!params.containsKey("sorters") || params.sorters == "") {
    params.sorters = "ks4+sc2"
}
def sorter_list = params.sorters.split('\\+')

println "Sorters to run: ${sorter_list}"

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
params.container_tag = "si-${versions['SPIKEINTERFACE_VERSION']}"
println "CONTAINER TAG: ${params.container_tag}"

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
    git -C capsule-repo -c core.fileMode=false checkout ${versions['JOB_DISPATCH']}  --quiet
    mv capsule-repo/code capsule/code
    rm -rf capsule-repo

    echo "[${task.tag}] running capsule..."
    cd capsule/code
    chmod +x run
    ./run ${params.job_dispatch_args}

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

process preprocessing {
tag 'preprocessing'
def container_name = "ghcr.io/allenneuraldynamics/aind-ephys-pipeline-base:${params.container_tag}"
    container container_name

input:
    val max_duration_minutes
    path ecephys_session_input, stageAs: 'capsule/data/ecephys_session'
    path job_dispatch_results, stageAs: 'capsule/data/*' // This was hybrid_generation_out.recordings before, check if correct

    output:
    path 'capsule/results/*', emit: results

script:
"""
#!/usr/bin/env bash
set -e

mkdir -p capsule
mkdir -p capsule/data
mkdir -p capsule/results
mkdir -p capsule/scratch

echo "[${task.tag}] cloning git repo..."
git clone "https://github.com/AllenNeuralDynamics/aind-ephys-preprocessing.git" capsule-repo
git -C capsule-repo -c core.fileMode=false checkout ${versions['PREPROCESSING']} --quiet
mv capsule-repo/code capsule/code
rm -rf capsule-repo

echo "[${task.tag}] running capsule..."
cd capsule/code
chmod +x run
./run ${params.preprocessing_args}

echo "[${task.tag}] completed!"
"""
}

process spikesort_kilosort25 {
tag 'spikesort_kilosort25'
def container_name = "ghcr.io/allenneuraldynamics/aind-ephys-spikesort-kilosort25:${params.container_tag}"
    container container_name

    input:
    val max_duration_minutes
    path preprocessing_results, stageAs: 'capsule/data/*'

    output:
    tuple val('ks25'), path('capsule/results')

script:
"""
#!/usr/bin/env bash
set -e

mkdir -p capsule
mkdir -p capsule/data
mkdir -p capsule/results
mkdir -p capsule/scratch

echo "[${task.tag}] cloning git repo..."
git clone "https://github.com/AllenNeuralDynamics/aind-ephys-spikesort-kilosort25.git" capsule-repo
git -C capsule-repo -c core.fileMode=false checkout ${versions['SPIKESORT_KS25']} --quiet
mv capsule-repo/code capsule/code
rm -rf capsule-repo

echo "[${task.tag}] running capsule..."
cd capsule/code
chmod +x run
./run ${params.spikesorting_args}

echo "[${task.tag}] completed!"
"""
}

process spikesort_kilosort4 {
tag 'spikesort_kilosort4'
def container_name = "ghcr.io/allenneuraldynamics/aind-ephys-spikesort-kilosort4:${params.container_tag}"
    container container_name

input:
    val max_duration_minutes
    path preprocessing_results, stageAs: 'capsule/data/*'

    output:
    tuple val('ks4'), path('capsule/results')

script:
"""
#!/usr/bin/env bash
set -e

mkdir -p capsule
mkdir -p capsule/data
mkdir -p capsule/results
mkdir -p capsule/scratch

echo "[${task.tag}] cloning git repo..."
git clone "https://github.com/AllenNeuralDynamics/aind-ephys-spikesort-kilosort4.git" capsule-repo
git -C capsule-repo -c core.fileMode=false checkout ${versions['SPIKESORT_KS4']} --quiet
mv capsule-repo/code capsule/code
rm -rf capsule-repo

echo "[${task.tag}] running capsule..."
cd capsule/code
chmod +x run
./run ${params.spikesorting_args}

echo "[${task.tag}] completed!"
"""
}

process spikesort_spykingcircus2 {
tag 'spikesort_spykingcircus2'
def container_name = "ghcr.io/allenneuraldynamics/aind-ephys-pipeline-base:${params.container_tag}"
    container container_name

input:
    val max_duration_minutes
    path preprocessing_results, stageAs: 'capsule/data/*'

    output:
    tuple val('sc2'), path('capsule/results')

script:
"""
#!/usr/bin/env bash
set -e

mkdir -p capsule
mkdir -p capsule/data
mkdir -p capsule/results
mkdir -p capsule/scratch

echo "[${task.tag}] cloning git repo..."
git clone "https://github.com/AllenNeuralDynamics/aind-ephys-spikesort-spykingcircus2.git" capsule-repo
git -C capsule-repo -c core.fileMode=false checkout ${versions['SPIKESORT_SC2']} --quiet
mv capsule-repo/code capsule/code
rm -rf capsule-repo

echo "[${task.tag}] running capsule..."
cd capsule/code
chmod +x run
./run ${params.spikesorting_args}

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

    // TODO: fix paths!
    def stage_sorter_dirs_str = ""
    if (sorter_results_list && sorter_results_list.size() > 0 && sorter_results_list.size() % 2 == 0) {
        for (int i = 0; i < sorter_results_list.size(); i += 2) {
            def sorter_name = sorter_results_list[i]
            def sorter_path = sorter_results_list[i+1] // This is a Path object
			stage_sorter_dirs_str += "mkdir capsule/data/${sorter_name} && "
            // Ensure sorter_path is converted to string for shell command
            stage_sorter_dirs_str += "cp -rv ${sorter_path.toString()}/* capsule/data/${sorter_name}/"
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

    echo "Raw sorter_results_list in shell: ${sorter_results_list}"
    echo "Generated stage_sorter_dirs commands: ${stage_sorter_dirs_str}"
    ${stage_sorter_dirs_str}

    ls capsule/data

    echo "[${task.tag}] cloning git repo..."
    git clone "https://github.com/AllenNeuralDynamics/aind-ephys-hybrid-evaluation.git" capsule-repo
    git -C capsule-repo -c core.fileMode=false checkout ${versions['HYBRID_EVALUATION']} --quiet
    mv capsule-repo/code capsule/code
    rm -rf capsule-repo

    echo "[${task.tag}] running capsule..."
    cd capsule/code
    chmod +x run
    ./run ${params.hybrid_evaluation_args}

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

    preprocessing_out = preprocessing(
        max_duration_minutes,
        ecephys_ch.collect(),
        hybrid_generation_out.recordings.flatten() // Ensure this is the correct input for preprocessing
    )

    def sorter_results_ch = Channel.empty()

    if ('ks25' in sorter_list) {
        ks25_output_ch = spikesort_kilosort25(max_duration_minutes, preprocessing_out.results)
        sorter_results_ch = sorter_results_ch.mix(ks25_output_ch)
    }
    if ('ks4' in sorter_list) {
        ks4_output_ch = spikesort_kilosort4(max_duration_minutes, preprocessing_out.results)
        sorter_results_ch = sorter_results_ch.mix(ks4_output_ch)
    }
    if ('sc2' in sorter_list) {
        sc2_output_ch = spikesort_spykingcircus2(max_duration_minutes, preprocessing_out.results)
        sorter_results_ch = sorter_results_ch.mix(sc2_output_ch)
    }

    all_sorter_results = sorter_results_ch.collect() // Collects all sorter outputs into a single list emission

    hybrid_evaluation_output_ch = hybrid_evaluation(
        max_duration_minutes,
        ecephys_ch.collect(),
        hybrid_generation_out.flattened.collect(),
        all_sorter_results // This will be the list of [sorter_name, path_to_results] items
    )
}
