#!/usr/bin/env nextflow
nextflow.enable.dsl = 1

params.ecephys_path = DATA_PATH

println "DATA_PATH: ${DATA_PATH}"
println "RESULTS_PATH: ${RESULTS_PATH}"
println "PARAMS: ${params}"

// get commit hashes for capsules
params.capsule_versions = "${baseDir}/capsule_versions.env"
def versions = [:]
file(params.capsule_versions).eachLine { line ->
    def (key, value) = line.tokenize('=')
    versions[key] = value
}

params_keys = params.keySet()
// set global n_jobs
if ("n_jobs" in params_keys) {
	n_jobs = params.n_jobs
}
else
{
	n_jobs = -1
}
println "N JOBS: ${n_jobs}"

// container tag
params.container_tag = "si-${versions['SPIKEINTERFACE_VERSION']}"
println "CONTAINER TAG: ${params.container_tag}"

ecephys_to_job_dispatch = channel.fromPath(params.ecephys_path + "/", type: 'any')
job_dispatch_to_hybrid_generation = channel.create()
ecephys_to_hybrid_generation = channel.fromPath(params.ecephys_path + "/", type: 'any')
hybrid_generation_to_preprocessing = channel.create()
ecephys_to_preprocessing = channel.fromPath(params.ecephys_path + "/", type: 'any')
preprocessing_to_spikesort_kilosort25 = channel.create()
preprocessing_to_spikesort_kilosort4 = channel.create()
preprocessing_to_spikesort_spykingcircus2 = channel.create()
preprocessing_to_spikesort = channel.create()
ecephys_to_hybrid_evaluation = channel.fromPath(params.ecephys_path + "/", type: 'any')
hybrid_generation_to_hybrid_evaluation = channel.create()
spikesort_kilosort4_to_hybrid_evaluation = channel.create()
spikesort_kilosort25_to_hybrid_evaluation = channel.create()
spikesort_spykingcircus2_to_hybrid_evaluation = channel.create()

if (!params_keys.contains('job_dispatch_args')) {
	params.job_dispatch_args = ""
}
if (!params_keys.contains('preprocessing_args')) {
	params.preprocessing_args = ""
}
if (!params_keys.contains('spikesorting_args')) {
	params.spikesorting_args = ""
}
if (!params_keys.contains('hybrid_generation_args')) {
	params.hybrid_generation_args = ""
}

// if (!params_keys.contains('sorters')) {
// 	params.sorters = "kilosort4+spykingcircus2"
// }

// // User-specified sorters
// def sorters = params.sorters.split('\\+')
// println "SORTERS: ${sorters}"

// // Dynamically split the channel for each sorter
// sorters.each { sorter ->
//     preprocessing_to_spikesort.into("preprocessing_to_spikesort_${sorter}")
// }


