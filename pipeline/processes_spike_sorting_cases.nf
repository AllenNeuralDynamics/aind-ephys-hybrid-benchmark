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
    versions['PREPROCESSING'] = versions['PREPROCESSING'] ?: 'main'
    versions['SPIKESORT_KS25'] = versions['SPIKESORT_KS25'] ?: 'main'
    versions['SPIKESORT_KS4'] = versions['SPIKESORT_KS4'] ?: 'main'
    versions['SPIKESORT_SC2'] = versions['SPIKESORT_SC2'] ?: 'main'
}
params.versions = versions

params.container_tag = "si-${params.versions['SPIKEINTERFACE_VERSION']}"
println "CONTAINER TAG: ${params.container_tag}"

process preprocessing {
    tag 'preprocessing'
    def container_name = "ghcr.io/allenneuraldynamics/aind-ephys-pipeline-base:${params.container_tag}"
    container container_name

    input:
    val max_duration_minutes
    path ecephys_session_input, stageAs: 'capsule/data/ecephys_session'
    path job_dispatch_results, stageAs: 'capsule/data/*' // This was hybrid_generation_out.recordings before, check if correct
    val preprocessing_args

    output:
    path 'capsule/results/*', emit: results

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

    echo "[${task.tag}] cloning git repo..."
    git clone "https://github.com/AllenNeuralDynamics/aind-ephys-preprocessing.git" capsule-repo
    git -C capsule-repo -c core.fileMode=false checkout ${params.versions['PREPROCESSING']} --quiet
    mv capsule-repo/code capsule/code
    rm -rf capsule-repo

    echo "[${task.tag}] running capsule..."
    cd capsule/code
    chmod +x run
    ./run ${preprocessing_args}

    echo "[${task.tag}] completed!"
    """
}

process compress_wavpack {
	tag 'compress-wavpack'
	def container_name = "ghcr.io/allenneuraldynamics/aind-ephys-pipeline-base:${params.container_tag}"
    container container_name

    input:
    val max_duration_minutes
    path ecephys_session_input, stageAs: 'capsule/data/ecephys_session'
    path job_dispatch_results, stageAs: 'capsule/data/*' // This was hybrid_generation_out.recordings before, check if correct
    val bps // Bits per sample

    output:
    path 'capsule/results/*', emit: results

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

	echo "[${task.tag}] cloning git repo..."
	git clone "https://github.com/AllenNeuralDynamics/aind-ephys-compress.git" capsule-repo
	git -C capsule-repo -c core.fileMode=false checkout ${params.versions['COMPRESSION']} --quiet
	mv capsule-repo/code capsule/code
	rm -rf capsule-repo

	echo "[${task.tag}] running capsule..."
	cd capsule/code
	chmod +x run
	./run --bps ${bps}

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
    val spikesorting_args

    output:
    tuple val('ks25'), path('capsule/results')

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

    echo "[${task.tag}] cloning git repo..."
    git clone "https://github.com/AllenNeuralDynamics/aind-ephys-spikesort-kilosort25.git" capsule-repo
    git -C capsule-repo -c core.fileMode=false checkout ${params.versions['SPIKESORT_KS25']} --quiet
    mv capsule-repo/code capsule/code
    rm -rf capsule-repo

    echo "[${task.tag}] running capsule..."
    cd capsule/code
    chmod +x run
    ./run ${spikesorting_args}

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
    val spikesorting_args

    output:
    tuple val('ks4'), path('capsule/results')

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

    echo "[${task.tag}] cloning git repo..."
    git clone "https://github.com/AllenNeuralDynamics/aind-ephys-spikesort-kilosort4.git" capsule-repo
    git -C capsule-repo -c core.fileMode=false checkout ${params.versions['SPIKESORT_KS4']} --quiet
    mv capsule-repo/code capsule/code
    rm -rf capsule-repo

    echo "[${task.tag}] running capsule..."
    cd capsule/code
    chmod +x run
    ./run ${spikesorting_args}

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
    val spikesorting_args

    output:
    tuple val('sc2'), path('capsule/results')

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

    echo "[${task.tag}] cloning git repo..."
    git clone "https://github.com/AllenNeuralDynamics/aind-ephys-spikesort-spykingcircus2.git" capsule-repo
    git -C capsule-repo -c core.fileMode=false checkout ${params.versions['SPIKESORT_SC2']} --quiet
    mv capsule-repo/code capsule/code
    rm -rf capsule-repo

    echo "[${task.tag}] running capsule..."
    cd capsule/code
    chmod +x run
    ./run ${spikesorting_args}

    echo "[${task.tag}] completed!"
    """
}


