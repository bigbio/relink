# Scout Integration & SDRF Input Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Scout as a switchable search engine alongside xiSEARCH, add SDRF input support, standardize on mzML, and output mzIdentML 1.3.

**Architecture:** The pipeline branches on `params.search_engine` ('xisearch'|'scout'). Both paths share THERMORAWFILEPARSER (RAW->mzML). xiSEARCH path: linear search -> recalibration -> crosslink search -> xiFDR. Scout path: SCOUT_SEARCH (-no_filter, per sample) -> SCOUT_FILTER (aggregate FDR). Both converge at MZIDENTML_EXPORT. Input is SDRF, parsed by sdrf-pipelines `convert-relink` and translated to engine-specific configs by a Python helper.

**Tech Stack:** Nextflow DSL2, Python 3.12 (pyopenms, polars, click), Java 21 (xiSEARCH/xiFDR), .NET 9.0 (Scout), Docker

**Repos involved:**
- `bigbio/relink` — main pipeline (primary)
- `sdrf-pipelines` — new `convert-relink` converter
- `bigbio/proteomics-sample-metadata` — validate PXD042173 SDRF
- `quantms-containers` — update relink container (Scout 2.0 -> 2.1)

---

### Task 1: Update Container — Scout 2.0.0 -> 2.1

**Repo:** `quantms-containers` (at `/Users/yperez/work/quantms-workspace/quantms-containers/`)
**Files:**
- Modify: `relink-1.0.0/Dockerfile:36-42`

This unblocks Scout `-no_filter` support. Everything else depends on this.

- [ ] **Step 1: Update Scout download URL in Dockerfile**

In `relink-1.0.0/Dockerfile`, change lines 35-42:

```dockerfile
# Install Scout 2.1
RUN mkdir -p /opt/scout && wget -q \
    https://github.com/diogobor/Scout/releases/download/2.1/Scout_Linux64.zip \
    -O /tmp/Scout.zip && \
    unzip /tmp/Scout.zip -d /opt/scout && \
    rm /tmp/Scout.zip && \
    mv /opt/scout/Scout_Linux64/* /opt/scout && \
    rmdir /opt/scout/Scout_Linux64
```

Note: Verify the exact release URL exists at https://github.com/diogobor/Scout/releases. If the tag is `v2.1` instead of `2.1`, adjust accordingly. If 2.1 is not released yet, file an issue to Diogo and use 2.0.0 with a TODO.

- [ ] **Step 2: Add xi-mzidentml-converter to container**

Add after the Python pip install block (after line 95):

```dockerfile
# Install xi-mzidentml-converter for mzIdentML export
RUN pip install --no-cache-dir xi-mzidentml-converter
```

- [ ] **Step 3: Update container label**

Change line 7:

```dockerfile
LABEL software.version="1.1.0"
```

And update line 8 to mention Scout 2.1:

```dockerfile
LABEL about.summary="Container for relink pipeline: xiSEARCH 1.8.11, xiFDR 2.3.10, Scout 2.1, xi-mzidentml-converter, and dependencies for crosslinking mass spectrometry analysis"
```

- [ ] **Step 4: Build and verify locally**

```bash
cd /Users/yperez/work/quantms-workspace/quantms-containers/relink-1.0.0
docker build -t ghcr.io/bigbio/relink:1.1.0 .
docker run --rm ghcr.io/bigbio/relink:1.1.0 dotnet /opt/scout/Scout_Unix.dll --help
docker run --rm ghcr.io/bigbio/relink:1.1.0 python -c "import xi_mzidentml_converter; print('ok')"
```

Expected: Scout 2.1 help output and successful Python import.

- [ ] **Step 5: Commit**

```bash
git add relink-1.0.0/Dockerfile
git commit -m "feat: update relink container to Scout 2.1 + xi-mzidentml-converter"
```

---

### Task 2: Switch ThermoRawFileParser from MGF to mzML

**Repo:** `bigbio/relink`
**Files:**
- Modify: `conf/modules.config:26-33`
- Modify: `workflows/relink.nf:42-43,65-66`

- [ ] **Step 1: Change ThermoRawFileParser output format to mzML**

In `conf/modules.config`, change lines 26-33:

```groovy
    withName: 'THERMORAWFILEPARSER' {
        ext.args = '-f=2'  // Output indexed mzML format
        publishDir = [
            path: { "${params.outdir}/mzml" },
            mode: params.publish_dir_mode,
            pattern: "*.mzML"
        ]
    }
```

- [ ] **Step 2: Update branch logic in relink.nf to handle mzML**

In `workflows/relink.nf`, change lines 41-45:

```groovy
        .branch {
            raw: it[1].name.toLowerCase().endsWith('.raw')
            mzml: it[1].name.toLowerCase().endsWith('.mzml')
        }
        .set { ch_input_by_type }
```

And lines 64-66:

```groovy
    // Combine converted mzML with input mzML files
    ch_mzml = THERMORAWFILEPARSER.out.convert_files
        .mix(ch_input_by_type.mzml)
```

- [ ] **Step 3: Update all downstream references from ch_mgf to ch_mzml**

In `workflows/relink.nf`, replace all `ch_mgf` with `ch_mzml` (lines 66, 78, 92, 103, 106):

Line 78: `XISEARCH_LINEAR ( ch_mzml, ... )`
Line 92: `.join(ch_mzml)`
Line 103: `ch_mzml_for_crosslink = MASS_RECALIBRATION.out.mzml`
Line 106: `ch_mzml_for_crosslink = ch_mzml`

- [ ] **Step 4: Commit**

```bash
git add conf/modules.config workflows/relink.nf
git commit -m "feat: switch spectral format from MGF to mzML"
```

---

### Task 3: Adapt xiSEARCH Module for mzML Input

**Repo:** `bigbio/relink`
**Files:**
- Modify: `modules/local/xisearch/main.nf:12,34`
- Modify: `modules/local/xisearch/meta.yml:23-26`

- [ ] **Step 1: Update xiSEARCH module input variable names**

In `modules/local/xisearch/main.nf`, change line 12:

```groovy
    tuple val(meta), path(spectra_file)
```

