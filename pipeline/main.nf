#!/usr/bin/env nextflow
// hash:sha256:c2f945eec324d57a4353fffa4bc9c346056b725d3d1626650aebd5928ec0aff7

nextflow.enable.dsl = 1

params.ecephys_url = 's3://aind-private-data-prod-o5171v/ecephys_715710_2024-07-16_12-58-34'

ecephys_to_job_dispatch_ecephys_1 = channel.fromPath(params.ecephys_url + "/", type: 'any')
capsule_job_dispatch_ecephys_1_to_capsule_hybrid_generation_ecephys_2_2 = channel.create()
ecephys_to_hybrid_generation_ecephys_3 = channel.fromPath(params.ecephys_url + "/", type: 'any')
capsule_hybrid_generation_ecephys_2_to_capsule_preprocess_ecephys_3_4 = channel.create()
ecephys_to_preprocess_ecephys_5 = channel.fromPath(params.ecephys_url + "/", type: 'any')
capsule_preprocess_ecephys_3_to_capsule_spikesort_kilosort_25_ecephys_4_6 = channel.create()
capsule_preprocess_ecephys_3_to_capsule_spikesort_kilosort_4_ecephys_5_7 = channel.create()
ecephys_to_hybrid_evaluation_ecephys_8 = channel.fromPath(params.ecephys_url + "/", type: 'any')
capsule_hybrid_generation_ecephys_2_to_capsule_hybrid_evaluation_ecephys_6_9 = channel.create()
capsule_spikesort_kilosort_4_ecephys_5_to_capsule_hybrid_evaluation_ecephys_6_10 = channel.create()
capsule_spikesort_kilosort_25_ecephys_4_to_capsule_hybrid_evaluation_ecephys_6_11 = channel.create()

// capsule - Job Dispatch Ecephys
process capsule_job_dispatch_ecephys_1 {
	tag 'capsule-5832718'
	container "$REGISTRY_HOST/capsule/cb734cf3-2f88-4b69-bf0a-d5869e6706e3:c2d5f2258861d572982b6bfb56ef7d5f"

	cpus 4
	memory '32 GB'

	input:
	path 'capsule/data/ecephys_session' from ecephys_to_job_dispatch_ecephys_1.collect()

	output:
	path 'capsule/results/*' into capsule_job_dispatch_ecephys_1_to_capsule_hybrid_generation_ecephys_2_2

	script:
	"""
	#!/usr/bin/env bash
	set -e

	export CO_CAPSULE_ID=cb734cf3-2f88-4b69-bf0a-d5869e6706e3
	export CO_CPUS=4
	export CO_MEMORY=34359738368

	mkdir -p capsule
	mkdir -p capsule/data && ln -s \$PWD/capsule/data /data
	mkdir -p capsule/results && ln -s \$PWD/capsule/results /results
	mkdir -p capsule/scratch && ln -s \$PWD/capsule/scratch /scratch

	echo "[${task.tag}] cloning git repo..."
	git clone "https://\$GIT_ACCESS_TOKEN@\$GIT_HOST/capsule-5832718.git" capsule-repo
	git -C capsule-repo checkout 628f38566b5545ba5dba8b8382cab2d18ccff743 --quiet
	mv capsule-repo/code capsule/code
	rm -rf capsule-repo

	echo "[${task.tag}] running capsule..."
	cd capsule/code
	chmod +x run
	./run ${params.capsule_job_dispatch_ecephys_1_args}

	echo "[${task.tag}] completed!"
	"""
}

