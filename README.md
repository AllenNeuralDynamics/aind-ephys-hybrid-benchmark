# AIND Ephys Hybrid Benhmark
## aind-ephys-hybrid-benchmark

Hybrid benchmark pipeline with [SpikeInterface](https://github.com/SpikeInterface/spikeinterface).

The pipeline is based on [Nextflow](https://www.nextflow.io/) and it includes the following common steps:

- [job-dispatch](https://github.com/AllenNeuralDynamics/aind-ephys-job-dispatch/): generates a list of JSON files to be processed in parallel. Parallelization is performed over multiple probes and multiple shanks (e.g., for NP2-4shank probes). The steps from `hybrid-generation` to `spike-sorting` are run in parallel.
- [hybrid-generation](https://github.com/AllenNeuralDynamics/aind-ephys-hybrid-generationh/): generate hybrid recordings for each input JSON file
- [preprocessing](https://github.com/AllenNeuralDynamics/aind-ephys-preprocessing/): phase_shift, highpass filter, denoising (bad channel removal + common median reference ("cmr") or highpass spatial filter - "destripe"), and motion estimation (optionally correction)

- [hybrid-evaluation](https://github.com/AllenNeuralDynamics/aind-ephys-hybrid-evaluation/): collect and evaluate results

The steps between the generation and evaluation are are the *spike sorting cases*. The repo currently implements to sample applications, that can be easily extended.

### Application 1: spike sorters comparison

The *spike sorting cases* include:
- [preprocessing](https://github.com/AllenNeuralDynamics/aind-ephys-preprocessing/)
- spike sorting: several spike sorters are tested:
  - [kilosort2.5](https://github.com/AllenNeuralDynamics/aind-ephys-spikesort-kilosort25/)
  - [kilosort4](https://github.com/AllenNeuralDynamics/aind-ephys-spikesort-kilosort4/)
  - [spykingcircus2](https://github.com/AllenNeuralDynamics/aind-ephys-spikesort-spykingcircus2/)

### Application 2: lossy compression

The *spike sorting cases* include:
- [wavpack compression](https://github.com/AllenNeuralDynamics/aind-ephys-compress/): includes lossless and lossy compression using [WavPack](https://wavpack.com/) with multiple compression levels (bit per samples - BPS)
- [preprocessing](https://github.com/AllenNeuralDynamics/aind-ephys-preprocessing/)
- spike sorting: using one of the following spike sorters:
  - [kilosort2.5](https://github.com/AllenNeuralDynamics/aind-ephys-spikesort-kilosort25/)
  - [kilosort4](https://github.com/AllenNeuralDynamics/aind-ephys-spikesort-kilosort4/)
  - [spykingcircus2](https://github.com/AllenNeuralDynamics/aind-ephys-spikesort-spykingcircus2/)


# Input

Currently, the pipeline supports the following input data types:

- `spikeglx`: the input folder should contain SpikeGLX folders. It is recommended to add a `subject.json` and a `data_description.json` following the [aind-data-schema](https://aind-data-schema.readthedocs.io/en/latest/) specification, since these metadata are propagated to the NWB files.
- `openephys`: the input folder should contain Open Ephys folders. It is recommended to add a `subject.json` and a `data_description.json` following the [aind-data-schema](https://aind-data-schema.readthedocs.io/en/latest/) specification, since these metadata are propagated to the NWB files.
- `nwb`: the input folder should contain a NWB files (both HDF5 and Zarr backend are supported).
- `spikeinterface`: 
- `aind`: data ingestion used at AIND. The input folder must AIND ecephys sessions with an `ecephys` subfolder which in turn includes an `ecephys_clipped` (clipped Open Ephys folder) and an `ecephys_compressed` (compressed traces with Zarr). In addition, JSON file following the [aind-data-schema](https://aind-data-schema.readthedocs.io/en/latest/) are parsed to create processing and NWB metadata.

By default, the `--multi-session` option of the `job_dispatch` process is activated, so that
multiple sessions can be processed in one run.

# Output

The `results` folder includes per-session evaluations and plots and an `aggregated` folder with the performance across all sessions.



# Parameters

## Global parameters

In Nextflow, the The `-resume` argument enables the caching mechanism.

The following global parameters can be passed to the pipeline:

For the `spike sorter comparison` pipeline:
```bash
--sorters     Combination of sorters to run, separated by a + (e.g., "kilosort4+spykingcircus2")
```

For the `lossy compression` pipeline:
```bash
--sorter      Which sorter to run after compression (e.g. "kilosort4")
```

## Process-specific parameters

Some steps of the pipeline accept additional parameters, that can be passed as follows:

```bash
--{step_name}_args "{args}"
```

The steps that accept additional arguments are:

### `job_dispatch_args`:

```bash
    --concatenate             # Whether to concatenate recordings (segments) or not. Default: False
    --no-split-groups         # Whether to process different groups separately. Default: split groups
    --debug                   # Whether to run in DEBUG mode. Default: False
    --debug-duration DURATION # Duration of clipped recording in debug mode. Only used if debug is enabled. Default: 30 seconds
    --skip-timestamps-check   # Skip timestamps check. Default: False
    --input {aind,spikeglx,openephys,nwb,spikeinterface}
                              # Which 'loader' to use (aind | spikeglx | openephys | nwb | spikeinterface)
    --spikeinterface-info SPIKEINTERFACE_INFO
                              # A JSON path or string to specify how to parse the recording in spikeinterface, including: 
                                - 1. reader_type (required): string with the reader type (e.g. 'plexon', 'neuralynx', 'intan' etc.).
                                - 2. reader_kwargs (optional): dictionary with the reader kwargs (e.g. {'folder': '/path/to/folder'}).
                                - 3. keep_stream_substrings (optional): string or list of strings with the stream names to load (e.g. 'AP' or ['AP', 'LFP']).
                                - 4. skip_stream_substrings (optional): string (or list of strings) with substrings used to skip streams (e.g. 'NIDQ' or ['USB', 'EVENTS']).
                                - 5. probe_paths (optional): string or dict the probe paths to a ProbeInterface JSON file (e.g. '/path/to/probe.json'). If a dict is provided, the key is the stream name and the value is the probe path. If reader_kwargs is not provided, the reader will be created with default parameters. The probe_path is required if the reader doesn't load the probe automatically.
```

### `hybrid_generation_args`

```bash
  --min-amp MIN_AMP     Minimum amplitude to scale injected templates
  --max-amp MAX_AMP     Maximum amplitude to scale injected templates
  --min-depth-percentile MIN_DEPTH_PERCENTILE
                        Percentile of depths used as minimum depth
  --max-depth-percentile MAX_DEPTH_PERCENTILE
                        Percentile of depths used as maximum depth
  --num-units NUM_UNITS
                        Number of hybrid units for each case
  --num-cases NUM_CASES
                        Number of cases for each recording
  --skip-correct-motion
                        Whether to skip motion correction.

```

### `preprocessing_args`:

```bash
  --denoising {cmr,destripe}
                        Which denoising strategy to use. Can be 'cmr' or 'destripe'
  --filter-type {highpass,bandpass}
                        Which filter to use. Can be 'highpass' or 'bandpass'
  --no-remove-out-channels
                        Whether to remove out channels
  --no-remove-bad-channels
                        Whether to remove bad channels
  --max-bad-channel-fraction MAX_BAD_CHANNEL_FRACTION
                        Maximum fraction of bad channels to remove. If more than this fraction, processing is skipped
  --motion {skip,compute,apply}
                        How to deal with motion correction. Can be 'skip', 'compute', or 'apply'
  --motion-preset {dredge,dredge_fast,nonrigid_accurate,nonrigid_fast_and_accurate,rigid_fast,kilosort_like}
                        What motion preset to use. Supported presets are:
                        dredge, dredge_fast, nonrigid_accurate, nonrigid_fast_and_accurate, rigid_fast, kilosort_like.
  --t-start T_START     Start time of the recording in seconds (assumes recording starts at 0). 
                        This parameter is ignored in case of multi-segment or multi-block recordings.
                        Default is None (start of recording)
  --t-stop T_STOP       Stop time of the recording in seconds (assumes recording starts at 0). 
                        This parameter is ignored in case of multi-segment or multi-block recordings.
                        Default is None (end of recording)
```


# Deployments

## Local

> [!WARNING]
> While the pipeline can be deployed locally on a workstation or a server, it is recommended to 
> deploy it on a SLURM cluster or on a batch processing system (e.g., AWS batch).
> When deploying locally, the most recource-intensive processes (preprocessing, spike sorting, postprocessing) 
> are not parallelized to avoid overloading the system.
> This is achieved by setting the `maxForks 1` directive in such processes.

### Requirements

To deploy locally, you need to install:

- `nextflow`
- `docker`

Please checkout the [Nextflow](https://www.nextflow.io/docs/latest/install.html) and [Docker](https://docs.docker.com/engine/install/) installation instructions.


### Run

Clone this repo (`git clone https://github.com/AllenNeuralDynamics/aind-ephys-hybrid-benchmark.git`) and go to the 
`pipeline` folder. You will find a `main_local.nf`. This nextflow script is accompanied by the 
`nextflow_local.config` and can run on local workstations/machines.

To invoke the pipeline you can run the following command:

```bash
NXF_VER=22.10.8 DATA_PATH=$PWD/../data RESULTS_PATH=$PWD/../results \
    nextflow -C nextflow_local.config -log $RESULTS_PATH/nextflow/nextflow.log \
    run main_sorters.nf (main_lossy.nf) \
    --n_jobs 8 -resume
```

The `DATA_PATH` specifies the folder where the input files are located. 
The `RESULT_PATH` points to the output folder, where the data will be saved.
The `--n_jobs` argument specifies the number of parallel jobs to run.

Additional parameters can be passed as described in the [Parameters](#parameters) section.


### Example run command

As an example, here is how to run the pipeline on SpikeGLX datasets in debug mode 
on a 120-second snippet to benchmark Kilosort4 and Spyking Circus2:

```bash
NXF_VER=22.10.8 DATA_PATH=path/to/data_spikeglx RESULTS_PATH=path/to/results_spikeglx \
    nextflow -C nextflow_local.config run main_sorters.nf --sorters "kilosort4+spykingcircus2" \
    --job_dispatch_args "--input spikeglx" --preprocessing_args "--debug --debug-duration 120"
    
```


## SLURM

To deploy on a SLURM cluster, you need to have access to a SLURM cluster and have the 
[Nextflow](https://www.nextflow.io/docs/latest/install.html) and Singularity/Apptainer installed. 
To use Figurl cloud visualizations, follow the same steps descrived in the 
[Local deployment - Requirements](#requirements) section and set the KACHERY environment variables.

Then, you can submit the pipeline to the cluster similarly to the Local deplyment, 
but wrapping the command into a script that can be launched with `sbatch`.

To avoid downloading the container images in the current location (usually the home folder),
you can set the `NXF_SINGULARITY_CACHEDIR` environment variable to a different location.

You can use the `slurm_submit.sh` script as a template to submit the pipeline to your cluster.
It is recommended to also make a copy of the `pipeline/nextflow_slurm.config` file and modify the `queue` parameter to match the partition you want to use on your cluster. In this example, we assume the copy is called 
`pipeline/nextflow_slurm_custom.config`.

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

NXF_VER=22.10.8 DATA_PATH=$DATA_PATH RESULTS_PATH=$RESULTS_PATH nextflow \
    -C $PIPELINE_PATH/pipeline/nextflow_slurm_custom.config \
    -log $RESULTS_PATH/nextflow/nextflow.log \
    run $PIPELINE_PATH/pipeline/main_sorters.nf \
    -work-dir $WORKDIR \
    --job_dispatch_args "--debug --debug-duration 120" \ # additional parameters
    -resume
```

> [!IMPORTANT]
> You should change the `--partition` parameter to match the partition you want to use on your cluster. 
> The same partition should be also indicated as the `queue` argument in the `pipeline/nextflow_slurm_custom.config` file!

Then, you can submit the script to the cluster with:

```bash
sbatch slurm_submit.sh
```
