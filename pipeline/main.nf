#!/usr/bin/env nextflow
nextflow.enable.dsl = 2

include { validate } from 'plugin/nf-schema'

params.ecephys_path = params.ecephys_url ?: DATA_PATH
params.params_file = null

// Helper function for git cloning
gitCloneFunction = '''
clone_repo() {
    local repo_url="$1"
    local commit_hash="$2"

    echo "cloning git repo: \${repo_url} (commit: \${commit_hash})..."

    git clone "\${repo_url}" capsule-repo
    git -C capsule-repo -c core.fileMode=false checkout "\${commit_hash}" --quiet

    mv capsule-repo/code capsule/code
    rm -rf capsule-repo
}
'''

// Recursively merge `over` into `base` (returns a new map)
def deepMerge(Map base, Map over) {
    def out = new LinkedHashMap(base)
    over.each { k, v ->
        out[k] = (out[k] instanceof Map && v instanceof Map) ? deepMerge(out[k], v) : v
    }
    return out
}

// Coerce a CLI value (Nextflow guesses int/float/boolean from the text) to the type the schema expects.
// Values already matching an allowed type, or that cannot be converted, are left for validation to report.
def coerceToSchema(value, Map node, Map root) {
    if (node?.get('$ref')) {
        node = node['$ref'].replaceFirst('^#/', '').split('/').inject(root) { n, k -> n[k] }
    }
    // objects from the CLI: a JSON string (--sorting_cases '{"ks4": {...}}') or a JSON file (--sorting_cases cases.json)
    if (node?.type == 'object' && value instanceof CharSequence) {
        def text = value.toString().trim()
        if (text.startsWith('{')) value = new groovy.json.JsonSlurper().parseText(text)
        else if (new File(text).isFile()) value = new groovy.json.JsonSlurper().parseText(new File(text).text)
    }
    if (value instanceof Map) {
        return value.collectEntries { k, v -> [(k): coerceToSchema(v, node?.properties?.get(k) ?: [:], root)] }
    }
    def types = node?.type instanceof List ? node.type : (node?.type ? [node.type] : [])
    if (!types) return value
    // arrays from the CLI: a JSON list, or comma/plus separated (--sorters kilosort4,spykingcircus2)
    if ('array' in types && !(value instanceof List)) {
        def text = value.toString().trim()
        if (text.startsWith('[')) return new groovy.json.JsonSlurper().parseText(text)
        return text.split(/[,+]/).collect { it.trim() }.findAll { it }.collect { it.isNumber() ? it.toBigDecimal() : it }
    }
    def matches = { t ->
        (t == 'string' && value instanceof String) || (t == 'boolean' && value instanceof Boolean) ||
        (t == 'integer' && value instanceof Integer) || (t == 'number' && value instanceof Number) ||
        (t == 'array' && value instanceof List)
    }
    if (types.any(matches)) return value
    def text = value.toString()
    if ('null' in types && text == 'null') return null
    if ('integer' in types && value instanceof Number && value == value.intValue()) return value.intValue()
    if ('integer' in types && text.isInteger()) return text.toInteger()
    if ('number' in types && text.isNumber()) return text.toBigDecimal()
    if ('boolean' in types && text in ['true', 'false']) return text == 'true'
    if ('string' in types) return text
    return value
}

println "DATA_PATH: ${params.ecephys_path}"
println "RESULTS_PATH: ${RESULTS_PATH}"

// Load parameters from custom JSON file, or default_params
def json_params = [:]
if (params.params_file) {
    json_params = new groovy.json.JsonSlurper().parseText(new File(params.params_file).text)
    println "Loaded parameters from ${params.params_file}"
}
else {
    params.params_file = "${baseDir}/default_params.json"
    json_params = new groovy.json.JsonSlurper().parseText(new File("${baseDir}/default_params.json").text)
    println "Loaded parameters from DEFAULT_PARAMS"
}

// Dotted CLI overrides following the JSON layout, e.g. --hybrid_generation.num_cases=2
// (Nextflow turns them into nested maps in `params`); merged before validation so they are checked too.
// Top-level keys are plain flags: --benchmark lossy, --existing, --sorters kilosort4,spykingcircus2
def step_keys = ['logging', 'job_dispatch', 'hybrid_generation', 'compression', 'preprocessing', 'spikesorting', 'hybrid_evaluation']
def top_keys = ['benchmark', 'existing', 'sorters', 'sorter', 'compression_cases', 'sorting_cases']
def cli_overrides = [:]
// Same overrides packed in one string, for Code Ocean (only App Panel params are forwarded), e.g.
// --extra_params "--benchmark=lossy --hybrid_generation.num_cases=2 --spikesorting.kilosort4.sorter.batch_size=30000"
// shortcut: whitespace split, so values can't contain spaces; use the params file for those
if (params.containsKey('extra_params') && params.extra_params instanceof String) {
    def tokens = params.extra_params.trim().split(/\s+/) as List
    for (int i = 0; i < tokens.size(); i++) {
        if (!tokens[i].startsWith('--')) continue
        def (key, value) = tokens[i].substring(2).contains('=') ? tokens[i].substring(2).split('=', 2) as List :
            [tokens[i].substring(2), (i + 1 < tokens.size() && !tokens[i + 1].startsWith('--')) ? tokens[++i] : 'true']
        def path = key.split(/\./) as List
        if (!(path.size() == 1 && path[0] in top_keys) && !(path[0] in step_keys && path.size() >= 2)) {
            println "WARN: ignoring extra_params entry '--${key}' (must be one of ${top_keys} or start with one of ${step_keys})"
            continue
        }
        cli_overrides = deepMerge(cli_overrides, path.reverse().inject(value) { acc, k -> [(k): acc] })
    }
}
cli_overrides = deepMerge(cli_overrides, step_keys.findAll { params.containsKey(it) && params[it] instanceof Map }.collectEntries { [(it): params[it]] })
cli_overrides = deepMerge(cli_overrides, top_keys.findAll { params.containsKey(it) && !(params[it] instanceof Map) }.collectEntries { [(it): params[it]] })
if (cli_overrides) {
    println "Merging CLI parameters: ${cli_overrides}"
    def schema = new groovy.json.JsonSlurper().parseText(new File("${projectDir}/default_params_schema.json").text)
    json_params = deepMerge(json_params, coerceToSchema(cli_overrides, schema, schema))
}

