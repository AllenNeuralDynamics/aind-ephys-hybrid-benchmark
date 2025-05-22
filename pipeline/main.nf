#!/usr/bin/env nextflow
// hash:sha256:5fc7a109f0e2cfc47cdbb80413dc363133bbf75355c0e995a4642e01357e0a79

nextflow.enable.dsl = 1

ecephys_np1_benchmark_list = new File('combined-data/ecephys_np1_benchmark.txt').readLines() // id: 51f9b4df-043b-490b-947e-680818664419

ecephys_np1_benchmark_to_job_dispatch_ecephys_dev__1 = channel.fromPath(ecephys_np1_benchmark_list)
ecephys_np1_benchmark_to_hybrid_generation_ecephys_2 = channel.fromPath(ecephys_np1_benchmark_list)
capsule_job_dispatch_ecephys_dev_1_to_capsule_hybrid_generation_ecephys_2_3 = channel.create()
ecephys_np1_benchmark_to_preprocess_ecephys_4 = channel.fromPath(ecephys_np1_benchmark_list)
capsule_hybrid_generation_ecephys_2_to_capsule_preprocess_ecephys_3_5 = channel.create()
capsule_preprocess_ecephys_3_to_capsule_spikesort_kilosort_25_ecephys_4_6 = channel.create()
capsule_preprocess_ecephys_3_to_capsule_spikesort_kilosort_4_ecephys_5_7 = channel.create()
ecephys_np1_benchmark_to_hybrid_evaluation_ecephys_8 = channel.fromPath(ecephys_np1_benchmark_list)
capsule_spikesort_spyking_circus_2_ecephys_7_to_capsule_hybrid_evaluation_ecephys_6_9 = channel.create()
capsule_hybrid_generation_ecephys_2_to_capsule_hybrid_evaluation_ecephys_6_10 = channel.create()
capsule_spikesort_kilosort_4_ecephys_5_to_capsule_hybrid_evaluation_ecephys_6_11 = channel.create()
capsule_spikesort_kilosort_25_ecephys_4_to_capsule_hybrid_evaluation_ecephys_6_12 = channel.create()
capsule_preprocess_ecephys_3_to_capsule_spikesort_spyking_circus_2_ecephys_7_13 = channel.create()

// capsule - Job Dispatch Ecephys (dev)
process capsule_job_dispatch_ecephys_dev_1 {
	tag 'capsule-5832718'
	container "$REGISTRY_HOST/capsule/cb734cf3-2f88-4b69-bf0a-d5869e6706e3:17395ffb8306cfc8136112623abf7a86"

	cpus 8
	memory '64 GB'

	input:
	path 'capsule/data/' from ecephys_np1_benchmark_to_job_dispatch_ecephys_dev__1.collect()

	output:
	path 'capsule/results/*' into capsule_job_dispatch_ecephys_dev_1_to_capsule_hybrid_generation_ecephys_2_3

	script:
	"""
	#!/usr/bin/env bash
	set -e

	export CO_CAPSULE_ID=cb734cf3-2f88-4b69-bf0a-d5869e6706e3
	export CO_CPUS=8
	export CO_MEMORY=68719476736

	mkdir -p capsule
	mkdir -p capsule/data && ln -s \$PWD/capsule/data /data
	mkdir -p capsule/results && ln -s \$PWD/capsule/results /results
	mkdir -p capsule/scratch && ln -s \$PWD/capsule/scratch /scratch

	echo "[${task.tag}] cloning git repo..."
	git clone "https://\$GIT_ACCESS_TOKEN@\$GIT_HOST/capsule-5832718.git" capsule-repo
	git -C capsule-repo checkout a9baa5d3f7915846fd3525be421079001eba2c8c --quiet
	mv capsule-repo/code capsule/code
	rm -rf capsule-repo

	echo "[${task.tag}] running capsule..."
	cd capsule/code
	chmod +x run
	./run ${params.capsule_job_dispatch_ecephys_dev_1_args}

	echo "[${task.tag}] completed!"
	"""
}