And line 34:

```groovy
        --peaks='${spectra_file}' \\
```

- [ ] **Step 2: Update meta.yml**

In `modules/local/xisearch/meta.yml`, update the input description to reference mzML instead of MGF.

- [ ] **Step 3: Commit**

```bash
git add modules/local/xisearch/main.nf modules/local/xisearch/meta.yml
git commit -m "refactor: xiSEARCH module accepts mzML input"
```

---

### Task 4: Adapt Mass Recalibration for mzML

**Repo:** `bigbio/relink`
**Files:**
- Modify: `bin/recalibrate_mgf.py` (rename to `bin/recalibrate_spectra.py`)
- Modify: `modules/local/mass_recalibration/main.nf:11,15,28-33`

The recalibration script currently reads/writes MGF using pyopenms. It needs to read/write mzML instead. The recalibration logic (mass error calculation) is format-agnostic — only the I/O changes.

- [ ] **Step 1: Rename the script**

```bash
cd /Users/yperez/work/relink
git mv bin/recalibrate_mgf.py bin/recalibrate_spectra.py
```

- [ ] **Step 2: Update recalibrate_spectra.py I/O to use mzML**

The script uses pyopenms for reading spectra. pyopenms supports mzML natively via `MSExperiment` and `MzMLFile`. Update the argparse arguments:

Change `--mgf` to `--spectra` and `--output` to produce `.mzML`:

```python
parser.add_argument('--spectra', required=True, help='Input mzML file')
parser.add_argument('--output', required=True, help='Output recalibrated mzML file')
```

Update the I/O functions to use `pyopenms.MzMLFile()` for reading/writing:

```python
from pyopenms import MzMLFile, MSExperiment

def load_spectra(path):
    exp = MSExperiment()
    MzMLFile().load(path, exp)
    return exp

def save_spectra(exp, path):
    MzMLFile().store(path, exp)
```

Keep all recalibration logic (mass error estimation, m/z correction) unchanged.

- [ ] **Step 3: Update mass_recalibration module**

In `modules/local/mass_recalibration/main.nf`:

Line 11 — change input:
```groovy
    tuple val(meta), path(linear_results), path(peaks_file), path(spectra_file)
```

Line 15 — change output:
```groovy
    tuple val(meta), path("recal_*.mzML"), emit: mzml
```

Lines 28-33 — update script:
```groovy
    python ${projectDir}/bin/recalibrate_spectra.py \\
        --linear-results '${linear_results}' \\
        --peaks '${peaks_file}' \\
        --spectra '${spectra_file}' \\
        --output 'recal_${prefix}.mzML' \\
        --error-report 'mass_error_${prefix}.csv' \\
        --prefix '${prefix}' \\
        ${plot_flag} \\
        ${args}
```

- [ ] **Step 4: Update modules.config for recalibrated output**

In `conf/modules.config`, update the MASS_RECALIBRATION publishDir (lines 52-70):

Change `pattern: "*.mgf"` to `pattern: "*.mzML"`.

- [ ] **Step 5: Commit**

```bash
git add bin/recalibrate_spectra.py modules/local/mass_recalibration/main.nf conf/modules.config
git commit -m "refactor: mass recalibration reads/writes mzML instead of MGF"
```

---

### Task 5: Remove FORMAT_CORRECTION Step

**Repo:** `bigbio/relink`
**Files:**
- Modify: `workflows/relink.nf:11,111-115`
- Note: Keep `modules/local/intensity_reformat/` and `bin/format_correction.py` in case anyone needs MGF support later, but remove from workflow.

- [ ] **Step 1: Remove FORMAT_CORRECTION from workflow**

In `workflows/relink.nf`:

Remove line 11 (the import):
```groovy
include { FORMAT_CORRECTION } from '../modules/local/intensity_reformat/main'
```

Remove lines 108-115 (the FORMAT_CORRECTION step) and replace with direct passthrough:

```groovy
    // mzML format does not need the MGF format correction step
    ch_mzml_for_crosslink_final = ch_mzml_for_crosslink
```

Update line 127 to use the new variable:
```groovy
        XISEARCH_CROSSLINK (
            ch_mzml_for_crosslink_final,
```

- [ ] **Step 2: Remove FORMAT_CORRECTION config from modules.config**

