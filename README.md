# bigbio/relink

[![Nextflow](https://img.shields.io/badge/nextflow%20DSL2-%E2%89%A523.04.0-23aa62.svg)](https://www.nextflow.io/)
[![run with docker](https://img.shields.io/badge/run%20with-docker-0db7ed?labelColor=000000&logo=docker)](https://www.docker.com/)
[![run with singularity](https://img.shields.io/badge/run%20with-singularity-1d355c.svg?labelColor=000000)](https://sylabs.io/docs/)

## Introduction

**bigbio/relink** is a bioinformatics pipeline for crosslinking mass spectrometry (XL-MS) data analysis. It processes mass spectrometry data through several stages including file conversion, linear search for mass recalibration, mass recalibration, crosslinking search, and FDR correction using the xiSEARCH/xiFDR suite.

The pipeline is built using [Nextflow](https://www.nextflow.io), a workflow tool to run tasks across multiple compute infrastructures in a very portable manner. It uses Docker/Singularity containers making installation trivial and results highly reproducible. The pipeline follows [nf-core](https://nf-co.re) guidelines.

## Pipeline Summary

1. **File Conversion** - Convert Thermo RAW files to MGF format using ThermoRawFileParser
2. **Linear Search** - Run xiSEARCH linear peptide search for mass error estimation
3. **Mass Recalibration** - Calculate and apply mass corrections to MS1 and MS2 spectra
4. **Crosslinking Search** - Run xiSEARCH crosslinking peptide search
5. **FDR Correction** - Apply xiFDR for false discovery rate estimation
6. **Reporting** - Generate MultiQC report with analysis summary

## Quick Start

1. Install [`Nextflow`](https://www.nextflow.io/docs/latest/getstarted.html#installation) (`>=23.04.0`)

2. Install any of [`Docker`](https://docs.docker.com/engine/installation/), [`Singularity`](https://www.sylabs.io/guides/3.0/user-guide/) (you can follow [this tutorial](https://singularity-tutorial.github.io/01-installation/)), [`Podman`](https://podman.io/), [`Shifter`](https://nersc.gitlab.io/development/shifter/how-to-use/) or [`Charliecloud`](https://hpc.github.io/charliecloud/) for full pipeline reproducibility

3. Download the pipeline and test it on a minimal dataset with a single command:

   ```bash
   nextflow run bigbio/relink -profile test,docker --outdir ./results
   ```

4. Start running your own analysis:

   ```bash
   nextflow run bigbio/relink \
       -profile docker \
       --input samplesheet.csv \
       --outdir ./results
   ```

## Input Samplesheet

The input samplesheet is a CSV file with the following columns:

```csv
sample,file,fasta,xi_linear_config,xi_crosslink_config
sample1,/path/to/sample1.raw,/path/to/database.fasta,/path/to/xi_linear.conf,/path/to/xi_crosslinking.conf
sample2,/path/to/sample2.raw,/path/to/database.fasta,/path/to/xi_linear.conf,/path/to/xi_crosslinking.conf
```

| Column | Description |
|--------|-------------|
| `sample` | Sample identifier (unique) |
| `file` | Path to RAW or MGF file |
| `fasta` | Path to FASTA database |
| `xi_linear_config` | Path to xiSEARCH linear configuration file |
| `xi_crosslink_config` | Path to xiSEARCH crosslinking configuration file |

## Parameters

### Input/Output Options

| Parameter | Description | Default |
|-----------|-------------|---------|
| `--input` | Path to input samplesheet CSV | Required |
| `--outdir` | Output directory for results | `./results` |

### Analysis Options

| Parameter | Description | Default |
|-----------|-------------|---------|
| `--do_recalibration` | Perform mass recalibration | `true` |
| `--do_crosslinking_search` | Perform crosslinking search | `true` |
| `--do_fdr` | Perform FDR correction | `true` |
| `--do_mass_error_plots` | Generate mass error plots | `false` |
| `--link_fdr` | Link-level FDR threshold (%) | `5` |

## Output

The pipeline outputs the following directories:

```
results/
├── mgf/                    # Converted MGF files
├── linear_search/          # Linear search results
├── recalibrated/           # Recalibrated MGF files
│   └── plots/              # Mass error plots (optional)
├── crosslinking_search/    # Crosslinking search results
├── fdr/                    # FDR-corrected results
├── multiqc/                # MultiQC report
└── pipeline_info/          # Pipeline execution info
```

## Software Used

- [ThermoRawFileParser](https://github.com/compomics/ThermoRawFileParser) - RAW file conversion
- [xiSEARCH](https://www.rappsilberlab.org/software/xisearch/) - Crosslinking peptide search
- [xiFDR](https://www.rappsilberlab.org/software/xifdr/) - FDR estimation
- [pyOpenMS](https://pyopenms.readthedocs.io/) - Mass spectrometry data processing
- [Polars](https://pola.rs/) - Data processing

## Citations

If you use bigbio/relink for your analysis, please cite:

> **xiSEARCH**: Mendes, M.L., et al. (2019). "An integrated workflow for crosslinking mass spectrometry." Molecular Systems Biology.

> **xiFDR**: Fischer, L., & Rappsilber, J. (2017). "Quirks of error estimation in cross-linking/mass spectrometry." Analytical Chemistry.

An extensive list of references for the tools used by the pipeline can be found in the [`CITATIONS.md`](CITATIONS.md) file.

## Contributing

We welcome contributions! Please see our [contribution guidelines](.github/CONTRIBUTING.md) for details.

## Support

For questions, issues, or feature requests, please open an issue on the [GitHub repository](https://github.com/bigbio/relink/issues).

## License

This pipeline is released under the [Apache 2.0 License](LICENSE).