// capsule - Hybrid Generation Ecephys
process capsule_hybrid_generation_ecephys_2 {
	tag 'capsule-9051504'
	container "$REGISTRY_HOST/capsule/bc02ffcd-a183-4ac4-8bda-021dc1cf01cb:4c0b67d9d541c137a491693538eeee28"

	cpus 16
	memory '64 GB'

	input:
	path 'capsule/data/' from ecephys_np1_benchmark_to_hybrid_generation_ecephys_2.collect()
	path 'capsule/data/' from capsule_job_dispatch_ecephys_dev_1_to_capsule_hybrid_generation_ecephys_2_3.flatten()

	output:
	path 'capsule/results/recordings/*' into capsule_hybrid_generation_ecephys_2_to_capsule_preprocess_ecephys_3_5
	path 'capsule/results/flattened/*' into capsule_hybrid_generation_ecephys_2_to_capsule_hybrid_evaluation_ecephys_6_10

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
	git -C capsule-repo checkout 4ca051ffb28713dedeeb2a77a1c5d1a2b3e86058 --quiet
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
	container "$REGISTRY_HOST/capsule/05eaf483-9ca3-4a9e-8da8-7d23717f6faf:0a03c1c9e1faa667c7edf99eb70bf077"

	cpus 32
	memory '128 GB'

	input:
	path 'capsule/data/' from ecephys_np1_benchmark_to_preprocess_ecephys_4.collect()
	path 'capsule/data/' from capsule_hybrid_generation_ecephys_2_to_capsule_preprocess_ecephys_3_5.flatten()

	output:
	path 'capsule/results/*' into capsule_preprocess_ecephys_3_to_capsule_spikesort_kilosort_25_ecephys_4_6
	path 'capsule/results/*' into capsule_preprocess_ecephys_3_to_capsule_spikesort_kilosort_4_ecephys_5_7
	path 'capsule/results/*' into capsule_preprocess_ecephys_3_to_capsule_spikesort_spyking_circus_2_ecephys_7_13

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
	git clone "https://\$GIT_ACCESS_TOKEN@\$GIT_HOST/capsule-0874799.git" capsule-repo
	git -C capsule-repo checkout ec8bcea53f1ec4b485ceb5e4ccf3b11c84069fdb --quiet
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
	container "$REGISTRY_HOST/capsule/9c169ec3-5933-4b10-808b-6fa4620e37b7:11a12ea2723737f9d71ee4b6b7dec426"

	cpus 16
	memory '64 GB'
	accelerator 1
	label 'gpu'

	input:
	path 'capsule/data/' from capsule_preprocess_ecephys_3_to_capsule_spikesort_kilosort_25_ecephys_4_6

	output:
	path 'capsule/results/*' into capsule_spikesort_kilosort_25_ecephys_4_to_capsule_hybrid_evaluation_ecephys_6_12

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
	git clone "https://\$GIT_ACCESS_TOKEN@\$GIT_HOST/capsule-2633671.git" capsule-repo
	git -C capsule-repo checkout b310dc8ca4404f587bfa9330bdd25490ffc60d8b --quiet
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
	container "$REGISTRY_HOST/capsule/e41ff24a-791c-4a11-a810-0106707d3617:45a23395522be4b30429efdf53bdebae"

	cpus 16
	memory '64 GB'
	accelerator 1
	label 'gpu'

	input:
	path 'capsule/data/' from capsule_preprocess_ecephys_3_to_capsule_spikesort_kilosort_4_ecephys_5_7

	output:
	path 'capsule/results/*' into capsule_spikesort_kilosort_4_ecephys_5_to_capsule_hybrid_evaluation_ecephys_6_11

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
	git -C capsule-repo checkout e48973f8d96645b2626615c0e738a27131d96364 --quiet
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
	container "$REGISTRY_HOST/capsule/e8752278-0e96-4e74-a179-2c838bc0c186:ba1d4ac125897cb9f67cc925057ee306"

	cpus 16
	memory '128 GB'

	publishDir "$RESULTS_PATH", saveAs: { filename -> new File(filename).getName() }

	input:
	path 'capsule/data/' from ecephys_np1_benchmark_to_hybrid_evaluation_ecephys_8.collect()
	path 'capsule/data/sc2/' from capsule_spikesort_spyking_circus_2_ecephys_7_to_capsule_hybrid_evaluation_ecephys_6_9.collect()
	path 'capsule/data/' from capsule_hybrid_generation_ecephys_2_to_capsule_hybrid_evaluation_ecephys_6_10.collect()
	path 'capsule/data/ks4/' from capsule_spikesort_kilosort_4_ecephys_5_to_capsule_hybrid_evaluation_ecephys_6_11.collect()
	path 'capsule/data/ks25/' from capsule_spikesort_kilosort_25_ecephys_4_to_capsule_hybrid_evaluation_ecephys_6_12.collect()

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
	git -C capsule-repo checkout d999eae27545192cbd0e6fa2820ddef414f4ef5a --quiet
	mv capsule-repo/code capsule/code
	rm -rf capsule-repo

	echo "[${task.tag}] running capsule..."
	cd capsule/code
	chmod +x run
	./run

	echo "[${task.tag}] completed!"
	"""
}

// capsule - Spikesort SpykingCircus2 Ecephys
process capsule_spikesort_spyking_circus_2_ecephys_7 {
	tag 'capsule-1515622'
	container "$REGISTRY_HOST/capsule/b68f9aec-7e8d-4862-865a-38081f5a6aeb:cbb8522e6b68b5db56b1d81fcdc3c913"

	cpus 32
	memory '128 GB'

	input:
	path 'capsule/data/' from capsule_preprocess_ecephys_3_to_capsule_spikesort_spyking_circus_2_ecephys_7_13

	output:
	path 'capsule/results/*' into capsule_spikesort_spyking_circus_2_ecephys_7_to_capsule_hybrid_evaluation_ecephys_6_9

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
	git clone "https://\$GIT_ACCESS_TOKEN@\$GIT_HOST/capsule-1515622.git" capsule-repo
	git -C capsule-repo checkout 3667485d2468acd176f26c3fd27325878c4b8327 --quiet
	mv capsule-repo/code capsule/code
	rm -rf capsule-repo

	echo "[${task.tag}] running capsule..."
	cd capsule/code
	chmod +x run
	./run ${params.capsule_spikesort_spyking_circus_2_ecephys_7_args}

	echo "[${task.tag}] completed!"
	"""
}