process job_dispatch {
	tag 'job_dispatch'
	def container_name = "ghcr.io/allenneuraldynamics/aind-ephys-pipeline-base:${params.container_tag}"
    container container_name

	input:
	path 'capsule/data/ecephys_session' from ecephys_to_job_dispatch.collect()

	output:
	path 'capsule/results/*' into job_dispatch_to_hybrid_generation

	script:
	"""
	#!/usr/bin/env bash
	set -e

	mkdir -p capsule
	mkdir -p capsule/data && ln -s \$PWD/capsule/data /data
	mkdir -p capsule/results && ln -s \$PWD/capsule/results /results
	mkdir -p capsule/scratch && ln -s \$PWD/capsule/scratch /scratch

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
	tag 'hybrid_generation'
	def container_name = "ghcr.io/allenneuraldynamics/aind-ephys-pipeline-base:${params.container_tag}"
    container container_name

	input:
	path 'capsule/data/' from job_dispatch_to_hybrid_generation.flatten()
	path 'capsule/data/ecephys_session' from ecephys_to_hybrid_generation.collect()

	output:
	path 'capsule/results/recordings/*' into hybrid_generation_to_preprocessing
	path 'capsule/results/flattened/*' into hybrid_generation_to_hybrid_evaluation

	script:
	"""
	#!/usr/bin/env bash
	set -e

	mkdir -p capsule
	mkdir -p capsule/data && ln -s \$PWD/capsule/data /data
	mkdir -p capsule/results && ln -s \$PWD/capsule/results /results
	mkdir -p capsule/scratch && ln -s \$PWD/capsule/scratch /scratch

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
	path 'capsule/data/' from hybrid_generation_to_preprocessing.flatten()
	path 'capsule/data/ecephys_session' from ecephys_to_preprocessing.collect()

	output:
	path 'capsule/results/*' into preprocessing_to_spikesort_kilosort25
	path 'capsule/results/*' into preprocessing_to_spikesort_kilosort4
	path 'capsule/results/*' into preprocessing_to_spikesort_spykingcircus2

	script:
	"""
	#!/usr/bin/env bash
	set -e

	mkdir -p capsule
	mkdir -p capsule/data && ln -s \$PWD/capsule/data /data
	mkdir -p capsule/results && ln -s \$PWD/capsule/results /results
	mkdir -p capsule/scratch && ln -s \$PWD/capsule/scratch /scratch

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

	accelerator 1
	label 'gpu'

	input:
	path 'capsule/data/' from preprocessing_to_spikesort_kilosort25

	output:
	path 'capsule/results/*' into spikesort_kilosort25_to_hybrid_evaluation

	script:
	"""
	#!/usr/bin/env bash
	set -e

	mkdir -p capsule
	mkdir -p capsule/data && ln -s \$PWD/capsule/data /data
	mkdir -p capsule/results && ln -s \$PWD/capsule/results /results
	mkdir -p capsule/scratch && ln -s \$PWD/capsule/scratch /scratch

	echo "[${task.tag}] cloning git repo..."
	git clone "https://github.com/AllenNeuralDynamics/aind-ephys-spikesort-kilosort25.git" capsule-repo
	git -C capsule-repo -c core.fileMode=false checkout ${versions['SPIKESORT_KS25']} --quiet
	mv capsule-repo/code capsule/code
	rm -rf capsule-repo

	echo "[${task.tag}] running capsule..."
	cd capsule/code
	chmod +x run
	./run ${params.spikesort_kilosort25_args}

	echo "[${task.tag}] completed!"
	"""
}

process spikesort_kilosort4 {
	tag 'spikesort_kilosort4'
	def container_name = "ghcr.io/allenneuraldynamics/aind-ephys-spikesort-kilosort4:${params.container_tag}"
    container container_name

	accelerator 1
	label 'gpu'

	input:
	path 'capsule/data/' from preprocessing_to_spikesort_kilosort4

	output:
	path 'capsule/results/*' into spikesort_kilosort4_to_hybrid_evaluation

	script:
	"""
	#!/usr/bin/env bash
	set -e

	mkdir -p capsule
	mkdir -p capsule/data && ln -s \$PWD/capsule/data /data
	mkdir -p capsule/results && ln -s \$PWD/capsule/results /results
	mkdir -p capsule/scratch && ln -s \$PWD/capsule/scratch /scratch

	echo "[${task.tag}] cloning git repo..."
	git clone "https://github.com/AllenNeuralDynamics/aind-ephys-spikesort-kilosort4.git" capsule-repo
	git -C capsule-repo -c core.fileMode=false checkout ${versions['SPIKESORT_KS4']} --quiet
	mv capsule-repo/code capsule/code
	rm -rf capsule-repo

	echo "[${task.tag}] running capsule..."
	cd capsule/code
	chmod +x run
	./run ${params.spikesort_kilosort4_args}

	echo "[${task.tag}] completed!"
	"""
}

process spikesort_spykingcircus2 {
	tag 'spikesort_spykingcircus2'
	def container_name = "ghcr.io/allenneuraldynamics/aind-ephys-pipeline-base:${params.container_tag}"
    container container_name

	input:
	path 'capsule/data/' from preprocessing_to_spikesort_spykingcircus2

	output:
	path 'capsule/results/*' into spikesort_spykingcircus2_to_hybrid_evaluation

	script:
	"""
	#!/usr/bin/env bash
	set -e

	mkdir -p capsule
	mkdir -p capsule/data && ln -s \$PWD/capsule/data /data
	mkdir -p capsule/results && ln -s \$PWD/capsule/results /results
	mkdir -p capsule/scratch && ln -s \$PWD/capsule/scratch /scratch

	echo "[${task.tag}] cloning git repo..."
	git clone "https://github.com/AllenNeuralDynamics/aind-ephys-spikesort-spykingcircus2.git" capsule-repo
	git -C capsule-repo -c core.fileMode=false checkout ${versions['SPIKESORT_SC2']} --quiet
	mv capsule-repo/code capsule/code
	rm -rf capsule-repo

	echo "[${task.tag}] running capsule..."
	cd capsule/code
	chmod +x run
	./run ${params.spikesort_spykingcircus2_args}

	echo "[${task.tag}] completed!"
	"""
}

process hybrid_evaluation {
	tag 'hybrid_evaluation'
	def container_name = "ghcr.io/allenneuraldynamics/aind-ephys-pipeline-base:${params.container_tag}"
    container container_name

	publishDir "$RESULTS_PATH", saveAs: { filename -> new File(filename).getName() }

	input:
	path 'capsule/data/ecephys_session' from ecephys_to_hybrid_evaluation.collect()
	path 'capsule/data/' from hybrid_generation_to_hybrid_evaluation.collect()
	path 'capsule/data/ks4/' from spikesort_kilosort4_to_hybrid_evaluation.collect()
	path 'capsule/data/ks25/' from spikesort_kilosort25_to_hybrid_evaluation.collect()
	path 'capsule/data/sc2/' from spikesort_spykingcircus2_to_hybrid_evaluation.collect()

	output:
	path 'capsule/results/*'

	script:
	"""
	#!/usr/bin/env bash
	set -e

	mkdir -p capsule
	mkdir -p capsule/data && ln -s \$PWD/capsule/data /data
	mkdir -p capsule/results && ln -s \$PWD/capsule/results /results
	mkdir -p capsule/scratch && ln -s \$PWD/capsule/scratch /scratch

	echo "[${task.tag}] cloning git repo..."
	git clone "https://github.com/AllenNeuralDynamics/aind-ephys-hybrid-evaluation.git" capsule-repo
	git -C capsule-repo -c core.fileMode=false checkout ${versions['HYBRID_EVALUATION']} --quiet
	mv capsule-repo/code capsule/code
	rm -rf capsule-repo

	echo "[${task.tag}] running capsule..."
	cd capsule/code
	chmod +x run
	./run

	echo "[${task.tag}] completed!"
	"""
}
