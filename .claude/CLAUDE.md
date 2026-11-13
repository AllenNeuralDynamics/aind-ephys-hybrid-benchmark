# AIND Ephys Hybrid Benchmark

## Project Overview

A Nextflow pipeline that benchmarks spike sorting on **hybrid recordings**: ground-truth units injected into real recordings.
It has two applications, selected by `benchmark` in the params file:
- `sorters`: compares several spike sorters.
- `lossy`: compares WavPack compression levels with a single sorter.

It follows the architecture of the sibling `aind-ephys-pipeline` (`../aind-ephys-pipeline`, see its `.claude/CLAUDE.md`). It reuses that pipeline's step repos (job-dispatch, preprocessing, sorters) and its container images.

## Architecture

A single Nextflow **DSL2** pipeline (`pipeline/main.nf`) runs on every backend. Only the config changes:

| Backend | Config | Executor |
|---|---|---|
| Code Ocean | `nextflow.config` (+ `params_co.json`) | `awsbatch` |
| SLURM | `nextflow_slurm.config` (+ `slurm_submit.sh`) | `slurm`, Apptainer/Singularity |
| Local | `nextflow_local.config` | `local`, Docker |

- **Step code:** each process clones its step repo from **public GitHub** at the commit pinned in `pipeline/process_versions.env`. If `process_versions_custom.env` exists, it takes priority. Override per step with `--<step>_repo` / `--<step>_version`.
- **Containers:** `ghcr.io/allenneuraldynamics/aind-ephys-pipeline-{base,spikesort-kilosort4,spikesort-kilosort25,spikesort-dartsort}:<tag>`, built in aind-ephys-pipeline's `environment/`. The tag comes from `--container_tag`, then the `CONTAINER_TAG` env var, then `pipeline/pipeline_version.txt`.
- **Nextflow:** needs >= 25.10 (the `nf-schema@2.7.3` plugin).

## Pipeline Steps

Step repos are in `../../pipeline-steps/hybrid/` (hybrid steps, compress) and `../../pipeline-steps/ephys/` (job-dispatch, preprocessing, `spikesorting/*`).

| Process | Repo | Runs | params.json section |
|---|---|---|---|
| `job_dispatch` | aind-ephys-job-dispatch | once (not `existing`) | `job_dispatch` |
| `hybrid_generation` | aind-ephys-hybrid-generation | per job JSON. Writes `recordings/job_<case>.pkl` and `flattened/` (gt, analyzers, figures) | `hybrid_generation` |
| `job_dispatch_hybrid` | aind-ephys-hybrid-job-dispatch | once (`existing`). Replaces the two steps above | `job_dispatch` (`max_recordings`, `s3_path`, `seed`) |
| `compress_wavpack` | aind-ephys-compress | per recording × compression level (`lossy`). `COMPRESSION_BPS` env var = `meta.bps` | `compression` |
| `preprocessing` | aind-ephys-preprocessing | per recording (× case in `lossy`) | `preprocessing` |
| `spikesort_<sorter>` | aind-ephys-spikesort-* | each sorter process at most once per run | `spikesorting.<sorter>` |
| `hybrid_evaluation` | aind-ephys-hybrid-evaluation | once. Publishes to `RESULTS_PATH` | `hybrid_evaluation` |
| `save_provenance` | (inline) | once. Writes `provenance.json` | – |

- **Channels:** they carry `[meta, files]`. `meta.id` is the job file name without `job_` and the extension, because generated jobs are pickles. In lossy mode, `meta.case` is `lossless` or `wv-<bps>` and `meta.bps` is the bps value.
- **Sorting case:** it's the sorter name (sorters mode) or `meta.case` (lossy mode). Evaluation gets `(case, file)` pairs staged as `capsule/data/sorting_inputs/in<i>/*` (real inputs, so it works on AWS Batch). It then moves them into `capsule/data/<case>/`, the layout `hybrid-evaluation` expects.
- **Existing datasets on S3:** with `existing` and an `s3://` input, `main.nf` sets `job_dispatch.s3_path` and stages a `no_session` placeholder instead of the data.

## Configuration

- **Params file:** `pipeline/default_params.json`, validated against `default_params_schema.json` before anything runs and again after all merges.
  - `logging`, `job_dispatch`, `preprocessing` and `spikesorting` are **copies** of aind-ephys-pipeline's sections. Re-sync them by hand when upstream changes. The hybrid-only keys are `benchmark`, `existing`, `sorters`, `sorter`, `compression_cases`, `hybrid_generation`, `compression`, `hybrid_evaluation` and `job_dispatch.{max_recordings,s3_path,seed}`.
- **Overrides:**
  - dotted CLI flags (`--hybrid_generation.num_cases=2`)
  - top-level plain flags (`--benchmark lossy`, `--existing`, `--sorters kilosort4,spykingcircus2`)
  - `--extra_params "<flags>"` (Code Ocean)
  - There are no legacy `*_args` strings.
- **Merged result:** written to `${workDir}/full_params.json`, then staged as `capsule/params.json`.

## Running Nextflow (Claude)

- Never launch Nextflow from inside the repo: it writes `.nextflow/`, `work/` and logs into the launch folder. `cd "$(mktemp -d)"` (or the session scratchpad) and call scripts by absolute path, e.g. `cd "$(mktemp -d)" && bash <repo>/tests/test_pipeline_sorters.sh`.
- Use `NXF_SYNTAX_PARSER=v1`; the strict parser rejects `main.nf`.
- Quick check: `nextflow -C <repo>/pipeline/nextflow_local.config run <repo>/pipeline/main.nf -preview --params_file <repo>/pipeline/default_params.json`.
- Tests: `tests/test_pipeline_{sorters,lossy,existing}.sh` (NWB sample or generated zarrs, spykingcircus2, CPU only). CI (`.github/workflows/test_pipeline.yml`) installs `.github/workflows/nextflow_test.config` as `pipeline/nextflow_local_custom.config`.

## Development Workflow

1. Change and test the step repo.
2. Bump its commit in `pipeline/process_versions.env`, or use `process_versions_custom.env` / `--<step>_version` for a trial.
3. If a step needs new keys, add them to `default_params.json` **and** the schema (`additionalProperties: false`).
4. Run the tests in `tests/`.