// capsule - Hybrid Generation Ecephys
process capsule_hybrid_generation_ecephys_2 {
	tag 'capsule-9051504'
	container "$REGISTRY_HOST/capsule/bc02ffcd-a183-4ac4-8bda-021dc1cf01cb:9b4e84fa1d3953043046d2fefef5684d"

	cpus 16
	memory '64 GB'

	input:
	path 'capsule/data/' from capsule_job_dispatch_ecephys_1_to_capsule_hybrid_generation_ecephys_2_2.flatten()
	path 'capsule/data/ecephys_session' from ecephys_to_hybrid_generation_ecephys_3.collect()

	output:
	path 'capsule/results/recordings/*' into capsule_hybrid_generation_ecephys_2_to_capsule_preprocess_ecephys_3_4
	path 'capsule/results/flattened/*' into capsule_hybrid_generation_ecephys_2_to_capsule_hybrid_evaluation_ecephys_6_9

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
	git clone "https://\$GIT_ACCESS_TOKEN@\$GIT_HOST/capsule-9051504.git" capsule-repo
	git -C capsule-repo checkout f4876ef80ed4d2538bde75708c333e2106bc9865 --quiet
	mv capsule-repo/code capsule/code
	rm -rf capsule-repo

	echo "[${task.tag}] running capsule..."
	cd capsule/code
	chmod +x run
	./run ${params.capsule_hybrid_generation_ecephys_2_args}

	echo "[${task.tag}] completed!"
	"""
}

// capsule - Preprocess Ecephys
process capsule_preprocess_ecephys_3 {
	tag 'capsule-0874799'
	container "$REGISTRY_HOST/capsule/05eaf483-9ca3-4a9e-8da8-7d23717f6faf:43b4cc30d75eb70967377f805f93e930"

	cpus 16
	memory '64 GB'

	input:
	path 'capsule/data/' from capsule_hybrid_generation_ecephys_2_to_capsule_preprocess_ecephys_3_4.flatten()
	path 'capsule/data/ecephys_session' from ecephys_to_preprocess_ecephys_5.collect()

	output:
	path 'capsule/results/*' into capsule_preprocess_ecephys_3_to_capsule_spikesort_kilosort_25_ecephys_4_6
	path 'capsule/results/*' into capsule_preprocess_ecephys_3_to_capsule_spikesort_kilosort_4_ecephys_5_7

	script:
	"""
	#!/usr/bin/env bash
	set -e

	export CO_CAPSULE_ID=05eaf483-9ca3-4a9e-8da8-7d23717f6faf
	export CO_CPUS=16
	export CO_MEMORY=68719476736

	mkdir -p capsule
	mkdir -p capsule/data && ln -s \$PWD/capsule/data /data
	mkdir -p capsule/results && ln -s \$PWD/capsule/results /results
	mkdir -p capsule/scratch && ln -s \$PWD/capsule/scratch /scratch

	echo "[${task.tag}] cloning git repo..."
	git clone "https://\$GIT_ACCESS_TOKEN@\$GIT_HOST/capsule-0874799.git" capsule-repo
	git -C capsule-repo checkout 86e1945980fd49fcfc26b42c5c803b51ea655984 --quiet
	mv capsule-repo/code capsule/code
	rm -rf capsule-repo

	echo "[${task.tag}] running capsule..."
	cd capsule/code
	chmod +x run
	./run ${params.capsule_preprocess_ecephys_3_args}

	echo "[${task.tag}] completed!"
	"""
}

// capsule - Spikesort Kilosort2.5 Ecephys
process capsule_spikesort_kilosort_25_ecephys_4 {
	tag 'capsule-2633671'
	container "$REGISTRY_HOST/capsule/9c169ec3-5933-4b10-808b-6fa4620e37b7:bc0ece20064b559e6c11214c397a950d"

	cpus 16
	memory '61 GB'
	accelerator 1
	label 'gpu'

	input:
	path 'capsule/data/' from capsule_preprocess_ecephys_3_to_capsule_spikesort_kilosort_25_ecephys_4_6

	output:
	path 'capsule/results/*' into capsule_spikesort_kilosort_25_ecephys_4_to_capsule_hybrid_evaluation_ecephys_6_11

	script:
	"""
	#!/usr/bin/env bash
	set -e

	export CO_CAPSULE_ID=9c169ec3-5933-4b10-808b-6fa4620e37b7
	export CO_CPUS=16
	export CO_MEMORY=65498251264

	mkdir -p capsule
	mkdir -p capsule/data && ln -s \$PWD/capsule/data /data
	mkdir -p capsule/results && ln -s \$PWD/capsule/results /results
	mkdir -p capsule/scratch && ln -s \$PWD/capsule/scratch /scratch

	echo "[${task.tag}] cloning git repo..."
	git clone "https://\$GIT_ACCESS_TOKEN@\$GIT_HOST/capsule-2633671.git" capsule-repo
	git -C capsule-repo checkout ce5bd8c3e61f07701ade1b7234b6f74678714dcb --quiet
	mv capsule-repo/code capsule/code
	rm -rf capsule-repo

	echo "[${task.tag}] running capsule..."
	cd capsule/code
	chmod +x run
	./run ${params.capsule_spikesort_kilosort_25_ecephys_4_args}

	echo "[${task.tag}] completed!"
	"""
}

// capsule - Spikesort Kilosort4 Ecephys
process capsule_spikesort_kilosort_4_ecephys_5 {
	tag 'capsule-2928576'
	container "$REGISTRY_HOST/capsule/e41ff24a-791c-4a11-a810-0106707d3617:2b5f3d5a8f884c6776734d7468e6600a"

	cpus 16
	memory '64 GB'
	accelerator 1
	label 'gpu'

	input:
	path 'capsule/data/' from capsule_preprocess_ecephys_3_to_capsule_spikesort_kilosort_4_ecephys_5_7

	output:
	path 'capsule/results/*' into capsule_spikesort_kilosort_4_ecephys_5_to_capsule_hybrid_evaluation_ecephys_6_10

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
	git clone "https://\$GIT_ACCESS_TOKEN@\$GIT_HOST/capsule-2928576.git" capsule-repo
	git -C capsule-repo checkout fe0588b7cd15a85817422be8255a0ae72af13acf --quiet
	mv capsule-repo/code capsule/code
	rm -rf capsule-repo

	echo "[${task.tag}] running capsule..."
	cd capsule/code
	chmod +x run
	./run ${params.capsule_spikesort_kilosort_4_ecephys_5_args}

	echo "[${task.tag}] completed!"
	"""
}

