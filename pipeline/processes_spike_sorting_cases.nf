#!/usr/bin/env nextflow

nextflow.enable.dsl = 2 // Assuming DSL2 is still desired for this file

include { parse_capsule_versions } from './processes_common.nf'
include { gitCloneFunction } from './processes_common.nf'

params.versions = parse_capsule_versions()

params.container_tag = "si-${params.versions['SPIKEINTERFACE_VERSION']}"

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
    ${gitCloneFunction()}
    clone_repo "https://github.com/AllenNeuralDynamics/aind-ephys-preprocessing.git" "${params.versions['PREPROCESSING']}"

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
    ${gitCloneFunction()}
    clone_repo "https://github.com/AllenNeuralDynamics/aind-ephys-compress.git" "${params.versions['COMPRESSION']}"

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
    ${gitCloneFunction()}
    clone_repo "https://github.com/AllenNeuralDynamics/aind-ephys-spikesort-kilosort25.git" "${params.versions['SPIKESORT_KS25']}"

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
    ${gitCloneFunction()}
    clone_repo "https://github.com/AllenNeuralDynamics/aind-ephys-spikesort-kilosort4.git" "${params.versions['SPIKESORT_KS4']}"

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
    ${gitCloneFunction()}
    clone_repo "https://github.com/AllenNeuralDynamics/aind-ephys-spikesort-spykingcircus2.git" "${params.versions['SPIKESORT_SC2']}"

    echo "[${task.tag}] running capsule..."
    cd capsule/code
    chmod +x run
    ./run ${spikesorting_args}

    echo "[${task.tag}] completed!"
    """
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
