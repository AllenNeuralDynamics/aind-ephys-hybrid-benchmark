# AIND Ephys Hybrid Benchmark
## aind-ephys-hybrid-benchmark

Hybrid benchmark pipeline with [SpikeInterface](https://github.com/SpikeInterface/spikeinterface).

The pipeline is based on [Nextflow](https://www.nextflow.io/) and follows the same architecture as the
[aind-ephys-pipeline](https://github.com/AllenNeuralDynamics/aind-ephys-pipeline): a single `pipeline/main.nf`
runs on every backend, all parameters live in one JSON file validated against a schema, and each step clones its
repository at the commit pinned in `pipeline/process_versions.env`.

It includes the following common steps:

- [job-dispatch](https://github.com/AllenNeuralDynamics/aind-ephys-job-dispatch/): generates a list of JSON files to be processed in parallel. Parallelization is performed over multiple probes and multiple shanks (e.g., for NP2-4shank probes). The steps from `hybrid-generation` to `spike-sorting` are run in parallel.
- [hybrid-generation](https://github.com/AllenNeuralDynamics/aind-ephys-hybrid-generation/): generates hybrid recordings (injected ground-truth units) for each input JSON file
- [hybrid-job-dispatch](https://github.com/AllenNeuralDynamics/aind-ephys-hybrid-job-dispatch/): replaces `job-dispatch` + `hybrid-generation` when starting from existing hybrid datasets
- [preprocessing](https://github.com/AllenNeuralDynamics/aind-ephys-preprocessing/): phase_shift, highpass filter, denoising (bad channel removal + common median reference ("cmr") or highpass spatial filter - "destripe"), and motion estimation (optionally correction)
- [hybrid-evaluation](https://github.com/AllenNeuralDynamics/aind-ephys-hybrid-evaluation/): collects and evaluates the results

The steps between the generation and the evaluation are the *spike sorting cases*. The `benchmark` parameter selects one of two applications.

### `benchmark: sorters`: spike sorters comparison

The *spike sorting cases* are the sorters listed in `sorters`. Preprocessing runs once, then each sorter runs on all hybrid recordings:
- [kilosort2.5](https://github.com/AllenNeuralDynamics/aind-ephys-spikesort-kilosort25/) (`kilosort25`)
- [kilosort4](https://github.com/AllenNeuralDynamics/aind-ephys-spikesort-kilosort4/) (`kilosort4`)
- [spykingcircus2](https://github.com/AllenNeuralDynamics/aind-ephys-spikesort-spykingcircus2/) (`spykingcircus2`)
- [lupin](https://github.com/AllenNeuralDynamics/aind-ephys-spikesort-lupin/) (`lupin`)
- [dartsort](https://github.com/AllenNeuralDynamics/aind-ephys-spikesort-dartsort/) (`dartsort`)

### `benchmark: lossy`: lossy compression

The *spike sorting cases* are the `compression_cases`, each run with the same `sorter`:
- [wavpack compression](https://github.com/AllenNeuralDynamics/aind-ephys-compress/): lossy compression using [WavPack](https://wavpack.com/) with multiple compression levels (bits per sample - BPS). The `lossless` case skips this step.
- [preprocessing](https://github.com/AllenNeuralDynamics/aind-ephys-preprocessing/)
- spike sorting with `sorter` (any of the sorters above)


# Input

Currently, the pipeline supports the following input data types (`job_dispatch.input`):

- `spikeglx`: the input folder should contain SpikeGLX folders. It is recommended to add a `subject.json` and a `data_description.json` following the [aind-data-schema](https://aind-data-schema.readthedocs.io/en/latest/) specification.
- `openephys`: the input folder should contain Open Ephys folders. It is recommended to add a `subject.json` and a `data_description.json` following the [aind-data-schema](https://aind-data-schema.readthedocs.io/en/latest/) specification.
- `nwb`: the input folder should contain NWB files (both HDF5 and Zarr backend are supported).
- `spikeinterface`: the input is loaded with a SpikeInterface reader, configured with `job_dispatch.spikeinterface_info`.
- `aind`: data ingestion used at AIND. The input folder must contain AIND ecephys sessions with an `ecephys` subfolder which in turn includes an `ecephys_clipped` (clipped Open Ephys folder) and an `ecephys_compressed` (compressed traces with Zarr).

By default, `job_dispatch.multi_session` is `true`, so that multiple sessions can be processed in one run.

## Existing hybrid datasets

Alternatively, the pipeline can be run on existing hybrid recordings (`existing: true`, or `--existing`). You can download datasets from the [AIND Benchmark Data page](https://allenneuraldynamics.github.io/data.html#aind-benchmark-dataephys-hybrid-evaluation) and point the input to the folder containing them, organized as `<session>/<case>/{recording,sorting}.zarr`.
In this case, the `hybrid-job-dispatch` step lists the hybrid recordings to be evaluated.

If the input is an `s3://` URL (e.g. `s3://aind-benchmark-data/ephys-hybrid-evaluation/sorters/np1/`), the data is not staged:
the URL is passed to `job_dispatch.s3_path` and every step reads the recordings from S3. `job_dispatch.max_recordings` and `job_dispatch.seed`
randomly sub-sample the available recordings.

# Output

The `results` folder includes per-session evaluations and plots, an `aggregated` folder with the performance across all sessions,
and a `provenance.json` with the pipeline version, the repository and commit of every step and the effective parameters.


# Parameters

All parameters are in a single JSON file, by default [pipeline/default_params.json](pipeline/default_params.json).
It is validated against [pipeline/default_params_schema.json](pipeline/default_params_schema.json) before anything runs.
The merged parameters are written to `<workDir>/full_params.json` and staged into every step as `params.json`;
each step reads its own section.

| Key | Default | Description |
|-----|---------|-------------|
| `benchmark` | `sorters` | `sorters` (compare `sorters`) or `lossy` (compare `compression_cases` with `sorter`) |
| `existing` | `false` | Start from existing hybrid datasets instead of generating them |
| `sorters` | `["kilosort4", "spykingcircus2"]` | Sorters to compare (`benchmark: sorters`) |
| `sorter` | `kilosort4` | Sorter used after compression (`benchmark: lossy`) |
| `compression_cases` | `["lossless", 3, 2.5, 2.25]` | `lossless` or WavPack BPS values (`benchmark: lossy`) |
| `job_dispatch` | | Job dispatch (input type, debug mode, multi-session, ...) and, for existing datasets, `max_recordings`, `s3_path`, `seed` |
| `hybrid_generation` | | `min_amp`, `max_amp`, `min_depth_percentile`, `max_depth_percentile`, `num_units`, `num_cases`, `correct_motion` |
| `compression` | | `highpass` (and `bps`, set per task from `compression_cases`) |
| `preprocessing` | | Same as in the aind-ephys-pipeline |
| `spikesorting.<sorter>` | | Same as in the aind-ephys-pipeline |
| `hybrid_evaluation` | | `debug_cases`: only evaluate this many hybrid cases |
| `logging` | | Logging configuration (`logging` or `log-schema`) |

The schema describes every key. Parameters can be changed in three ways:

```bash
# 1. a custom params file
--params_file /path/to/my_params.json

# 2. CLI flags following the JSON layout (top-level keys are plain flags)
--benchmark lossy --sorter spykingcircus2 --compression_cases lossless,3
--sorters kilosort4,spykingcircus2 --existing
--hybrid_generation.num_cases=2 --preprocessing.motion_correction.compute=false

# 3. the same flags packed in one string (used on Code Ocean, where only App Panel params are forwarded)
--extra_params "--benchmark=lossy --hybrid_generation.num_cases=2"
```

Other global parameters:

```bash
--n_jobs              Number of parallel jobs (local deployment only, default: all CPUs)
--container_tag       Tag of the ghcr.io/allenneuraldynamics images (default: pipeline/pipeline_version.txt)
--extra_installs      Comma-separated pip packages installed before running each step
--<step>_repo / --<step>_version
                      Override the repository / commit of a step (e.g. --hybrid_generation_version <commit>)
```

A `pipeline/process_versions_custom.env`, if present, replaces `pipeline/process_versions.env`.

In Nextflow, the `-resume` argument enables the caching mechanism.


# Deployments

## Local

> [!WARNING]
> While the pipeline can be deployed locally on a workstation or a server, it is recommended to
> deploy it on a SLURM cluster or on a batch processing system (e.g., AWS batch).
> When deploying locally, the most resource-intensive processes (hybrid generation, compression, preprocessing, spike sorting)
> are not parallelized to avoid overloading the system.
> This is achieved by setting the `maxForks 1` directive in such processes.

### Requirements

To deploy locally, you need to install:

- `nextflow` (>= 25.10)
- `docker`

Please checkout the [Nextflow](https://www.nextflow.io/docs/latest/install.html) and [Docker](https://docs.docker.com/engine/install/) installation instructions.


### Run

Clone this repo (`git clone https://github.com/AllenNeuralDynamics/aind-ephys-hybrid-benchmark.git`).
The `pipeline/main.nf` script is accompanied by the `pipeline/nextflow_local.config` for local workstations/machines.

To invoke the pipeline you can run the following command (from a folder outside the repository, since Nextflow writes its
work and log files in the current folder):

```bash
NXF_SYNTAX_PARSER=v1 DATA_PATH=/path/to/data RESULTS_PATH=/path/to/results \
    nextflow -C /path/to/aind-ephys-hybrid-benchmark/pipeline/nextflow_local.config \
    run /path/to/aind-ephys-hybrid-benchmark/pipeline/main.nf \
    --n_jobs 8 -resume
```

The `DATA_PATH` specifies the folder where the input files are located (it can also be passed as `--ecephys_url`).
The `RESULTS_PATH` points to the output folder, where the data will be saved.
`NXF_SYNTAX_PARSER=v1` is needed with Nextflow >= 26.04, whose default strict parser rejects `main.nf`.

Additional parameters can be passed as described in the [Parameters](#parameters) section.


### Example run command

As an example, here is how to run the pipeline on SpikeGLX datasets in debug mode
on a 120-second snippet to benchmark Kilosort4 and Spyking Circus2:

```bash
NXF_SYNTAX_PARSER=v1 DATA_PATH=path/to/data_spikeglx RESULTS_PATH=path/to/results_spikeglx \
    nextflow -C /path/to/aind-ephys-hybrid-benchmark/pipeline/nextflow_local.config \
    run /path/to/aind-ephys-hybrid-benchmark/pipeline/main.nf \
    --sorters kilosort4,spykingcircus2 \
    --job_dispatch.input=spikeglx --job_dispatch.debug=true --job_dispatch.debug_duration=120
```

The `tests/` folder has ready-to-run examples for each benchmark on a small synthetic NWB dataset
(`tests/test_pipeline_sorters.sh`, `tests/test_pipeline_lossy.sh`, `tests/test_pipeline_existing.sh`).


## SLURM

To deploy on a SLURM cluster, you need to have access to a SLURM cluster and have
[Nextflow](https://www.nextflow.io/docs/latest/install.html) and Singularity/Apptainer installed.

Then, you can submit the pipeline to the cluster similarly to the Local deployment,
but wrapping the command into a script that can be launched with `sbatch`.

To avoid downloading the container images in the current location (usually the home folder),
you can set the `NXF_SINGULARITY_CACHEDIR` (or `NXF_APPTAINER_CACHEDIR`) environment variable to a different location.

You can use the `pipeline/slurm_submit.sh` script as a template to submit the pipeline to your cluster.
It is recommended to also make a copy of the `pipeline/nextflow_slurm.config` file and modify the `default_queue` parameter
to match the partition you want to use on your cluster. In this example, we assume the copy is called
`pipeline/nextflow_slurm_custom.config`, which `slurm_submit.sh` picks up automatically.

```bash
#!/bin/bash
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --mem=4GB
#SBATCH --time=2:00:00
### change {your-partition} to the partition/queue on your cluster
#SBATCH --partition={your-partition}


# modify this section to make the nextflow command available to your environment
# e.g., using a conda environment with nextflow installed
conda activate env_nf

PIPELINE_PATH="path-to-your-cloned-repo"
DATA_PATH="path-to-data-folder"
RESULTS_PATH="path-to-results-folder"
WORKDIR="path-to-large-workdir"

NXF_SYNTAX_PARSER=v1 DATA_PATH=$DATA_PATH RESULTS_PATH=$RESULTS_PATH nextflow \
    -C $PIPELINE_PATH/pipeline/nextflow_slurm_custom.config \
    -log $RESULTS_PATH/nextflow/nextflow.log \
    run $PIPELINE_PATH/pipeline/main.nf \
    -work-dir $WORKDIR \
    --job_dispatch.debug=true --job_dispatch.debug_duration=120 \
    -resume
```

> [!IMPORTANT]
> You should change the `--partition` parameter to match the partition you want to use on your cluster.
> The same partition should be also indicated as the `default_queue` argument in the `pipeline/nextflow_slurm_custom.config` file!

Then, you can submit the script to the cluster with:

```bash
sbatch slurm_submit.sh
```

## Code Ocean

On Code Ocean, `pipeline/nextflow.config` runs the pipeline on AWS Batch with `pipeline/params_co.json` as params file.
The App Panel can expose `benchmark`, `existing`, `sorters`, `sorter` and `extra_params`; any other parameter can be set
through `extra_params`.