Remove the FORMAT_CORRECTION publishDir block if present (it's currently using the default).

- [ ] **Step 3: Commit**

```bash
git add workflows/relink.nf
git commit -m "refactor: remove FORMAT_CORRECTION step (not needed for mzML)"
```

---

### Task 6: Add Search Engine Parameter to nextflow.config

**Repo:** `bigbio/relink`
**Files:**
- Modify: `nextflow.config:10-27`

- [ ] **Step 1: Add search_engine and custom_search_config params**

In `nextflow.config`, add after line 20 (after `xi_crosslink_config`):

```groovy
    // Search engine selection
    search_engine              = 'xisearch'   // 'xisearch' or 'scout'
    custom_search_config       = null          // Optional: user-provided engine config override
```

- [ ] **Step 2: Commit**

```bash
git add nextflow.config
git commit -m "feat: add search_engine parameter for engine switching"
```

---

### Task 7: Create SCOUT_SEARCH Module

**Repo:** `bigbio/relink`
**Files:**
- Create: `modules/local/scout_search/main.nf`
- Create: `modules/local/scout_search/meta.yml`

- [ ] **Step 1: Create the SCOUT_SEARCH process**

Create `modules/local/scout_search/main.nf`:

```groovy
process SCOUT_SEARCH {
    tag "$meta.id"
    label 'process_high'
    label 'process_long'
    label 'error_retry'

    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'oras://ghcr.io/bigbio/relink-sif:1.1.0' :
        'ghcr.io/bigbio/relink:1.1.0' }"

    input:
    tuple val(meta), path(spectra_file)
    path search_params
    path filter_params
    path fasta

    output:
    tuple val(meta), path("*.buf"), emit: buf_files
    path "versions.yml",            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    """
    /opt/scout/run_scout.sh -search -no_filter \\
        ${search_params} ${filter_params} \\
        ${args}

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        scout: 2.1
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch '${prefix}.buf'

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        scout: 2.1
    END_VERSIONS
    """
}
```

- [ ] **Step 2: Create meta.yml**

Create `modules/local/scout_search/meta.yml`:

```yaml
name: scout_search
description: Run Scout crosslinking search per sample without FDR filtering
keywords:
  - proteomics
  - crosslinking
  - mass spectrometry
  - scout
tools:
  - scout:
      description: Proteome-scale crosslink identification
      homepage: https://github.com/diogobor/Scout
      documentation: https://github.com/diogobor/Scout
      licence: ['MIT']
input:
  - meta:
      type: map
      description: Sample metadata
  - spectra_file:
      type: file
      description: mzML or RAW file with MS/MS spectra
      pattern: "*.{mzML,raw}"
  - search_params:
      type: file
      description: Scout search parameters JSON
      pattern: "*.json"
  - filter_params:
      type: file
      description: Scout filter parameters JSON
      pattern: "*.json"
  - fasta:
      type: file
      description: Protein FASTA database
      pattern: "*.{fasta,fa}"
output:
  - buf_files:
      type: file
      description: Scout intermediate binary result files
      pattern: "*.buf"
  - versions:
      type: file
      description: Software versions
      pattern: "versions.yml"
```

- [ ] **Step 3: Commit**

```bash
git add modules/local/scout_search/
git commit -m "feat: add SCOUT_SEARCH module (per-sample search with -no_filter)"
```

---

### Task 8: Create SCOUT_FILTER Module

**Repo:** `bigbio/relink`
**Files:**
- Create: `modules/local/scout_filter/main.nf`
- Create: `modules/local/scout_filter/meta.yml`

- [ ] **Step 1: Create the SCOUT_FILTER process**

Create `modules/local/scout_filter/main.nf`:

```groovy
process SCOUT_FILTER {
    tag "scout_fdr"
    label 'process_high'
    label 'error_retry'

    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'oras://ghcr.io/bigbio/relink-sif:1.1.0' :
        'ghcr.io/bigbio/relink:1.1.0' }"

    input:
    path buf_files       // Collected from all samples
    path filter_params
    path fasta

    output:
    path "output/*.csv", emit: results
    path "versions.yml", emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    """
    mkdir -p output

    /opt/scout/run_scout.sh -filter \\
        ${filter_params} \\
        -fasta ${fasta} \\
        -i . \\
        -o output/ \\
        ${args}

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        scout: 2.1
    END_VERSIONS
    """

    stub:
    """
    mkdir -p output
    touch 'output/scout_fdr_results.csv'

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        scout: 2.1
    END_VERSIONS
    """
}
```

- [ ] **Step 2: Create meta.yml**

Create `modules/local/scout_filter/meta.yml`:

```yaml
name: scout_filter
description: Run Scout FDR filtering on collected results from all samples
keywords:
  - proteomics
  - crosslinking
  - fdr
  - scout
tools:
  - scout:
      description: Proteome-scale crosslink identification
      homepage: https://github.com/diogobor/Scout
      licence: ['MIT']
input:
  - buf_files:
      type: file
      description: Scout intermediate binary files collected from all samples
      pattern: "*.buf"
  - filter_params:
      type: file
      description: Scout filter parameters JSON
      pattern: "*.json"
  - fasta:
      type: file
      description: Protein FASTA database
      pattern: "*.{fasta,fa}"
output:
  - results:
      type: file
      description: FDR-filtered CSV results
      pattern: "output/*.csv"
  - versions:
      type: file
      description: Software versions
      pattern: "versions.yml"
```

- [ ] **Step 3: Commit**

```bash
git add modules/local/scout_filter/
git commit -m "feat: add SCOUT_FILTER module (aggregated FDR across all samples)"
```

---

### Task 9: Create MZIDENTML_EXPORT Module

**Repo:** `bigbio/relink`
**Files:**
- Create: `modules/local/mzidentml_export/main.nf`
- Create: `modules/local/mzidentml_export/meta.yml`

- [ ] **Step 1: Create the MZIDENTML_EXPORT process**

Create `modules/local/mzidentml_export/main.nf`:

```groovy
process MZIDENTML_EXPORT {
    tag "mzidentml_export"
    label 'process_medium'

    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'oras://ghcr.io/bigbio/relink-sif:1.1.0' :
        'ghcr.io/bigbio/relink:1.1.0' }"

    input:
    path fdr_results
    path fasta
    val search_engine

    output:
    path "*.mzid", emit: mzidentml
    path "versions.yml", emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    if (search_engine == 'xisearch')
        """
        xi-mzidentml-converter \\
            --csv ${fdr_results} \\
            --fasta ${fasta} \\
            --output results.mzid \\
            ${args}

        cat <<-END_VERSIONS > versions.yml
        "${task.process}":
            xi-mzidentml-converter: \$(pip show xi-mzidentml-converter 2>/dev/null | grep Version | cut -d' ' -f2 || echo 'unknown')
        END_VERSIONS
        """
    else
        """
        python ${projectDir}/bin/scout_to_mzidentml.py \\
            --input ${fdr_results} \\
            --fasta ${fasta} \\
            --output results.mzid \\
            ${args}

        cat <<-END_VERSIONS > versions.yml
        "${task.process}":
            scout_to_mzidentml: 1.0.0
        END_VERSIONS
        """

    stub:
    """
    touch results.mzid

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        mzidentml_export: stub
    END_VERSIONS
    """
}
```

- [ ] **Step 2: Create meta.yml**

Create `modules/local/mzidentml_export/meta.yml` with appropriate input/output descriptions.

- [ ] **Step 3: Create placeholder bin/scout_to_mzidentml.py**

Create `bin/scout_to_mzidentml.py`:

```python
#!/usr/bin/env python3
"""Convert Scout FDR-filtered CSV results to mzIdentML 1.3 format.

This is a placeholder. Scout may natively support mzIdentML export via its
-filter command. If so, this script can be replaced by that functionality.
Otherwise, implement using pyteomics.mzid.
"""

import argparse
import sys


def main():
    parser = argparse.ArgumentParser(description="Convert Scout CSV to mzIdentML 1.3")
    parser.add_argument("--input", required=True, help="Scout FDR CSV results directory")
    parser.add_argument("--fasta", required=True, help="FASTA database")
    parser.add_argument("--output", required=True, help="Output mzIdentML file")
    args = parser.parse_args()

    # TODO: Implement conversion using pyteomics or verify Scout native mzIdentML export
    # For now, check if Scout already produced mzIdentML in the input directory
    print(f"Converting Scout results from {args.input} to mzIdentML at {args.output}")
    print("WARNING: Scout mzIdentML converter not yet implemented. Producing empty mzid file.")

    with open(args.output, "w") as f:
        f.write('<?xml version="1.0" encoding="UTF-8"?>\n')
        f.write('<MzIdentML xmlns="http://psidev.info/psi/pi/mzIdentML/1.3" version="1.3.0">\n')
        f.write('</MzIdentML>\n')


if __name__ == "__main__":
    main()
```

- [ ] **Step 4: Commit**

```bash
git add modules/local/mzidentml_export/ bin/scout_to_mzidentml.py
git commit -m "feat: add MZIDENTML_EXPORT module for mzIdentML 1.3 output"
```

---

### Task 10: Add Engine-Switching Logic to relink.nf

**Repo:** `bigbio/relink`
**Files:**
- Modify: `workflows/relink.nf` (major refactor — engine branching)
- Modify: `conf/modules.config` (add Scout process configs)

This is the core integration task. The workflow branches based on `params.search_engine`.

- [ ] **Step 1: Add Scout module imports**

In `workflows/relink.nf`, add after line 12:

```groovy
include { SCOUT_SEARCH              } from '../modules/local/scout_search/main'
include { SCOUT_FILTER              } from '../modules/local/scout_filter/main'
include { MZIDENTML_EXPORT          } from '../modules/local/mzidentml_export/main'
```

- [ ] **Step 2: Refactor workflow with engine branching**

Replace the workflow body (lines 24-196) with the engine-branching version. The key structure:

```groovy
workflow RELINK {

    take:
    ch_samplesheet

    main:

    ch_versions = Channel.empty()
    ch_multiqc_files = Channel.empty()

    // Prepare input channels (same for both engines)
    ch_samplesheet
        .map { meta, file, fasta, linear_config, crosslink_config ->
            [ meta, file ]
        }
        .branch {
            raw: it[1].name.toLowerCase().endsWith('.raw')
            mzml: it[1].name.toLowerCase().endsWith('.mzml')
        }
        .set { ch_input_by_type }

    ch_fasta = ch_samplesheet.map { meta, file, fasta, lc, cc -> fasta }.first()
    ch_linear_config = ch_samplesheet.map { meta, file, fasta, lc, cc -> lc }.first()
    ch_crosslink_config = ch_samplesheet.map { meta, file, fasta, lc, cc -> cc }.first()

    // STEP 1: File Conversion (RAW -> mzML) — shared by both engines
    THERMORAWFILEPARSER ( ch_input_by_type.raw )
    ch_versions = ch_versions.mix(THERMORAWFILEPARSER.out.versions.first())

    ch_mzml = THERMORAWFILEPARSER.out.convert_files
        .mix(ch_input_by_type.mzml)

    // =========================================================================
    // ENGINE BRANCHING
    // =========================================================================

    if (params.search_engine == 'xisearch') {

        // --- xiSEARCH PATH (existing) ---

        if (params.do_recalibration) {
            XISEARCH_LINEAR ( ch_mzml, ch_fasta, ch_linear_config, 'linear' )
            ch_versions = ch_versions.mix(XISEARCH_LINEAR.out.versions.first())

            ch_for_recal = XISEARCH_LINEAR.out.results
                .join(XISEARCH_LINEAR.out.peaks)
                .join(ch_mzml)

            MASS_RECALIBRATION ( ch_for_recal, params.do_mass_error_plots )
            ch_versions = ch_versions.mix(MASS_RECALIBRATION.out.versions.first())
            ch_mzml_for_crosslink = MASS_RECALIBRATION.out.mzml
        } else {
            ch_mzml_for_crosslink = ch_mzml
        }

        if (params.do_crosslinking_search) {
            XISEARCH_CROSSLINK ( ch_mzml_for_crosslink, ch_fasta, ch_crosslink_config, 'crosslink' )
            ch_versions = ch_versions.mix(XISEARCH_CROSSLINK.out.versions.first())
            ch_crosslink_results = XISEARCH_CROSSLINK.out.results

            if (params.do_fdr) {
                XIFDR (
                    ch_crosslink_results.map { meta, csv -> csv }.collect(),
                    ch_fasta, ch_crosslink_config, params.link_fdr
                )
                ch_versions = ch_versions.mix(XIFDR.out.versions.first())
                ch_fdr_results = XIFDR.out.results
            }
        }

    } else if (params.search_engine == 'scout') {

        // --- SCOUT PATH (new) ---

        // Scout search params come from custom_search_config or generated configs
        ch_scout_search_params = params.custom_search_config
            ? Channel.fromPath(params.custom_search_config)
            : ch_crosslink_config  // fallback: use crosslink config path

        SCOUT_SEARCH (
            ch_mzml,
            ch_scout_search_params,
            ch_scout_search_params,  // filter params (same file for now)
            ch_fasta
        )
        ch_versions = ch_versions.mix(SCOUT_SEARCH.out.versions.first())

        if (params.do_fdr) {
            SCOUT_FILTER (
                SCOUT_SEARCH.out.buf_files.map { meta, buf -> buf }.collect(),
                ch_scout_search_params,
                ch_fasta
            )
            ch_versions = ch_versions.mix(SCOUT_FILTER.out.versions.first())
            ch_fdr_results = SCOUT_FILTER.out.results
        }

    } else {
        error "Unknown search engine: ${params.search_engine}. Use 'xisearch' or 'scout'."
    }

    // =========================================================================
    // mzIdentML Export (both paths)
    // =========================================================================

    if (params.do_fdr) {
        MZIDENTML_EXPORT (
            ch_fdr_results,
            ch_fasta,
            params.search_engine
        )
        ch_versions = ch_versions.mix(MZIDENTML_EXPORT.out.versions.first())
    }

    // =========================================================================
    // Reporting (unchanged)
    // =========================================================================

    // ... (keep existing PMULTIQC section unchanged)
```

- [ ] **Step 3: Add Scout module configs to modules.config**

Append to `conf/modules.config` before the closing `}`:

```groovy
    // =========================================================================
    // Scout Search
    // =========================================================================

    withName: 'SCOUT_SEARCH' {
        ext.args = ''
        publishDir = [
            path: { "${params.outdir}/scout_search" },
            mode: params.publish_dir_mode,
            pattern: "*.buf"
        ]
    }

    withName: 'SCOUT_FILTER' {
        publishDir = [
            path: { "${params.outdir}/fdr" },
            mode: params.publish_dir_mode,
            pattern: "*.csv"
        ]
    }

    // =========================================================================
    // mzIdentML Export
    // =========================================================================

    withName: 'MZIDENTML_EXPORT' {
        publishDir = [
            path: { "${params.outdir}/mzidentml" },
            mode: params.publish_dir_mode,
            pattern: "*.mzid"
        ]
    }
```

- [ ] **Step 4: Commit**

```bash
git add workflows/relink.nf conf/modules.config
git commit -m "feat: add engine-switching logic (xisearch/scout) in relink.nf"
```

---

### Task 11: Add `convert-relink` to sdrf-pipelines

**Repo:** `sdrf-pipelines` (at `/Users/yperez/work/sdrf-workspace/sdrf-pipelines/`)
**Files:**
- Create: `src/sdrf_pipelines/converters/relink/__init__.py`
- Create: `src/sdrf_pipelines/converters/relink/relink.py`
- Modify: `src/sdrf_pipelines/parse_sdrf.py` (add import + CLI command)

- [ ] **Step 1: Create the relink converter directory**

```bash
mkdir -p /Users/yperez/work/sdrf-workspace/sdrf-pipelines/src/sdrf_pipelines/converters/relink
```

- [ ] **Step 2: Create `__init__.py`**

Create `src/sdrf_pipelines/converters/relink/__init__.py`:

```python
from sdrf_pipelines.converters.relink.relink import Relink

__all__ = ["Relink"]
```

- [ ] **Step 3: Create the converter class**

Create `src/sdrf_pipelines/converters/relink/relink.py`:

```python
import re

import pandas as pd


class Relink:
    """Convert SDRF to relink pipeline configuration files."""

    def __init__(self) -> None:
        self.warnings: dict[str, int] = {}

    def convert_relink_config(self, sdrf_file: str, output_path: str) -> None:
        """Convert SDRF file to relink_config.tsv.

        Extracts standard proteomics columns and XL-MS specific columns
        (crosslinker, enrichment, etc.) into a per-file config TSV.
        """
        sdrf = pd.read_csv(sdrf_file, sep="\t")
        sdrf.columns = sdrf.columns.str.lower()

        rows = []
        for _, row in sdrf.iterrows():
            entry = {}

            # Standard columns
            entry["filename"] = row.get("comment[data file]", "")
            entry["sample_id"] = row.get("source name", "")
            entry["fraction"] = row.get("comment[fraction identifier]", "1")
            entry["technical_replicate"] = row.get("comment[technical replicate]", "1")

            # Enzyme(s)
            enzyme_cols = [c for c in sdrf.columns if c.startswith("comment[cleavage agent details]")]
            enzymes = []
            for ec in enzyme_cols:
                val = row.get(ec, "")
                if pd.notna(val) and val:
                    nt_match = re.search(r"NT=([^;]+)", str(val))
                    if nt_match:
                        enzymes.append(nt_match.group(1))
            entry["enzyme"] = ";".join(enzymes) if enzymes else "Trypsin"

            # Modifications
            mod_cols = [c for c in sdrf.columns if c.startswith("comment[modification parameters]")]
            fixed_mods = []
            variable_mods = []
            for mc in mod_cols:
                val = str(row.get(mc, ""))
                if "MT=Fixed" in val or "MT=fixed" in val:
                    nt_match = re.search(r"NT=([^;]+)", val)
                    ta_match = re.search(r"TA=([^;]+)", val)
                    if nt_match:
                        mod_name = nt_match.group(1)
                        mod_site = ta_match.group(1) if ta_match else ""
                        fixed_mods.append(f"{mod_name} ({mod_site})")
                elif "MT=Variable" in val or "MT=variable" in val:
                    nt_match = re.search(r"NT=([^;]+)", val)
                    ta_match = re.search(r"TA=([^;]+)", val)
                    if nt_match:
                        mod_name = nt_match.group(1)
                        mod_site = ta_match.group(1) if ta_match else ""
                        variable_mods.append(f"{mod_name} ({mod_site})")
            entry["fixed_modifications"] = ";".join(fixed_mods)
            entry["variable_modifications"] = ";".join(variable_mods)

            # Tolerances
            entry["precursor_mass_tolerance"] = row.get("comment[precursor mass tolerance]", "10 ppm")
            entry["fragment_mass_tolerance"] = row.get("comment[fragment mass tolerance]", "20 ppm")

            # Dissociation
            diss_val = row.get("comment[dissociation method]", "")
            nt_match = re.search(r"NT=([^;]+)", str(diss_val))
            entry["dissociation_method"] = nt_match.group(1) if nt_match else "HCD"

            # Collision energy
            entry["collision_energy"] = row.get("comment[collision energy]", "")

            # XL-MS specific columns
            crosslinker_val = row.get("comment[cross-linker]", "")
            entry["crosslinker_raw"] = str(crosslinker_val)
            # Parse crosslinker fields
            if pd.notna(crosslinker_val) and crosslinker_val:
                cl_str = str(crosslinker_val)
                nt_match = re.search(r"NT=([^;]+)", cl_str)
                ac_match = re.search(r"AC=([^;]+)", cl_str)
                ta_match = re.search(r"TA=([^;]+)", cl_str)
                mh_match = re.search(r"MH=([^;]+)", cl_str)
                ml_match = re.search(r"ML=([^;]+)", cl_str)
                cl_match = re.search(r"CL=([^;]+)", cl_str)
                entry["crosslinker_name"] = nt_match.group(1) if nt_match else ""
                entry["crosslinker_accession"] = ac_match.group(1) if ac_match else ""
                entry["crosslinker_sites"] = ta_match.group(1) if ta_match else ""
                entry["crosslinker_mass_heavy"] = mh_match.group(1) if mh_match else ""
                entry["crosslinker_mass_light"] = ml_match.group(1) if ml_match else ""
                entry["crosslinker_cleavable"] = cl_match.group(1) if cl_match else ""
            else:
                entry["crosslinker_name"] = ""
                entry["crosslinker_accession"] = ""
                entry["crosslinker_sites"] = ""
                entry["crosslinker_mass_heavy"] = ""
                entry["crosslinker_mass_light"] = ""
                entry["crosslinker_cleavable"] = ""

            entry["experiment_type"] = row.get(
                "comment[chemical cross-linking coupled with ms]", ""
            )
            entry["enrichment_method"] = row.get("comment[crosslink enrichment method]", "")
            entry["crosslinker_concentration"] = row.get("comment[crosslinker concentration]", "")
            entry["crosslink_distance"] = row.get("comment[crosslink distance]", "")

            rows.append(entry)

        df = pd.DataFrame(rows)
        df.to_csv(output_path, sep="\t", index=False)
        print(f"Wrote relink config with {len(df)} entries to {output_path}")

        for warning, count in self.warnings.items():
            print(f"WARNING: {warning} (occurred {count} times)")
```

- [ ] **Step 4: Register CLI command in parse_sdrf.py**

In `src/sdrf_pipelines/parse_sdrf.py`, add the import:

```python
from sdrf_pipelines.converters.relink.relink import Relink
```

Add the CLI command function:

```python
@click.command("convert-relink", short_help="convert sdrf to relink pipeline config")
@click.option("--sdrf", "-s", help="SDRF file", required=True)
@click.option("--outpath", "-o", help="Output config TSV path", default="relink_config.tsv")
@click.pass_context
def relink_from_sdrf(ctx, sdrf, outpath):
    Relink().convert_relink_config(sdrf, outpath)
```

And register it:

```python
cli.add_command(relink_from_sdrf)
```

- [ ] **Step 5: Test locally**

```bash
cd /Users/yperez/work/sdrf-workspace/sdrf-pipelines
pip install -e .
parse_sdrf convert-relink -s /Users/yperez/work/sdrf-workspace/proteomics-sample-metadata/examples/PXD042173/PXD042173.sdrf.tsv -o /tmp/relink_config.tsv
cat /tmp/relink_config.tsv | head -3
```

Expected: TSV with columns for filename, sample_id, enzyme, mods, tolerances, crosslinker fields.

- [ ] **Step 6: Commit**

```bash
cd /Users/yperez/work/sdrf-workspace/sdrf-pipelines
git add src/sdrf_pipelines/converters/relink/ src/sdrf_pipelines/parse_sdrf.py
git commit -m "feat: add convert-relink converter for XL-MS SDRF files"
```

---

### Task 12: Create Parameter Translator Script

**Repo:** `bigbio/relink`
**Files:**
- Create: `bin/generate_engine_config.py`

This script reads `relink_config.tsv` (from SDRF parsing) and generates engine-specific config files.

- [ ] **Step 1: Create the parameter translator**

Create `bin/generate_engine_config.py`:

```python
#!/usr/bin/env python3
"""Generate engine-specific config files from relink_config.tsv.

Reads the SDRF-derived relink_config.tsv and produces:
- xiSEARCH: xi_linear.conf + xi_crosslinking.conf (XML-like config)
- Scout: search_params.json + filter_params.json
"""

import argparse
import json
import sys

import pandas as pd


def generate_xisearch_config(config_df: pd.DataFrame, output_prefix: str) -> None:
    """Generate xiSEARCH linear and crosslink config files."""
    # Take parameters from first row (assumed consistent across samples)
    row = config_df.iloc[0]

    enzyme = row.get("enzyme", "Trypsin")
    fixed_mods = row.get("fixed_modifications", "")
    variable_mods = row.get("variable_modifications", "")
    precursor_tol = row.get("precursor_mass_tolerance", "10 ppm")
    fragment_tol = row.get("fragment_mass_tolerance", "20 ppm")
    crosslinker_name = row.get("crosslinker_name", "DSSO")
    crosslinker_sites = row.get("crosslinker_sites", "K,S,T,Y,nterm")
    crosslinker_mass_heavy = row.get("crosslinker_mass_heavy", "54.01")
    crosslinker_mass_light = row.get("crosslinker_mass_light", "85.98")

    # Parse tolerance values
    prec_val, prec_unit = _parse_tolerance(precursor_tol)
    frag_val, frag_unit = _parse_tolerance(fragment_tol)

    # Linear config (no crosslinker)
    linear_config = f"""## xiSEARCH linear config (auto-generated from SDRF)
tolerance:precursor:{prec_val}{prec_unit}
tolerance:fragment:{frag_val}{frag_unit}
digestion:{enzyme}
modification:fixed:{fixed_mods}
modification:variable:{variable_mods}
"""
    with open(f"{output_prefix}_linear.conf", "w") as f:
        f.write(linear_config)

    # Crosslinking config
    crosslink_config = f"""## xiSEARCH crosslinking config (auto-generated from SDRF)
tolerance:precursor:{prec_val}{prec_unit}
tolerance:fragment:{frag_val}{frag_unit}
digestion:{enzyme}
modification:fixed:{fixed_mods}
modification:variable:{variable_mods}
crosslinker:name:{crosslinker_name}
crosslinker:sites:{crosslinker_sites}
crosslinker:mass_heavy:{crosslinker_mass_heavy}
crosslinker:mass_light:{crosslinker_mass_light}
"""
    with open(f"{output_prefix}_crosslinking.conf", "w") as f:
        f.write(crosslink_config)

    print(f"Generated xiSEARCH configs: {output_prefix}_linear.conf, {output_prefix}_crosslinking.conf")


def generate_scout_config(config_df: pd.DataFrame, output_prefix: str) -> None:
    """Generate Scout search and filter parameter JSON files."""
    row = config_df.iloc[0]

    enzyme = row.get("enzyme", "Trypsin")
    fixed_mods = row.get("fixed_modifications", "")
    variable_mods = row.get("variable_modifications", "")
    precursor_tol = row.get("precursor_mass_tolerance", "10 ppm")
    fragment_tol = row.get("fragment_mass_tolerance", "20 ppm")
    crosslinker_name = row.get("crosslinker_name", "DSSO")
    crosslinker_sites = row.get("crosslinker_sites", "K,S,T,Y,nterm")
    crosslinker_mass_heavy = row.get("crosslinker_mass_heavy", "54.01")
    crosslinker_mass_light = row.get("crosslinker_mass_light", "85.98")
    crosslinker_cleavable = row.get("crosslinker_cleavable", "yes")

    prec_val, prec_unit = _parse_tolerance(precursor_tol)
    frag_val, frag_unit = _parse_tolerance(fragment_tol)

    search_params = {
        "enzyme": enzyme,
        "fixed_modifications": fixed_mods.split(";") if fixed_mods else [],
        "variable_modifications": variable_mods.split(";") if variable_mods else [],
        "precursor_tolerance": {"value": float(prec_val), "unit": prec_unit},
        "fragment_tolerance": {"value": float(frag_val), "unit": frag_unit},
        "crosslinker": {
            "name": crosslinker_name,
            "reactive_sites": crosslinker_sites.split(","),
            "mass_heavy": float(crosslinker_mass_heavy) if crosslinker_mass_heavy else 0,
            "mass_light": float(crosslinker_mass_light) if crosslinker_mass_light else 0,
            "cleavable": crosslinker_cleavable.lower() == "yes",
        },
    }

    filter_params = {
        "fdr_threshold": 0.05,
        "level": "residue_pair",
    }

    with open(f"{output_prefix}_search_params.json", "w") as f:
        json.dump(search_params, f, indent=2)

    with open(f"{output_prefix}_filter_params.json", "w") as f:
        json.dump(filter_params, f, indent=2)

    print(f"Generated Scout configs: {output_prefix}_search_params.json, {output_prefix}_filter_params.json")


def _parse_tolerance(tol_str: str) -> tuple[str, str]:
    """Parse tolerance string like '10 ppm' or '20 Da' into (value, unit)."""
    tol_str = str(tol_str).strip()
    parts = tol_str.split()
    if len(parts) >= 2:
        return parts[0], parts[1]
    return tol_str, "ppm"


def main():
    parser = argparse.ArgumentParser(description="Generate engine-specific configs from relink_config.tsv")
    parser.add_argument("--config", required=True, help="relink_config.tsv from SDRF parsing")
    parser.add_argument("--engine", required=True, choices=["xisearch", "scout"], help="Search engine")
    parser.add_argument("--output-prefix", default="generated", help="Output file prefix")
    parser.add_argument("--override", default=None, help="Optional user override config file")
    args = parser.parse_args()

    config_df = pd.read_csv(args.config, sep="\t")

    if args.engine == "xisearch":
        generate_xisearch_config(config_df, args.output_prefix)
    elif args.engine == "scout":
        generate_scout_config(config_df, args.output_prefix)


if __name__ == "__main__":
    main()
```

- [ ] **Step 2: Make executable**

```bash
chmod +x bin/generate_engine_config.py
```

- [ ] **Step 3: Commit**

```bash
git add bin/generate_engine_config.py
git commit -m "feat: add parameter translator (SDRF config -> engine-specific configs)"
```

---

### Task 13: Add SDRF Input Subworkflow to relink

**Repo:** `bigbio/relink`
**Files:**
- Create: `modules/local/sdrf_parsing/main.nf`
- Create: `modules/local/generate_engine_config/main.nf`
- Modify: `subworkflows/local/utils_nfcore_relink_pipeline/main.nf:74-80`
- Modify: `nextflow.config` (if needed for SDRF param)

This task wires SDRF parsing into the pipeline input. The pipeline should accept either SDRF or legacy CSV samplesheet.

- [ ] **Step 1: Create SDRF_PARSING process**

Create `modules/local/sdrf_parsing/main.nf`:

```groovy
process SDRF_PARSING {
    label 'process_single'

    container 'biocontainers/sdrf-pipelines:0.1.2--pyhdfd78af_0'

    input:
    path sdrf

    output:
    path "relink_config.tsv", emit: config
    path "versions.yml",      emit: versions

    script:
    """
    parse_sdrf convert-relink -s ${sdrf} -o relink_config.tsv

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        sdrf-pipelines: \$(pip show sdrf-pipelines 2>/dev/null | grep Version | cut -d' ' -f2 || echo 'unknown')
    END_VERSIONS
    """
}
```

- [ ] **Step 2: Create GENERATE_ENGINE_CONFIG process**

Create `modules/local/generate_engine_config/main.nf`:

```groovy
process GENERATE_ENGINE_CONFIG {
    label 'process_single'

    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'oras://ghcr.io/bigbio/relink-sif:1.1.0' :
        'ghcr.io/bigbio/relink:1.1.0' }"

    input:
    path relink_config
    val search_engine
    path custom_config

    output:
    path "*.conf", emit: xisearch_configs, optional: true
    path "*.json", emit: scout_configs, optional: true
    path "versions.yml", emit: versions

    script:
    def override = custom_config.name != 'NO_FILE' ? "--override ${custom_config}" : ''
    """
    python ${projectDir}/bin/generate_engine_config.py \\
        --config ${relink_config} \\
        --engine ${search_engine} \\
        --output-prefix generated \\
        ${override}

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        generate_engine_config: 1.0.0
    END_VERSIONS
    """
}
```

- [ ] **Step 3: Commit**

```bash
git add modules/local/sdrf_parsing/ modules/local/generate_engine_config/
git commit -m "feat: add SDRF_PARSING and GENERATE_ENGINE_CONFIG modules"
```

---

### Task 14: Create Test Profile with PXD042173

**Repo:** `bigbio/relink`
**Files:**
- Modify: `conf/test.config`
- Create: `assets/test_sdrf_PXD042173_2files.tsv` (2-row SDRF subset)

- [ ] **Step 1: Create 2-file SDRF test subset**

Create `assets/test_sdrf_PXD042173_2files.tsv` with the header and first 2 data rows from the PXD042173 SDRF (files B12 and E12). This is a tab-separated file — copy the first 3 lines (header + 2 rows) from the full SDRF.

- [ ] **Step 2: Add Scout test profile**

In `conf/test.config`, add a section or create `conf/test_scout.config`:

```groovy
params {
    config_profile_name        = 'Scout test profile'
    config_profile_description = 'Test Scout search engine with PXD042173 (2 files)'

    input          = "${projectDir}/assets/test_sdrf_PXD042173_2files.tsv"
    search_engine  = 'scout'
    outdir         = 'results_scout_test'
    fasta          = 'https://raw.githubusercontent.com/bigbio/relink/dev/assets/test_data/Homo_sapiens_320prots.fasta'

    max_cpus   = 2
    max_memory = '6.GB'
    max_time   = '6.h'
}
```

- [ ] **Step 3: Commit**

```bash
git add assets/test_sdrf_PXD042173_2files.tsv conf/test_scout.config
git commit -m "feat: add Scout test profile with PXD042173 2-file SDRF"
```

---

### Task 15: Create GitHub Issues

**Repo:** Multiple repos
**Files:** N/A (GitHub API only)

Create issues in the appropriate repositories to track this work.

- [ ] **Step 1: Create issues in bigbio/relink**

```bash
# Issue 1: MGF -> mzML migration
gh issue create --repo bigbio/relink \
    --title "Switch spectral format from MGF to mzML" \
    --body "Update ThermoRawFileParser to output mzML (-f=2), adapt xiSEARCH module, adapt mass recalibration script, remove FORMAT_CORRECTION step. Both xiSEARCH and Scout support mzML natively."

# Issue 2: Scout integration
gh issue create --repo bigbio/relink \
    --title "Add Scout as switchable search engine" \
    --body "Add SCOUT_SEARCH and SCOUT_FILTER modules. Scout v2.1 supports -no_filter for per-sample parallel search and -filter for aggregated FDR. Switch via params.search_engine='scout'. FDR is tied to engine: xiSEARCH uses xiFDR, Scout uses -filter."

# Issue 3: SDRF input
gh issue create --repo bigbio/relink \
    --title "Add SDRF input support" \
    --body "Replace CSV samplesheet with SDRF input. Use sdrf-pipelines convert-relink converter. Add parameter translator (bin/generate_engine_config.py) to generate xiSEARCH XML or Scout JSON configs from SDRF columns."

# Issue 4: mzIdentML output
gh issue create --repo bigbio/relink \
    --title "Add mzIdentML 1.3 export" \
    --body "Add MZIDENTML_EXPORT module. xiSEARCH path uses xi-mzidentml-converter. Scout path uses native export or custom converter. Required for PRIDE deposition."

# Issue 5: Test dataset
gh issue create --repo bigbio/relink \
    --title "Add test profile with PXD042173 for Scout" \
    --body "Create 2-file SDRF subset from PXD042173 for benchmarking both xiSEARCH and Scout paths."
```

- [ ] **Step 2: Create issue in sdrf-pipelines**

```bash
gh issue create --repo bigbio/sdrf-pipelines \
    --title "Add convert-relink converter for XL-MS SDRF" \
    --body "New converter that extracts XL-MS specific SDRF columns (cross-linker, enrichment method, crosslink distance) plus standard proteomics columns (enzyme, mods, tolerances). Outputs relink_config.tsv for the relink pipeline."
```

- [ ] **Step 3: Create issue in quantms-containers**

```bash
gh issue create --repo bigbio/quantms-containers \
    --title "Update relink container: Scout 2.0 -> 2.1 + xi-mzidentml-converter" \
    --body "Scout 2.1 adds -no_filter flag required for HPC parallelization. Also add xi-mzidentml-converter Python package for mzIdentML 1.3 export."
```

- [ ] **Step 4: Commit** (N/A — issues are on GitHub)

---

## Dependency Graph

```
Task 1  (container update) ─────────────────────────┐
                                                     │
Task 2  (MGF->mzML) ──┐                             │
Task 3  (xiSEARCH mzML) ──┤                         │
Task 4  (recalibration mzML) ──┤                     │
Task 5  (remove FORMAT_CORRECTION) ──┘               │
                        │                            │
Task 6  (search_engine param) ──────────────┐        │
                                            │        │
Task 7  (SCOUT_SEARCH module) ──────────────┤ requires Task 1
Task 8  (SCOUT_FILTER module) ──────────────┤        │
Task 9  (MZIDENTML_EXPORT module) ─────────┤        │
                                            │        │
Task 10 (engine-switching relink.nf) ───────┘ requires Tasks 2-9
                                            │
Task 11 (sdrf-pipelines converter) ─────────┤ independent
Task 12 (parameter translator) ─────────────┤ requires Task 11
Task 13 (SDRF input subworkflow) ───────────┤ requires Tasks 11-12
                                            │
Task 14 (test profile) ────────────────────── requires Tasks 10,13
Task 15 (GitHub issues) ──────────────────── independent, do first
```

## Parallel Execution Groups

These task groups can be executed in parallel:

- **Group A** (independent): Task 15 (issues)
- **Group B** (independent): Task 11 (sdrf-pipelines converter)
- **Group C** (relink mzML migration): Tasks 2, 3, 4, 5 (sequential within group)
- **Group D** (relink Scout modules): Tasks 6, 7, 8, 9 (after Task 1)
- **Group E** (integration): Task 10 (requires Groups C + D)
- **Group F** (SDRF wiring): Tasks 12, 13 (requires Group B)
- **Group G** (testing): Task 14 (requires Groups E + F)