// Subworkflow for preprocess + Kilosort2.5
workflow spike_sorting_kilosort25 {
    take:
        max_duration_minutes // Max duration for the recordings
        ecephys_input_ch     // Channel: ecephys session input
        hybrid_recordings_ch
        preprocessing_args
        spikesorting_args

    main:
        preprocess_ch = preprocessing(
            max_duration_minutes,
            ecephys_input_ch.collect(),  
            hybrid_recordings_ch.flatten(),
            preprocessing_args
        )
        // Pass versions to process if it's scoped locally, or ensure it's global
        spikesort_kilosort25_ch = spikesort_kilosort25(
            max_duration_minutes,
            preprocessing_out.results,
            spikesorting_args
        )

    emit:
        kilosort25_results = spikesort_kilosort25_ch
}

// Subworkflow for preprocess + Kilosort4
workflow spike_sorting_kilosort4 {
    take:
        max_duration_minutes // Max duration for the recordings
        ecephys_input_ch     
        hybrid_recordings_ch 
        preprocessing_args
        spikesorting_args

    main:
        preprocess_ch = preprocessing(
            max_duration_minutes,
            ecephys_input_ch.collect(),
            hybrid_recordings_ch.flatten(),
            preprocessing_args
        )
        spikesort_kilosort4_ch = spikesort_kilosort4(
            max_duration_minutes, 
            preprocess_ch.results,
            spikesorting_args
        )

    emit:
        kilosort4_results = spikesort_kilosort4_ch
}

// Subworkflow for preprocess + SpykingCircus2
workflow spike_sorting_spykingcircus2 {
    take:
        max_duration_minutes // Max duration for the recordings
        ecephys_input_ch
        hybrid_recordings_ch 
        preprocessing_args
        spikesorting_args

    main:
        preprocess_ch = preprocessing(
            max_duration_minutes,
            ecephys_input_ch.collect(),
            hybrid_recordings_ch.flatten(),
            preprocessing_args
        )
        spikesort_spykingcircus2_ch = spikesort_spykingcircus2(
            max_duration_minutes,
            preprocess_ch.results,
            spikesorting_args    
        )

    emit:
        spykingcircus2_results = spikesort_spykingcircus2_ch
}

workflow lossless {
    take:
        max_duration_minutes // Max duration for the recordings
        ecephys_input_ch     
        hybrid_recordings_ch
        sorter
        preprocessing_args
        spikesorting_args

    main:
        println "Running lossless workflow with sorter: ${sorter}"
        println "Preprocessing arguments: ${preprocessing_args}"
        println "Spikesorting arguments: ${spikesorting_args}"

        preprocess_ch = preprocessing(
            max_duration_minutes,
            ecephys_input_ch.collect(),
            hybrid_recordings_ch.flatten(),
            preprocessing_args
        )
        if (sorter == 'kilosort25' || sorter == 'ks25') {
            sorter_results_ch = spikesort_kilosort25(
                max_duration_minutes,
                preprocess_ch.results,
                spikesorting_args
            )
        } else if (sorter == 'kilosort4'  || sorter == 'ks4') {
            sorter_results_ch = spikesort_kilosort4(
                max_duration_minutes,
                preprocess_ch.results,
                spikesorting_args
            )
        } else if (sorter == 'spykingcircus2' || sorter == 'sc2') {
            sorter_results_ch = spikesort_spykingcircus2(
                max_duration_minutes,
                preprocess_ch.results,
                spikesorting_args
            )
        }

    emit:
        lossless_results = sorter_results_ch.map { it -> tuple('lossless', it[1]) }
}