// capsule - Hybrid Evaluation Ecephys
process capsule_hybrid_evaluation_ecephys_6 {
	tag 'capsule-5273805'
	container "$REGISTRY_HOST/capsule/e8752278-0e96-4e74-a179-2c838bc0c186:b61a0430df8865d257ccc9fec7aa5128"

	cpus 16
	memory '128 GB'

	publishDir "$RESULTS_PATH", saveAs: { filename -> new File(filename).getName() }

	input:
	path 'capsule/data/ecephys_session' from ecephys_to_hybrid_evaluation_ecephys_8.collect()
	path 'capsule/data/' from capsule_hybrid_generation_ecephys_2_to_capsule_hybrid_evaluation_ecephys_6_9.collect()
	path 'capsule/data/ks4/' from capsule_spikesort_kilosort_4_ecephys_5_to_capsule_hybrid_evaluation_ecephys_6_10.collect()
	path 'capsule/data/ks25/' from capsule_spikesort_kilosort_25_ecephys_4_to_capsule_hybrid_evaluation_ecephys_6_11.collect()

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
	git clone "https://\$GIT_ACCESS_TOKEN@\$GIT_HOST/capsule-5273805.git" capsule-repo
	git -C capsule-repo checkout 99d81857887badf0903b42a84e8c6ff738a6fddb --quiet
	mv capsule-repo/code capsule/code
	rm -rf capsule-repo

	echo "[${task.tag}] running capsule..."
	cd capsule/code
	chmod +x run
	./run ${params.capsule_hybrid_evaluation_ecephys_6_args}

	echo "[${task.tag}] completed!"
	"""
}
