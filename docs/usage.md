# bigbio/relink: Usage

## Introduction

bigbio/relink is an nf-core compliant Nextflow pipeline for crosslinking mass spectrometry (XL-MS) data analysis using xiSEARCH and xiFDR.

## Samplesheet input

You will need to create a samplesheet with information about the samples you would like to analyse before running the pipeline. Use this parameter to specify its location. It has to be a comma-separated file with 5 columns, and a header row as shown in the examples below.

```bash
--input '[path to samplesheet file]'
```

### Full samplesheet

The samplesheet can have as many columns as you desire, however, there is a strict requirement for the first 5 columns to match those defined in the table below.

A final samplesheet file consisting of a single sample may look something like the one below:

```csv
sample,file,fasta,linear_config,crosslink_config
SAMPLE_1,/path/to/data/sample1.raw,/path/to/database.fasta,/path/to/linear.conf,/path/to/crosslink.conf
SAMPLE_2,/path/to/data/sample2.raw,/path/to/database.fasta,/path/to/linear.conf,/path/to/crosslink.conf
```

| Column             | Description                                                                                                   |
| ------------------ | ------------------------------------------------------------------------------------------------------------- |
| `sample`           | Custom sample name. This entry will be identical for multiple sequencing libraries/runs from the same sample. |
| `file`             | Full path to the RAW or MGF file.                                                                             |
| `fasta`            | Full path to the FASTA database file.                                                                         |
| `linear_config`    | Full path to the xiSEARCH configuration file for linear search.                                               |
| `crosslink_config` | Full path to the xiSEARCH configuration file for crosslinking search.                                         |

## Running the pipeline

The typical command for running the pipeline is as follows:

```bash
nextflow run bigbio/relink --input samplesheet.csv --outdir results -profile docker
```

This will launch the pipeline with the `docker` configuration profile. See below for more information about profiles.

Note that the pipeline will create the following files in your working directory:

```bash
work                # Directory containing the nextflow working files
<OUTDIR>            # Finished results in specified location (defined with --outdir)
.nextflow_log       # Log file from Nextflow
# Other nextflow hidden files, eg. history of pipeline runs and old logs.
```

### Updating the pipeline

When you run the above command, Nextflow automatically pulls the pipeline code from GitHub and stores it as a cached version. When running the pipeline after this, it will always use the cached version if available - even if the pipeline has been updated since. To make sure that you're running the latest version of the pipeline, make sure that you regularly update the cached version of the pipeline:

```bash
nextflow pull bigbio/relink
```

### Reproducibility

It is a good idea to specify a pipeline version when running the pipeline on your data. This ensures that a specific version of the pipeline code and software are used when you run your pipeline. If you keep using the same tag, you'll be running the same version of the pipeline, even if there have been changes to the code since.

First, go to the [bigbio/relink releases page](https://github.com/bigbio/relink/releases) and find the latest pipeline version - numeric only (eg. `1.0.0`). Then specify this when running the pipeline with `-r` (one hyphen) - eg. `-r 1.0.0`. Of course, you can switch to another version by changing the number after the `-r` flag.

## Core Nextflow arguments

> **NB:** These options are part of Nextflow and use a _single_ hyphen (pipeline parameters use a double-hyphen).

### `-profile`

Use this parameter to choose a configuration profile. Profiles can give configuration presets for different compute environments.

Several generic profiles are bundled with the pipeline which instruct the pipeline to use software packaged using different methods (Docker, Singularity, Conda) - see below.

> We highly recommend the use of Docker or Singularity containers for full pipeline reproducibility.

The pipeline also dynamically loads configurations from [https://github.com/nf-core/configs](https://github.com/nf-core/configs) when it runs, making multiple config profiles for various institutional clusters available at run time.

Note that multiple profiles can be loaded, for example: `-profile test,docker` - the order of arguments is important! They are loaded in sequence, so later profiles can overwrite earlier profiles.

If `-profile` is not specified, the pipeline will run locally and expect all software to be installed and available on the `PATH`. This is _not_ recommended.

- `docker`
  - A generic configuration profile to be used with [Docker](https://docker.com/)
- `singularity`
  - A generic configuration profile to be used with [Singularity](https://sylabs.io/docs/)
- `conda`
  - A generic configuration profile to be used with [Conda](https://conda.io/docs/)
- `test`
  - A profile with a complete configuration for automated testing
  - Includes links to test data so needs no other parameters

### `-resume`

Specify this when restarting a pipeline. Nextflow will use cached results from any pipeline steps where the inputs are the same, continuing from where it got to previously. For input to be considered the same, not only the names must be identical but the files' contents as well.

### `-c`

Specify the path to a specific config file (this is a core Nextflow command). See the [nf-core website documentation](https://nf-co.re/usage/configuration) for more information.