workflow wavpack_3 {
    take:
        max_duration_minutes // Max duration for the recordings
        ecephys_input_ch     
        hybrid_recordings_ch
        sorter
        preprocessing_args
        spikesorting_args

    main:
        wavpack_ch = compress_wavpack(
            max_duration_minutes,
            ecephys_input_ch.collect(),
            hybrid_recordings_ch.flatten(),
            3
        )
        preprocess_ch = preprocessing(
            max_duration_minutes,
            ecephys_input_ch.collect(),
            wavpack_ch.results,
            preprocessing_args
        )
        if (sorter == 'kilosort25' || sorter == 'ks25') {
            sorter_results_ch = spikesort_kilosort25(
                max_duration_minutes,
                preprocess_ch.results,
                spikesorting_args
            )
        } else if (sorter == 'kilosort4' || sorter == 'ks4') {
            sorter_results_ch = spikesort_kilosort4(
                max_duration_minutes,
                preprocess_ch.results,
                spikesorting_args
            )
        } else if (sorter == 'spykingcircus2' || sorter == 'sc2') {
            sorter_results_ch = spikesort_spykingcircus2(
                max_duration_minutes,
                preprocess_ch.results,
                spikesorting_args
            )
        }

    emit:
        wv3_results = sorter_results_ch.map { it -> tuple('wv-3', it[1]) }
}

workflow wavpack_2_5 {
    take:
        max_duration_minutes // Max duration for the recordings
        ecephys_input_ch     
        hybrid_recordings_ch
        sorter
        preprocessing_args
        spikesorting_args

    main:
        wavpack_ch = compress_wavpack(
            max_duration_minutes,
            ecephys_input_ch.collect(),
            hybrid_recordings_ch.flatten(),
            2.5
        )
        preprocess_ch = preprocessing(
            max_duration_minutes,
            ecephys_input_ch.collect(),
            wavpack_ch.results,
            preprocessing_args
        )
        if (sorter == 'kilosort25' || sorter == 'ks25') {
            sorter_results_ch = spikesort_kilosort25(
                max_duration_minutes,
                preprocess_ch.results,
                spikesorting_args
            )
        } else if (sorter == 'kilosort4' || sorter == 'ks4') {
            sorter_results_ch = spikesort_kilosort4(
                max_duration_minutes,
                preprocess_ch.results,
                spikesorting_args
            )
        } else if (sorter == 'spykingcircus2' || sorter == 'sc2') {
            sorter_results_ch = spikesort_spykingcircus2(
                max_duration_minutes,
                preprocess_ch.results,
                spikesorting_args
            )
        }

    emit:
        wv25_results = sorter_results_ch.map { it -> tuple('wv-2.5', it[1]) }

}

workflow wavpack_2_25 {
    take:
        max_duration_minutes // Max duration for the recordings
        ecephys_input_ch     
        hybrid_recordings_ch
        sorter
        preprocessing_args
        spikesorting_args

    main:
        wavpack_ch = compress_wavpack(
            max_duration_minutes,
            ecephys_input_ch.collect(),
            hybrid_recordings_ch.flatten(),
            2.25
        )
        preprocess_ch = preprocessing(
            max_duration_minutes,
            ecephys_input_ch.collect(),
            wavpack_ch.results,
            preprocessing_args
        )
        if (sorter == 'kilosort25' || sorter == 'ks25') {
            sorter_results_ch = spikesort_kilosort25(
                max_duration_minutes,
                preprocess_ch.results,
                spikesorting_args
            )
        } else if (sorter == 'kilosort4' || sorter == 'ks4') {
            sorter_results_ch = spikesort_kilosort4(
                max_duration_minutes,
                preprocess_ch.results,
                spikesorting_args
            )
        } else if (sorter == 'spykingcircus2' || sorter == 'sc2') {
            sorter_results_ch = spikesort_spykingcircus2(
                max_duration_minutes,
                preprocess_ch.results,
                spikesorting_args
            )
        }

    emit:
        wv225_results = sorter_results_ch.map { it -> tuple('wv-2.25', it[1]) }
}
