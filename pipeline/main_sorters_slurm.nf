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

// container tag
params.container_tag = "si-${versions['SPIKEINTERFACE_VERSION']}"
println "CONTAINER TAG: ${params.container_tag}"

ecephys_to_job_dispatch = channel.fromPath(params.ecephys_url + "/", type: 'any')
job_dispatch_to_hybrid_generation = channel.create()
ecephys_to_hybrid_generation = channel.fromPath(params.ecephys_url + "/", type: 'any')
hybrid_generation_to_preprocess = channel.create()
ecephys_to_preprocess = channel.fromPath(params.ecephys_url + "/", type: 'any')
preprocess_to_spikesort_kilosort25 = channel.create()
preprocess_to_spikesort_kilosort4 = channel.create()
preprocess_to_spikesort_spykingcircus2 = channel.create()
ecephys_to_hybrid_evaluation = channel.fromPath(params.ecephys_url + "/", type: 'any')
hybrid_generation_to_hybrid_evaluation = channel.create()
spikesort_kilosort4_to_hybrid_evaluation = channel.create()
spikesort_kilosort25_to_hybrid_evaluation = channel.create()
spikesort_spykingcircus2_to_hybrid_evaluation = channel.create()


process job_dispatch {
	tag 'job_dispatch'
	def container_name = "ghcr.io/allenneuraldynamics/aind-ephys-pipeline-base:${params.container_tag}"
    container container_name

	cpus 4
	memory '32 GB'

	input:
	path 'capsule/data/ecephys_session' from ecephys_to_job_dispatch.collect()

	output:
	path 'capsule/results/*' into job_dispatch_to_hybrid_generation

	script:
	"""
	#!/usr/bin/env bash
	set -e

	export CO_CAPSULE_ID=44358dbf-921b-42d7-897d-9725eebd5ed8
	export CO_CPUS=4
	export CO_MEMORY=34359738368

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
	def container_name = "ghcr.io/allenneuraldynamics/aind-ephys-hybrid-generation-dev:${params.container_tag}"
    container container_name

	cpus 16
	memory '64 GB'

	input:
	path 'capsule/data/' from job_dispatch_to_hybrid_generation.flatten()
	path 'capsule/data/ecephys_session' from ecephys_to_hybrid_generation.collect()

	output:
	path 'capsule/results/recordings/*' into hybrid_generation_to_preprocess
	path 'capsule/results/flattened/*' into hybrid_generation_to_hybrid_evaluation

	script:
	"""
	#!/usr/bin/env bash
	set -e

	export CO_CAPSULE_ID=bc02ffcd-a183-4ac4-8bda-021dc1cf01cb
	export CO_CPUS=16
	export CO_MEMORY=68719476736

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

process preprocess {
	tag 'preprocess'
	def container_name = "ghcr.io/allenneuraldynamics/aind-ephys-pipeline-base:${params.container_tag}"
    container container_name

	cpus 32
	memory '128 GB'

	input:
	path 'capsule/data/' from hybrid_generation_to_preprocess.flatten()
	path 'capsule/data/ecephys_session' from ecephys_to_preprocess.collect()

	output:
	path 'capsule/results/*' into preprocess_to_spikesort_kilosort25
	path 'capsule/results/*' into preprocess_to_spikesort_kilosort4
	path 'capsule/results/*' into preprocess_to_spikesort_spykingcircus2

	script:
	"""
	#!/usr/bin/env bash
	set -e

	export CO_CAPSULE_ID=05eaf483-9ca3-4a9e-8da8-7d23717f6faf
	export CO_CPUS=32
	export CO_MEMORY=137438953472

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
	./run ${params.preprocess_args}

	echo "[${task.tag}] completed!"
	"""
}

process spikesort_kilosort25 {
	tag 'spikesort_kilosort25'
	def container_name = "ghcr.io/allenneuraldynamics/aind-ephys-spikesort-kilosort25:${params.container_tag}"
    container container_name
	containerOptions '--nv'
	clusterOptions '--gres=gpu:1'
	module 'cuda'
	queue params.gpu_queue ?: params.default_queue

	cpus 16
	memory '64 GB'

	input:
	path 'capsule/data/' from preprocess_to_spikesort_kilosort25

	output:
	path 'capsule/results/*' into spikesort_kilosort25_to_hybrid_evaluation

	script:
	"""
	#!/usr/bin/env bash
	set -e

	export CO_CAPSULE_ID=9c169ec3-5933-4b10-808b-6fa4620e37b7
	export CO_CPUS=16
	export CO_MEMORY=68719476736

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
	containerOptions '--nv'
	clusterOptions '--gres=gpu:1'
	module 'cuda'
	queue params.gpu_queue ?: params.default_queue

	cpus 16
	memory '64 GB'

	input:
	path 'capsule/data/' from preprocess_to_spikesort_kilosort4

	output:
	path 'capsule/results/*' into spikesort_kilosort4_to_hybrid_evaluation

	script:
	"""
	#!/usr/bin/env bash
	set -e

	export CO_CAPSULE_ID=e41ff24a-791c-4a11-a810-0106707d3617
	export CO_CPUS=16
	export CO_MEMORY=68719476736

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
	def container_name = "ghcr.io/allenneuraldynamics/aind-ephys-spikesort-spykingcircus2-dev:${params.container_tag}"
    container container_name

	cpus 32
	memory '128 GB'

	input:
	path 'capsule/data/' from preprocess_to_spikesort_spykingcircus2

	output:
	path 'capsule/results/*' into spikesort_spykingcircus2_to_hybrid_evaluation

	script:
	"""
	#!/usr/bin/env bash
	set -e

	export CO_CAPSULE_ID=b68f9aec-7e8d-4862-865a-38081f5a6aeb
	export CO_CPUS=32
	export CO_MEMORY=137438953472

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
	def container_name = "ghcr.io/allenneuraldynamics/aind-ephys-hybrid-evaluation-dev:${params.container_tag}"
    container container_name

	cpus 16
	memory '64 GB'

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

	export CO_CAPSULE_ID=e8752278-0e96-4e74-a179-2c838bc0c186
	export CO_CPUS=16
	export CO_MEMORY=137438953472

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