// Validate the parameters file against the schema before any process runs
def params_file_name = params.params_file ?: "default_params.json"
def params_errors = validate(json_params, "${projectDir}/default_params_schema.json", exitOnError: false)
if (params_errors) {
    error "Invalid parameters in ${params_file_name}:\n" + params_errors.collect { "  * ${it}" }.join('\n')
}
println "Parameters in ${params_file_name} are valid"

println "PARAMS: ${params}"

// get commit hashes for capsules
def parse_capsule_versions() {
    // Check for custom versions file first, fall back to default
    def versionsFile = file("${baseDir}/process_versions_custom.env")
    if (!versionsFile.exists()) {
        versionsFile = file("${baseDir}/process_versions.env")
    }
    def capsule_versions = versionsFile.toString()
    println "Using capsule versions file at: ${capsule_versions}"

    def versions = [:]
    if (file(capsule_versions).exists()) {
        file(capsule_versions).eachLine { line ->
            if (line.contains('=')) {
                def idx = line.indexOf('=')
                def key = line.substring(0, idx).trim()
                def value = line.substring(idx + 1).trim().replaceAll(/^["']|["']$/, '')
                versions[key] = value
            }
        }
    } else {
        println "Warning: Capsule versions file not found at ${capsule_versions}. Using empty versions map."
    }
    versions
}

versions = parse_capsule_versions()

// Allow CLI/config to override individual step repos and commits.
// Usage: --preprocessing_repo <url> --preprocessing_version <hash>
// (Nextflow converts --foo-bar to params.foo_bar automatically)
def step_version_keys = [
    'job_dispatch':        ['JOB_DISPATCH_REPO',        'JOB_DISPATCH_VERSION'],
    'job_dispatch_hybrid': ['JOB_DISPATCH_HYBRID_REPO', 'JOB_DISPATCH_HYBRID_VERSION'],
    'hybrid_generation':   ['HYBRID_GENERATION_REPO',   'HYBRID_GENERATION_VERSION'],
    'compression':         ['COMPRESSION_REPO',         'COMPRESSION_VERSION'],
    'preprocessing':       ['PREPROCESSING_REPO',       'PREPROCESSING_VERSION'],
    'spikesort_ks25':      ['SPIKESORT_KS25_REPO',      'SPIKESORT_KS25_VERSION'],
    'spikesort_ks4':       ['SPIKESORT_KS4_REPO',       'SPIKESORT_KS4_VERSION'],
    'spikesort_sc2':       ['SPIKESORT_SC2_REPO',       'SPIKESORT_SC2_VERSION'],
    'spikesort_lupin':     ['SPIKESORT_LUPIN_REPO',     'SPIKESORT_LUPIN_VERSION'],
    'spikesort_dartsort':  ['SPIKESORT_DARTSORT_REPO',  'SPIKESORT_DARTSORT_VERSION'],
    'hybrid_evaluation':   ['HYBRID_EVALUATION_REPO',   'HYBRID_EVALUATION_VERSION'],
]
step_version_keys.each { step, keys ->
    if (params.containsKey(step + "_repo")) {
        versions[keys[0]] = params[step + "_repo"]
        println "OVERRIDE ${keys[0]} (from CLI): ${versions[keys[0]]}"
    }
    if (params.containsKey(step + "_version")) {
        versions[keys[1]] = params[step + "_version"]
        println "OVERRIDE ${keys[1]} (from CLI): ${versions[keys[1]]}"
    }
}

// Read pipeline version from pipeline_version.txt
pipelineVersion = ""
def pipelineVersionFile = file("${baseDir}/pipeline_version.txt")
if (pipelineVersionFile.exists()) {
    pipelineVersion = pipelineVersionFile.text.trim()
    println "Loaded PIPELINE VERSION from pipeline_version.txt: ${pipelineVersion}"
} else {
    println "Warning: pipeline_version.txt not found at ${baseDir}/pipeline_version.txt"
}
pipelineUrl = "https://github.com/AllenNeuralDynamics/aind-ephys-hybrid-benchmark"

println "PIPELINE VERSION: ${pipelineVersion}"
println "PIPELINE URL: ${pipelineUrl}"

// container tag: CLI/config > CONTAINER_TAG env var > pipeline_version.txt
def env_container_tag = System.getenv('CONTAINER_TAG')
if (params.containsKey('container_tag')) {
    println "CONTAINER TAG (from CLI/config): ${params.container_tag}"
} else if (env_container_tag) {
    params.container_tag = env_container_tag
    println "CONTAINER TAG (from ENV): ${params.container_tag}"
} else {
    if (!pipelineVersion) {
        error "Cannot determine container tag: set --container_tag, CONTAINER_TAG env var, or provide pipeline_version.txt"
    }
    params.container_tag = pipelineVersion
    println "CONTAINER TAG (from pipeline_version.txt): ${params.container_tag}"
}
params.extra_installs = params.extra_installs ?: ""
if (params.extra_installs) {
    println "Extra installs specified: ${params.extra_installs}"
} else {
    println "No extra installs specified."
}
def extra_installs_list = params.extra_installs ? params.extra_installs.split(',').collect { it.trim() }.findAll { it } : []
extra_installs_cmd = extra_installs_list ? "pip install " + extra_installs_list.collect { "'" + it + "'" }.join(' ') : ""
extra_installs_echo = extra_installs_list ? "echo 'installing extra packages: " + extra_installs_list.join(', ') + "'" : ""

// params keys on the outer level were loaded via CLI flags (the `json_params` are from the `params_file`)
params_keys = params.keySet()

// if not specified, assume local executor
if (!params_keys.contains('executor')) {
    params.executor = "local"
}
// set global n_jobs for local executor
if (params.executor == "local") {
    n_jobs = ("n_jobs" in params_keys) ? params.n_jobs : -1
    println "N JOBS: ${n_jobs}"
}

// Full parameter map (a deep copy of the merged JSON), staged into every task as capsule/params.json
def full_params = new groovy.json.JsonSlurper().parseText(groovy.json.JsonOutput.toJson(json_params))

benchmark = full_params.benchmark ?: 'sorters'
existing = full_params.existing ?: false
println "EXISTING: ${existing}"

// Sorting cases: {name: {step: {params, repo, commit}}}. Each case is a chain of fixed slots
//   job file -> [compress_wavpack] -> preprocessing -> spikesort_<sorter> -> sorting folder
// Explicit `sorting_cases` win; otherwise the `benchmark` preset builds them:
//   sorters: one case per sorter in `sorters`; lossy: one case per `compression_cases` entry with `sorter`
case_defs = full_params.sorting_cases ?: [:]
if (case_defs) {
    println "SORTING CASES: from sorting_cases (benchmark '${benchmark}' ignored)"
} else if (benchmark == 'sorters') {
    case_defs = full_params.sorters.collectEntries { s -> [(s): [preprocessing: [:], ("spikesort_${s}".toString()): [:]]] }
} else {
    def sort_step = "spikesort_${full_params.sorter}".toString()
    case_defs = full_params.compression_cases.collectEntries { c ->
        c == 'lossless' ? ['lossless': [preprocessing: [:], (sort_step): [:]]] :
            [("wv-${c}".toString()): [compress_wavpack: [params: [bps: c]], preprocessing: [:], (sort_step): [:]]]
    }
}

// Existing hybrid datasets on S3 are listed and read by the steps directly: don't stage them
def input_is_s3 = params.ecephys_path.toString().startsWith('s3://')
stage_input = true
if (existing && input_is_s3) {
    full_params.job_dispatch.s3_path = full_params.job_dispatch.s3_path ?: params.ecephys_path.toString()
    stage_input = false
}
println "JOB DISPATCH S3 PATH: ${full_params.job_dispatch.s3_path}"
// shortcut: job_dispatch streaming is not wired here (hybrid_generation reads the staged session); add it if needed
if (full_params.job_dispatch.streaming) {
    println "WARN: job_dispatch.streaming is not supported by the hybrid benchmark: staging the session"
    full_params.job_dispatch.streaming = false
}

// Tag logs with the acquisition name from data_description.json and the pipeline name;
// values set by the user in the params file take priority
full_params.logging = full_params.logging ?: [:]
if (!full_params.logging.acquisition_name) {
    def acquisition_name = null
    try {
        def data_description = file("${params.ecephys_path}/data_description.json")
        if (data_description.exists()) {
            acquisition_name = new groovy.json.JsonSlurper().parseText(data_description.text).name
        }
    } catch (Exception e) {
        println "WARN: could not read data_description.json: ${e.message}"
    }
    if (!acquisition_name) {
        println "WARN: no name found in ${params.ecephys_path}/data_description.json, using 'undefined'"
        acquisition_name = 'undefined'
    }
    full_params.logging.acquisition_name = acquisition_name
}
if (!full_params.logging.pipeline_name) {
    full_params.logging.pipeline_name = 'AIND Ephys Hybrid Benchmark'
}
println "Logging acquisition_name: ${full_params.logging.acquisition_name}"

// Dump the full map to the work dir so it can be inspected/attached to tasks
def full_params_file = new File("${workDir}/full_params.json")
full_params_file.parentFile.mkdirs()
// Rewrite only on change: tasks hash the staged file's mtime, so touching it would invalidate -resume
// The keys choosing the sorting cases are not staged: adding a case must not rerun dispatch/generation or other cases
def case_selection_keys = ['benchmark', 'sorters', 'sorter', 'compression_cases', 'sorting_cases']
staged_params = full_params.findAll { k, v -> !(k in case_selection_keys) }
def full_params_text = groovy.json.JsonOutput.prettyPrint(groovy.json.JsonOutput.toJson(staged_params))
if (!full_params_file.exists() || full_params_file.text != full_params_text) {
    full_params_file.text = full_params_text
}
println "Full parameters written to ${full_params_file}"

// Validate the final map (JSON + CLI + path/log adjustments) against the schema
def full_params_errors = validate(new groovy.json.JsonSlurper().parseText(full_params_file.text), "${projectDir}/default_params_schema.json", exitOnError: false)
if (full_params_errors) {
    error "Invalid full parameters (${full_params_file}):\n" + full_params_errors.collect { "  * ${it}" }.join('\n')
}
println "Full parameters are valid"

// Resolve the sorting cases. Each step gets its params section (base + step `params`) and its repo/commit
// (pinned in process_versions.env unless overridden). Cases with the same compression + preprocessing
// (a "variant") share those tasks; each case gets its own params file for the sorter.
sorter_steps = ['spikesort_kilosort4', 'spikesort_kilosort25', 'spikesort_spykingcircus2', 'spikesort_lupin', 'spikesort_dartsort']
def step_section = { step -> step == 'compress_wavpack' ? ['compression'] : step == 'preprocessing' ? ['preprocessing'] : ['spikesorting', step - 'spikesort_'] }
def step_version_key = { step -> step == 'compress_wavpack' ? 'compression' : step == 'preprocessing' ? 'preprocessing' :
    ['kilosort4': 'spikesort_ks4', 'kilosort25': 'spikesort_ks25', 'spykingcircus2': 'spikesort_sc2', 'lupin': 'spikesort_lupin', 'dartsort': 'spikesort_dartsort'][step - 'spikesort_'] }
def json_copy = { m -> new groovy.json.JsonSlurper().parseText(groovy.json.JsonOutput.toJson(m)) }
def get_section = { m, path -> path.inject(m) { n, k -> n?.get(k) } ?: [:] }
def set_section = { m, path, v -> path.take(path.size() - 1).inject(m) { n, k -> n[k] } [path[-1]] = v }
def md5 = { text -> java.security.MessageDigest.getInstance('MD5').digest(text.bytes).encodeHex().toString() }
def params_dir = new File("${workDir}/params")
params_dir.mkdirs()
def write_params = { name, m ->
    def f = new File(params_dir, "${name}.json")
    def text = groovy.json.JsonOutput.prettyPrint(groovy.json.JsonOutput.toJson(m))
    if (!f.exists() || f.text != text) { f.text = text }  // rewrite only on change (keeps -resume)
    f.toString()
}

variant_files = [:]   // variant key -> params file
variant_metas = [:]   // variant key -> meta fields of its compression/preprocessing tasks
case_list = []        // [variant key, case meta, case params file]
resolved_cases = [:]  // for provenance
case_defs.each { case_name, chain ->
    def sorters_in_case = chain.keySet().findAll { it in sorter_steps }
    if (sorters_in_case.size() != 1) {
        error "Sorting case '${case_name}' must have exactly one spikesort_* step, found ${sorters_in_case}"
    }
    if (!chain.containsKey('preprocessing')) {
        error "Sorting case '${case_name}' has no preprocessing step"
    }
    def case_params = json_copy(staged_params)
    def check_params = json_copy(staged_params)  // what is validated: custom-repo sections keep the base values
    def resolved = [:]
    chain.each { step, cfg ->
        def (repo_key, commit_key) = step_version_keys[step_version_key(step)]
        def custom_repo = cfg.repo && cfg.repo != versions[repo_key]
        def section = deepMerge(get_section(staged_params, step_section(step)), cfg.params ?: [:])
        set_section(case_params, step_section(step), section)
        if (custom_repo) {
            println "WARN: sorting case '${case_name}' uses a custom ${step} repo (${cfg.repo}): its params are not validated"
        } else {
            set_section(check_params, step_section(step), section)
        }
        resolved[step] = [repo: cfg.repo ?: versions[repo_key],
                          commit: cfg.commit ?: (custom_repo ? 'HEAD' : versions[commit_key]),
                          params: section]
    }
    def errors = validate(check_params, "${projectDir}/default_params_schema.json", exitOnError: false)
    if (errors) {
        error "Invalid params for sorting case '${case_name}':\n" + errors.collect { "  * ${it}" }.join('\n')
    }
    def sort_step = sorters_in_case[0]
    def compress = resolved['compress_wavpack']
    // the variant: everything the compression + preprocessing tasks depend on
    def variant_params = json_copy(case_params)
    variant_params.spikesorting = staged_params.spikesorting
    def variant_key = md5(groovy.json.JsonOutput.toJson([variant_params, compress?.subMap(['repo', 'commit']), resolved.preprocessing.subMap(['repo', 'commit'])])).take(10)
    if (!variant_files.containsKey(variant_key)) {
        variant_files[variant_key] = write_params("variant_${variant_key}", variant_params)
        variant_metas[variant_key] = [variant: variant_key,
                                      compress: compress != null, bps: compress?.params?.bps,
                                      compress_repo: compress?.repo, compress_commit: compress?.commit,
                                      pp_repo: resolved.preprocessing.repo, pp_commit: resolved.preprocessing.commit]
    }
    case_list << [variant_key,
                  [case: case_name, sorter: sort_step - 'spikesort_', sort_repo: resolved[sort_step].repo, sort_commit: resolved[sort_step].commit],
                  write_params("case_${case_name}", case_params)]
    resolved_cases[case_name] = resolved
}
used_sorters = case_list.collect { it[1].sorter }.unique()
println "SORTING CASES: " + case_list.collect { "${it[1].case} (${it[1].sorter}, variant ${it[0]})" }.join(', ')
println "PREPROCESSING VARIANTS: ${variant_files.size()}"

// Process definitions
process job_dispatch {
    tag 'job-dispatch'
    def container_name = "ghcr.io/allenneuraldynamics/aind-ephys-pipeline-base:${params.container_tag}"
    container container_name

    input:
    path input_folder, stageAs: 'capsule/data/ecephys_session'
    path params_file, stageAs: 'capsule/params.json'

    output:
    path 'capsule/results/*', emit: results
    path 'max_duration.txt', emit: max_duration_file  // file containing the value

    script:
    """
    #!/usr/bin/env bash
    set -e

    ${extra_installs_echo}
    ${extra_installs_cmd}

    export CODE_REPO="${versions['JOB_DISPATCH_REPO']}"
    export CODE_VERSION="${versions['JOB_DISPATCH_VERSION']}"

    mkdir -p capsule
    mkdir -p capsule/data
    mkdir -p capsule/results
    mkdir -p capsule/scratch

    if [[ ${params.executor} == "slurm" ]]; then
        echo "[${task.tag}] allocated task time: ${task.time}"
    fi
    # Make sure N_JOBS matches allocated CPUs
    export N_JOBS_EXT=${params.get('n_jobs') ?: task.cpus}

    TASK_DIR=\$(pwd)

    echo "[${task.tag}] cloning git repo..."
    ${gitCloneFunction}
    clone_repo "${versions['JOB_DISPATCH_REPO']}" "${versions['JOB_DISPATCH_VERSION']}"

    echo "[${task.tag}] running capsule..."
    cd capsule/code
    chmod +x run
    ./run

    MAX_DURATION_MIN=\$(python get_max_recording_duration_min.py)

    cd \$TASK_DIR
    echo "\$MAX_DURATION_MIN" > max_duration.txt

    echo "[${task.tag}] completed!"
    """
}

// Existing hybrid datasets: replaces job_dispatch + hybrid_generation
process job_dispatch_hybrid {
    tag 'job-dispatch-hybrid'
    def container_name = "ghcr.io/allenneuraldynamics/aind-ephys-pipeline-base:${params.container_tag}"
    container container_name

    input:
    path input_folder, stageAs: 'capsule/data/ecephys_session'
    path params_file, stageAs: 'capsule/params.json'

    output:
    path 'capsule/results/recordings/*', emit: recordings
    path 'capsule/results/flattened/*', emit: flattened
    path 'max_duration.txt', emit: max_duration_file

    script:
    """
    #!/usr/bin/env bash
    set -e

    ${extra_installs_echo}
    ${extra_installs_cmd}

    export CODE_REPO="${versions['JOB_DISPATCH_HYBRID_REPO']}"
    export CODE_VERSION="${versions['JOB_DISPATCH_HYBRID_VERSION']}"

    mkdir -p capsule
    mkdir -p capsule/data
    mkdir -p capsule/results
    mkdir -p capsule/scratch

    if [[ ${params.executor} == "slurm" ]]; then
        echo "[${task.tag}] allocated task time: ${task.time}"
    fi
    # Make sure N_JOBS matches allocated CPUs
    export N_JOBS_EXT=${params.get('n_jobs') ?: task.cpus}

    TASK_DIR=\$(pwd)

    echo "[${task.tag}] cloning git repo..."
    ${gitCloneFunction}
    clone_repo "${versions['JOB_DISPATCH_HYBRID_REPO']}" "${versions['JOB_DISPATCH_HYBRID_VERSION']}"

    echo "[${task.tag}] running capsule..."
    cd capsule/code
    chmod +x run
    ./run

    MAX_DURATION_MIN=\$(python get_max_recording_duration_min.py)

    cd \$TASK_DIR
    echo "\$MAX_DURATION_MIN" > max_duration.txt

    echo "[${task.tag}] completed!"
    """
}

process hybrid_generation {
    tag 'hybrid-generation'
    def container_name = "ghcr.io/allenneuraldynamics/aind-ephys-pipeline-base:${params.container_tag}"
    container container_name

    input:
    val max_duration_minutes
    path job_json, stageAs: 'capsule/data/*'
    path ecephys_session_input, stageAs: 'capsule/data/ecephys_session'
    path params_file, stageAs: 'capsule/params.json'

    output:
    path 'capsule/results/recordings/*', emit: recordings
    path 'capsule/results/flattened/*', emit: flattened

    script:
    """
    #!/usr/bin/env bash
    set -e

    ${extra_installs_echo}
    ${extra_installs_cmd}

    export CODE_REPO="${versions['HYBRID_GENERATION_REPO']}"
    export CODE_VERSION="${versions['HYBRID_GENERATION_VERSION']}"

    mkdir -p capsule
    mkdir -p capsule/data
    mkdir -p capsule/results
    mkdir -p capsule/scratch

    if [[ ${params.executor} == "slurm" ]]; then
        echo "[${task.tag}] allocated task time: ${task.time}"
    fi
    # Make sure N_JOBS matches allocated CPUs
    export N_JOBS_EXT=${params.get('n_jobs') ?: task.cpus}

    echo "[${task.tag}] cloning git repo..."
    ${gitCloneFunction}
    clone_repo "${versions['HYBRID_GENERATION_REPO']}" "${versions['HYBRID_GENERATION_VERSION']}"

    echo "[${task.tag}] running capsule..."
    cd capsule/code
    chmod +x run
    ./run

    echo "[${task.tag}] completed!"
    """
}

// One task per hybrid recording and compression variant (sorting cases with a compress_wavpack step)
process compress_wavpack {
    tag 'compress-wavpack'
    def container_name = "ghcr.io/allenneuraldynamics/aind-ephys-pipeline-base:${params.container_tag}"
    container container_name

    input:
    val max_duration_minutes
    tuple val(meta), path(job_files, stageAs: 'capsule/data/*'), path(params_file, stageAs: 'capsule/params.json')
    path ecephys_session_input, stageAs: 'capsule/data/ecephys_session'

    output:
    tuple val(meta), path('capsule/results/*', arity: '1..*'), emit: results

    script:
    """
    #!/usr/bin/env bash
    set -e

    ${extra_installs_echo}
    ${extra_installs_cmd}

    export CODE_REPO="${meta.compress_repo}"
    export CODE_VERSION="${meta.compress_commit}"

    mkdir -p capsule
    mkdir -p capsule/data
    mkdir -p capsule/results
    mkdir -p capsule/scratch
    # hybrid recordings refer to their GT sorting as ../scratch/gt_<id>: move the staged gt_<id> folders there
    for gt_folder in capsule/data/gt_*; do if [ -e "\$gt_folder" ]; then mv "\$gt_folder" capsule/scratch/; fi; done

    if [[ ${params.executor} == "slurm" ]]; then
        echo "[${task.tag}] allocated task time: ${task.time}"
    fi
    # Make sure N_JOBS matches allocated CPUs
    export N_JOBS_EXT=${params.get('n_jobs') ?: task.cpus}

    echo "[${task.tag}] cloning git repo..."
    ${gitCloneFunction}
    clone_repo "${meta.compress_repo}" "${meta.compress_commit}"

    echo "[${task.tag}] running capsule..."
    cd capsule/code
    chmod +x run
    ./run

    echo "[${task.tag}] completed!"
    """
}

process preprocessing {
    tag 'preprocessing'
    def container_name = "ghcr.io/allenneuraldynamics/aind-ephys-pipeline-base:${params.container_tag}"
    container container_name

    input:
    val max_duration_minutes
    tuple val(meta), path(job_files, stageAs: 'capsule/data/*'), path(params_file, stageAs: 'capsule/params.json')
    path ecephys_session_input, stageAs: 'capsule/data/ecephys_session'

    output:
    tuple val(meta), path('capsule/results/*', arity: '1..*'), emit: results

    script:
    """
    #!/usr/bin/env bash
    set -e

    ${extra_installs_echo}
    ${extra_installs_cmd}

    export CODE_REPO="${meta.pp_repo}"
    export CODE_VERSION="${meta.pp_commit}"

    mkdir -p capsule
    mkdir -p capsule/data
    mkdir -p capsule/results
    mkdir -p capsule/scratch
    # hybrid recordings refer to their GT sorting as ../scratch/gt_<id>: move the staged gt_<id> folders there
    for gt_folder in capsule/data/gt_*; do if [ -e "\$gt_folder" ]; then mv "\$gt_folder" capsule/scratch/; fi; done

    if [[ ${params.executor} == "slurm" ]]; then
        echo "[${task.tag}] allocated task time: ${task.time}"
    fi
    # Make sure N_JOBS matches allocated CPUs
    export N_JOBS_EXT=${params.get('n_jobs') ?: task.cpus}

    echo "[${task.tag}] cloning git repo..."
    ${gitCloneFunction}
    clone_repo "${meta.pp_repo}" "${meta.pp_commit}"

    echo "[${task.tag}] running capsule..."
    cd capsule/code
    chmod +x run
    ./run

    echo "[${task.tag}] completed!"
    """
}

process spikesort_kilosort25 {
    tag 'spikesort-kilosort25'
    def container_name = "ghcr.io/allenneuraldynamics/aind-ephys-spikesort-kilosort25:${params.container_tag}"
    container container_name
    label 'gpu'

    input:
    val max_duration_minutes
    tuple val(meta), path(preprocessing_results, stageAs: 'capsule/data/*'), path(params_file, stageAs: 'capsule/params.json')

    output:
    tuple val(meta), path('capsule/results/*', arity: '1..*'), emit: results

    script:
    """
    #!/usr/bin/env bash
    set -e

    export CODE_REPO="${meta.sort_repo}"
    export CODE_VERSION="${meta.sort_commit}"

    mkdir -p capsule
    mkdir -p capsule/data
    mkdir -p capsule/results
    mkdir -p capsule/scratch

    if [[ ${params.executor} == "slurm" ]]; then
        echo "[${task.tag}] allocated task time: ${task.time}"
    fi
    # Make sure N_JOBS matches allocated CPUs
    export N_JOBS_EXT=${params.get('n_jobs') ?: task.cpus}

    echo "[${task.tag}] cloning git repo..."
    ${gitCloneFunction}
    clone_repo "${meta.sort_repo}" "${meta.sort_commit}"

    echo "[${task.tag}] running capsule..."
    cd capsule/code
    chmod +x run
    ./run

    echo "[${task.tag}] completed!"
    """
}

process spikesort_kilosort4 {
    tag 'spikesort-kilosort4'
    def container_name = "ghcr.io/allenneuraldynamics/aind-ephys-spikesort-kilosort4:${params.container_tag}"
    container container_name
    label 'gpu'

    input:
    val max_duration_minutes
    tuple val(meta), path(preprocessing_results, stageAs: 'capsule/data/*'), path(params_file, stageAs: 'capsule/params.json')

    output:
    tuple val(meta), path('capsule/results/*', arity: '1..*'), emit: results

    script:
    """
    #!/usr/bin/env bash
    set -e

    export CODE_REPO="${meta.sort_repo}"
    export CODE_VERSION="${meta.sort_commit}"

    mkdir -p capsule
    mkdir -p capsule/data
    mkdir -p capsule/results
    mkdir -p capsule/scratch

    if [[ ${params.executor} == "slurm" ]]; then
        echo "[${task.tag}] allocated task time: ${task.time}"
    fi
    # Make sure N_JOBS matches allocated CPUs
    export N_JOBS_EXT=${params.get('n_jobs') ?: task.cpus}

    echo "[${task.tag}] cloning git repo..."
    ${gitCloneFunction}
    clone_repo "${meta.sort_repo}" "${meta.sort_commit}"

    echo "[${task.tag}] running capsule..."
    cd capsule/code
    chmod +x run
    ./run

    echo "[${task.tag}] completed!"
    """
}

process spikesort_spykingcircus2 {
    tag 'spikesort-spykingcircus2'
    def container_name = "ghcr.io/allenneuraldynamics/aind-ephys-pipeline-base:${params.container_tag}"
    container container_name

    input:
    val max_duration_minutes
    tuple val(meta), path(preprocessing_results, stageAs: 'capsule/data/*'), path(params_file, stageAs: 'capsule/params.json')

    output:
    tuple val(meta), path('capsule/results/*', arity: '1..*'), emit: results

    script:
    """
    #!/usr/bin/env bash
    set -e

    export CODE_REPO="${meta.sort_repo}"
    export CODE_VERSION="${meta.sort_commit}"

    mkdir -p capsule
    mkdir -p capsule/data
    mkdir -p capsule/results
    mkdir -p capsule/scratch

    if [[ ${params.executor} == "slurm" ]]; then
        echo "[${task.tag}] allocated task time: ${task.time}"
    fi
    # Make sure N_JOBS matches allocated CPUs
    export N_JOBS_EXT=${params.get('n_jobs') ?: task.cpus}

    echo "[${task.tag}] cloning git repo..."
    ${gitCloneFunction}
    clone_repo "${meta.sort_repo}" "${meta.sort_commit}"

    echo "[${task.tag}] running capsule..."
    cd capsule/code
    chmod +x run
    ./run

    echo "[${task.tag}] completed!"
    """
}

process spikesort_lupin {
    tag 'spikesort-lupin'
    def container_name = "ghcr.io/allenneuraldynamics/aind-ephys-pipeline-base:${params.container_tag}"
    container container_name

    input:
    val max_duration_minutes
    tuple val(meta), path(preprocessing_results, stageAs: 'capsule/data/*'), path(params_file, stageAs: 'capsule/params.json')

    output:
    tuple val(meta), path('capsule/results/*', arity: '1..*'), emit: results

    script:
    """
    #!/usr/bin/env bash
    set -e

    export CODE_REPO="${meta.sort_repo}"
    export CODE_VERSION="${meta.sort_commit}"

    mkdir -p capsule
    mkdir -p capsule/data
    mkdir -p capsule/results
    mkdir -p capsule/scratch

    if [[ ${params.executor} == "slurm" ]]; then
        echo "[${task.tag}] allocated task time: ${task.time}"
    fi
    # Make sure N_JOBS matches allocated CPUs
    export N_JOBS_EXT=${params.get('n_jobs') ?: task.cpus}

    echo "[${task.tag}] cloning git repo..."
    ${gitCloneFunction}
    clone_repo "${meta.sort_repo}" "${meta.sort_commit}"

    echo "[${task.tag}] running capsule..."
    cd capsule/code
    chmod +x run
    ./run

    echo "[${task.tag}] completed!"
    """
}

process spikesort_dartsort {
    tag 'spikesort-dartsort'
    def container_name = "ghcr.io/allenneuraldynamics/aind-ephys-spikesort-dartsort:${params.container_tag}"
    container container_name
    label 'gpu'

    input:
    val max_duration_minutes
    tuple val(meta), path(preprocessing_results, stageAs: 'capsule/data/*'), path(params_file, stageAs: 'capsule/params.json')

    output:
    tuple val(meta), path('capsule/results/*', arity: '1..*'), emit: results

    script:
    """
    #!/usr/bin/env bash
    set -e

    export CODE_REPO="${meta.sort_repo}"
    export CODE_VERSION="${meta.sort_commit}"

    mkdir -p capsule
    mkdir -p capsule/data
    mkdir -p capsule/results
    mkdir -p capsule/scratch

    if [[ ${params.executor} == "slurm" ]]; then
        echo "[${task.tag}] allocated task time: ${task.time}"
    fi
    # Make sure N_JOBS matches allocated CPUs
    export N_JOBS_EXT=${params.get('n_jobs') ?: task.cpus}

    echo "[${task.tag}] cloning git repo..."
    ${gitCloneFunction}
    clone_repo "${meta.sort_repo}" "${meta.sort_commit}"

    echo "[${task.tag}] running capsule..."
    cd capsule/code
    chmod +x run
    ./run

    echo "[${task.tag}] completed!"
    """
}

process hybrid_evaluation {
    tag 'hybrid-evaluation'
    def container_name = "ghcr.io/allenneuraldynamics/aind-ephys-pipeline-base:${params.container_tag}"
    container container_name

    publishDir "$RESULTS_PATH", saveAs: { filename -> new File(filename).getName() }

    input:
    val max_duration_minutes
    path ecephys_session_input, stageAs: 'capsule/data/ecephys_session'
    path hybrid_flattened, stageAs: 'capsule/data/*'
    val sorting_cases                                                       // one case name per staged file below
    path sorting_results, stageAs: 'capsule/data/sorting_inputs/in*/*'      // in1, in2, ... in list order
    path params_file, stageAs: 'capsule/params.json'

    output:
    path 'capsule/results/*', emit: results

    script:
    """
    #!/usr/bin/env bash
    set -e

    ${extra_installs_echo}
    ${extra_installs_cmd}

    export CODE_REPO="${versions['HYBRID_EVALUATION_REPO']}"
    export CODE_VERSION="${versions['HYBRID_EVALUATION_VERSION']}"

    mkdir -p capsule
    mkdir -p capsule/data
    mkdir -p capsule/results
    mkdir -p capsule/scratch

    if [[ ${params.executor} == "slurm" ]]; then
        echo "[${task.tag}] allocated task time: ${task.time}"
    fi
    # Make sure N_JOBS matches allocated CPUs
    export N_JOBS_EXT=${params.get('n_jobs') ?: task.cpus}

    # the evaluation expects one folder per sorting case: capsule/data/<case>/spikesorted_*
    echo "[${task.tag}] staging sorting cases..."
    i=1
    for sorting_case in ${sorting_cases.join(' ')}; do
        mkdir -p capsule/data/\$sorting_case
        mv capsule/data/sorting_inputs/in\$i/* capsule/data/\$sorting_case/
        i=\$((i + 1))
    done
    rm -rf capsule/data/sorting_inputs
    # the evaluation finds the GT sortings in data/, and the hybrid recordings refer to them as ../scratch/gt_<id>
    for gt_folder in capsule/data/gt_*; do if [ -d "\$gt_folder" ]; then ln -s "\$(realpath "\$gt_folder")" capsule/scratch/; fi; done

    echo "[${task.tag}] cloning git repo..."
    ${gitCloneFunction}
    clone_repo "${versions['HYBRID_EVALUATION_REPO']}" "${versions['HYBRID_EVALUATION_VERSION']}"

    echo "[${task.tag}] running capsule..."
    cd capsule/code
    chmod +x run
    ./run

    echo "[${task.tag}] completed!"
    """
}

// Provenance: record pipeline version, repos + commits and effective parameters
process save_provenance {
    tag 'provenance'
    def container_name = "ghcr.io/allenneuraldynamics/aind-ephys-pipeline-base:${params.container_tag}"
    container container_name
    publishDir "$RESULTS_PATH", mode: 'copy'

    input:
    val provenance_json

    output:
    path 'provenance.json'

    script:
    """
    #!/usr/bin/env bash
    set -e

    cat > provenance.json <<'PROVENANCE_EOF'
${groovy.json.JsonOutput.prettyPrint(provenance_json)}
PROVENANCE_EOF
    """
}

workflow {
    full_params_ch = Channel.value(file(full_params_file.toString()))
    if (stage_input) {
        ecephys_ch = Channel.fromPath(params.ecephys_path + "/", type: 'any')
    } else {
        // the data is read from job_dispatch.s3_path: stage a placeholder in place of the session
        def placeholder = file("${workDir}/no_session/NO_SESSION.txt")
        if (!placeholder.exists()) { placeholder.parent.mkdirs(); placeholder.text = 'Data is read from job_dispatch.s3_path\n' }
        ecephys_ch = Channel.fromPath(placeholder.parent.toString() + "/", type: 'any')
    }

    // Provenance: dispatch/generation/evaluation pins, plus each sorting case's resolved steps
    def used_steps = (existing ? ['job_dispatch_hybrid'] : ['job_dispatch', 'hybrid_generation']) + ['hybrid_evaluation']
    def provenance = [
        pipeline_url: pipelineUrl,
        pipeline_version: pipelineVersion,
        container_tag: params.container_tag,
        extra_installs: params.extra_installs,
        benchmark: benchmark,
        existing: existing,
        command_line: workflow.commandLine,
        steps: used_steps.collectEntries { step ->
            def keys = step_version_keys[step]
            [(step): [repo: versions[keys[0]], commit: versions[keys[1]]]]
        },
        sorting_cases: resolved_cases,
        parameters: [
            params_file: params.params_file ?: 'default_params.json',
            params_file_content: json_params,
            effective_params: full_params
        ]
    ]
    save_provenance(groovy.json.JsonOutput.toJson(provenance))

    // Hybrid recordings: generated, or listed from existing hybrid datasets
    if (existing) {
        dispatch_out = job_dispatch_hybrid(ecephys_ch.collect(), full_params_ch)
        max_duration_minutes = dispatch_out.max_duration_file.map { it.text.trim() }
        hybrid_recordings = dispatch_out.recordings
        hybrid_flattened = dispatch_out.flattened
    } else {
        job_dispatch_out = job_dispatch(ecephys_ch.collect(), full_params_ch)
        max_duration_minutes = job_dispatch_out.max_duration_file.map { it.text.trim() }
        job_jsons = job_dispatch_out.results.flatten().filter { it.name.startsWith('job') && it.name.endsWith('.json') }
        generation_out = hybrid_generation(max_duration_minutes, job_jsons, ecephys_ch.collect(), full_params_ch)
        hybrid_recordings = generation_out.recordings
        hybrid_flattened = generation_out.flattened
    }
    max_duration_minutes.view { "Max recording duration: ${it}min" }

    // [meta, files]: a job file plus, for generated recordings, the gt_<id> GT sorting folder the hybrid recording
    // refers to (they are staged together). The id comes from the file names because generated jobs are pickles
    streams = hybrid_recordings
        .flatMap { files ->
            (files instanceof List ? files : [files])
                .findAll { it.name.startsWith('job_') || it.name.startsWith('gt_') }
                .groupBy { it.name.replaceFirst(/^(job|gt)_/, '').replaceFirst(/\.(json|pkl|pickle)$/, '') }
                .collect { id, id_files -> [[id: id], id_files] }
        }

    // One item per stream and variant (shared compression + preprocessing), with the variant's params file
    stream_variants = streams
        .combine(Channel.fromList(variant_metas.values().toList()))
        .map { meta, job, vmeta -> [meta + vmeta, job, file(variant_files[vmeta.variant])] }
    compress_out = compress_wavpack(
        max_duration_minutes,
        stream_variants.filter { meta, job, pfile -> meta.compress },
        ecephys_ch.collect()
    )
    preprocessing_in = stream_variants
        .filter { meta, job, pfile -> !meta.compress }
        .mix(compress_out.results.map { meta, files -> [meta, files, file(variant_files[meta.variant])] })

    preprocessing_out = preprocessing(
        max_duration_minutes,
        preprocessing_in,
        ecephys_ch.collect()
    )

    // Streams whose preprocessing wrote error.txt: don't launch sorting for them
    def isFailed = { files -> files.any { p -> p.name.startsWith('preprocessed_') && p.resolve('error.txt').exists() } }
    preprocessing_ok = preprocessing_out.results.filter { meta, files -> !isFailed(files) }
    preprocessing_out.results
        .filter { meta, files -> isFailed(files) }
        .view { meta, files -> "Recording skipped after preprocessing: ${meta.id} (variant ${meta.variant})" }

    // Fan each preprocessed stream out to the cases of its variant, with the case's params file
    sorting_in = preprocessing_ok
        .map { meta, files -> [meta.variant, meta, files] }
        .combine(Channel.fromList(case_list.collect { key, cmeta, pfile -> [key, cmeta, file(pfile)] }), by: 0)
        .map { key, meta, files, cmeta, pfile -> [meta + cmeta, files, pfile] }

    // Spike sorting: each sorter process runs at most once, on the items of all cases using it
    def forSorter = { s -> sorting_in.filter { meta, files, pfile -> meta.sorter == s } }
    def byCase = { meta, files -> [meta.case, files] }
    sorted = Channel.empty()
    if ('kilosort4' in used_sorters) {
        sorted = sorted.mix(spikesort_kilosort4(max_duration_minutes, forSorter('kilosort4')).results.map(byCase))
    }
    if ('kilosort25' in used_sorters) {
        sorted = sorted.mix(spikesort_kilosort25(max_duration_minutes, forSorter('kilosort25')).results.map(byCase))
    }
    if ('spykingcircus2' in used_sorters) {
        sorted = sorted.mix(spikesort_spykingcircus2(max_duration_minutes, forSorter('spykingcircus2')).results.map(byCase))
    }
    if ('lupin' in used_sorters) {
        sorted = sorted.mix(spikesort_lupin(max_duration_minutes, forSorter('lupin')).results.map(byCase))
    }
    if ('dartsort' in used_sorters) {
        sorted = sorted.mix(spikesort_dartsort(max_duration_minutes, forSorter('dartsort')).results.map(byCase))
    }

    // Evaluation: one (case, file) pair per sorting output file, staged as real inputs (works on AWS Batch)
    sorting_pairs = sorted
        .flatMap { sorting_case, files -> (files instanceof List ? files : [files]).collect { [sorting_case, it] } }
        .toList()
    hybrid_evaluation(
        max_duration_minutes,
        ecephys_ch.collect(),
        hybrid_flattened.flatten().collect(),
        sorting_pairs.map { pairs -> pairs.collect { it[0] } },
        sorting_pairs.map { pairs -> pairs.collect { it[1] } },
        full_params_ch
    )
}
