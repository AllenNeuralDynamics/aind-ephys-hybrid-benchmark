#!/usr/bin/env nextflow

nextflow.enable.dsl = 2 // Retaining DSL2 for this file


// Include common processes
include { job_dispatch } from './processes_common.nf'
include { job_dispatch_hybrid } from './processes_common.nf'
include { hybrid_generation } from './processes_common.nf'
include { hybrid_evaluation } from './processes_common.nf'

// Include subworkflows from the updated sorters_workflows.nf
include { lossless } from './processes_spike_sorting_cases.nf'
include { wavpack_3 } from './processes_spike_sorting_cases.nf'
include { wavpack_2_5 } from './processes_spike_sorting_cases.nf'
include { wavpack_2_25 } from './processes_spike_sorting_cases.nf'


// Params from main_sorters_slurm.nf
params.ecephys_path = DATA_PATH

println "DATA_PATH: ${DATA_PATH}"
println "RESULTS_PATH: ${RESULTS_PATH}"
println "PARAMS: ${params}"

include { parse_capsule_versions } from './processes_common.nf'

params.versions = parse_capsule_versions()

params.container_tag = "si-${params.versions['SPIKEINTERFACE_VERSION']}"
println "CONTAINER TAG: ${params.container_tag}"

params_keys = params.keySet()
println "PARAMS KEYS: ${params_keys}"

// if not specified, assume local executor
if (!params_keys.contains('executor')) {
    params.executor = "local"
}
// set global n_jobs for local executor
if (params.executor == "local")
{
    if ("n_jobs" in params_keys) {
        n_jobs = params.n_jobs
    }
    else {
        n_jobs = -1
    }
    println "N JOBS: ${n_jobs}"
    job_args=" --n-jobs ${n_jobs}"
}
else {
    job_args=""
}

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


// Params defaults
params.job_dispatch_args = null
params.existing = false

// Normalize inputs
def existing = params.existing.toString().toBoolean()
def job_dispatch_args = params.job_dispatch_args?.toString() ?: ""

// Ensure multi-session unless overridden
if (!job_dispatch_args.contains("--multi-session") && !existing) {
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

if (!params.containsKey("sorter")) {
    params.sorter = "kilosort4"
    println "No sorter specified, defaulting to kilosort4"
}
else {
    println "Using sorter from params"
}

println "Sorter to run: ${params.sorter}"
def sorting_cases_list = params.sorting_cases.split('\\+')
println "Spike sorting cases to run: ${sorting_cases_list}"


workflow {
    ecephys_ch = Channel.fromPath(params.ecephys_path + "/", type: 'any')

    if (existing) {
        hybrid_generation_out = job_dispatch_hybrid(
            ecephys_ch.collect(),
            job_dispatch_args
        )

        max_duration_file = hybrid_generation_out.max_duration_file
        max_duration_minutes = max_duration_file.map { it.text.trim() }
        max_duration_minutes.view { "Max recording duration: ${it}min" }
    }
    else {
        job_dispatch_out = job_dispatch(
            ecephys_ch.collect(),
            job_dispatch_args
        )

        max_duration_file = job_dispatch_out.max_duration_file
        max_duration_minutes = max_duration_file.map { it.text.trim() }
        max_duration_minutes.view { "Max recording duration: ${it}min" }
        
        hybrid_generation_out = hybrid_generation(
            max_duration_minutes,
            ecephys_ch.collect(),
            job_dispatch_out.results.flatten(),
            hybrid_generation_args
        )
    }

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
        all_sorter_results,
        hybrid_evaluation_args
    )
}
