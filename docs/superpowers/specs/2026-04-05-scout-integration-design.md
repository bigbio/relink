# Design: Scout Search Engine Integration & SDRF Input Support

## Summary

Extend the relink XL-MS pipeline to support Scout as a switchable search engine alongside xiSEARCH, controlled by `params.search_engine`. Add SDRF-based input with automatic parameter translation to engine-specific configs. Standardize on mzML as the intermediate spectral format. Output mzIdentML 1.3 for PRIDE deposition. FDR tool is tied to the engine: xiSEARCH uses xiFDR, Scout uses its built-in `-filter`.

## Motivation

- The current pipeline only supports xiSEARCH. Scout (Nature Methods 2023) is a complementary search engine optimized for MS-cleavable crosslinkers (DSSO, DSBU) with excellent speed and sensitivity.
- SDRF input enables standardized, reproducible experiment descriptions — consistent with the quantms/quantmsdiann ecosystem.
- mzIdentML 1.3 output is required for PRIDE deposition and community interoperability.
- Future goal: combine both engines in a multi-engine FDR approach. This design is the foundation for that.

## Pipeline Architecture

### Overall Flow

```
SDRF (input)
    |
    v
SDRF_PARSING (once)
    |
    v
PARAMETER_TRANSLATOR (once)
    | -> engine-specific configs (value channel, shared by all samples)
    | -> per-file channel: [meta, raw_file]
    |
    v
+=================== PER SAMPLE (parallel) ====================+
|                                                               |
|  THERMORAWFILEPARSER (RAW -> mzML)                            |
|       |                                                       |
|  +--- params.search_engine --------+                          |
|  |                                  |                         |
|  |  'xisearch' (default)            |  'scout'               |
|  |                                  |                         |
|  |  XISEARCH_LINEAR (mzML)          |  SCOUT_SEARCH           |
|  |  MASS_RECALIBRATION              |  (-no_filter, mzML)     |
|  |  XISEARCH_CROSSLINK (mzML)       |  -> *.buf file          |
|  |  -> *.csv file                   |                         |
|  |                                  |                         |
|  +----------------------------------+                         |
|                                                               |
+===============================================================+
                       |
                  .collect()   <-- aggregation barrier
                       |
    +--- params.search_engine --------+
    |                                  |
    |  XIFDR                           |  SCOUT_FILTER
    |  (all CSVs together)             |  (all *.buf together)
    |                                  |
    +---------------+------------------+
                    |
                    v
              MZIDENTML_EXPORT (once)
                    |
                    v
                 PMULTIQC (once)
```

### Key Design Decisions

1. **mzML as standard intermediate format**: Both xiSEARCH and Scout support mzML. ThermoRawFileParser converts RAW -> mzML. This replaces the current MGF-only path. The FORMAT_CORRECTION step (MGF scientific notation fix) is no longer needed.

2. **Per-sample parallelism**: Each RAW file is searched independently in parallel. Nextflow handles this natively via per-sample channels. The only serialization point is `.collect()` before FDR computation.

3. **FDR tied to engine**: xiSEARCH uses xiFDR, Scout uses Scout `-filter`. No cross-engine FDR mixing in this phase.

4. **Single container**: The existing `ghcr.io/bigbio/relink` container already bundles xiSEARCH, xiFDR, Scout, .NET, Python, libmpfr. Needs version bump to Scout 2.1 for `-no_filter` support.

## SDRF Parsing & Parameter Translation

### SDRF Converter (`convert-relink` in sdrf-pipelines)

A new converter in the `sdrf-pipelines` package, following the quantms pattern (`parse_sdrf convert-openms`, `parse_sdrf convert-diann`).

**Command**: `parse_sdrf convert-relink -s <sdrf_file>`

**Standard columns extracted:**

| SDRF Column | Output Field | Example |
|-------------|-------------|---------|
| `comment[data file]` | filename | `sample_B12.raw` |
| `source name` | sample_id | `PXD042173-batch1` |
| `comment[cleavage agent details]` | enzyme | `Trypsin`, `Lys-C` |
| `comment[modification parameters]` (MT=Fixed) | fixed_mods | `Carbamidomethyl (C)` |
| `comment[modification parameters]` (MT=Variable) | variable_mods | `Oxidation (M)` |
| `comment[precursor mass tolerance]` | precursor_tol | `10 ppm` |
| `comment[fragment mass tolerance]` | fragment_tol | `20 ppm` |
| `comment[dissociation method]` | dissociation | `stepped HCD` |
| `comment[collision energy]` | collision_energy | `stepped 27+-6%` |
| `comment[fraction identifier]` | fraction | `1` |
| `comment[technical replicate]` | technical_replicate | `1` |

**XL-MS specific columns:**

| SDRF Column | Output Field | Example |
|-------------|-------------|---------|
| `comment[cross-linker]` | crosslinker | `NT=DSSO;AC=XLMOD:02010;CL=yes;TA=K,S,T,Y,nterm;MH=54.01;ML=85.98` |
| `comment[chemical cross-linking coupled with ms]` | experiment_type | `cross-linking mass spectrometry` |
| `comment[crosslink enrichment method]` | enrichment_method | `strong cation exchange chromatography` |
| `comment[crosslinker concentration]` | crosslinker_conc | `0.2-1 mM` |
| `comment[crosslink distance]` | crosslink_distance | `26.4 A` |

**Output**: `relink_config.tsv` — per-file metadata with all extracted parameters.

### Parameter Translator (`bin/generate_engine_config.py`)

A Python helper script that reads `relink_config.tsv` + optional user overrides and generates engine-specific configuration files.

**Input:**
- `relink_config.tsv` (from SDRF parsing)
- `params.search_engine` ('xisearch' or 'scout')
- `params.custom_search_config` (optional user override file)

**Output for xiSEARCH:**
- `xi_linear.conf` (XML) — linear search config with enzyme, mods, tolerances
- `xi_crosslinking.conf` (XML) — crosslink search config with crosslinker definition

**Output for Scout:**
- `search_params.json` — search parameters (enzyme, mods, tolerances, crosslinker)
- `filter_params.json` — FDR filter parameters

**Crosslinker mapping example:**
```
SDRF: NT=DSSO;AC=XLMOD:02010;CL=yes;TA=K,S,T,Y,nterm;MH=54.01;ML=85.98

xiSEARCH XML:
  <crosslinker name="DSSO" mass="158.00376" sites="K,S,T,Y,nterm"
               cleavable="true" stub_mass_short="54.01" stub_mass_long="85.98"/>

Scout JSON:
  {"crosslinker": "DSSO", "reactive_sites": ["K","S","T","Y","nterm"],
   "mass": 158.00376, "cleavable": true, "stub_short": 54.01, "stub_long": 85.98}
```

**Override precedence**: `params.custom_search_config` > SDRF-derived values > defaults.

### Nextflow Integration

```groovy
process SDRF_PARSING {
    container 'biocontainers/sdrf-pipelines:<version>'

    input:
    path sdrf

    output:
    path "relink_config.tsv", emit: config

    script:
    """
    parse_sdrf convert-relink -s ${sdrf}
    """
}

process GENERATE_ENGINE_CONFIG {
    container 'ghcr.io/bigbio/relink:<version>'

    input:
    path relink_config
    val search_engine
    path custom_config  // optional

    output:
    path "*.conf", emit: xisearch_configs, optional: true
    path "*.json", emit: scout_configs, optional: true

    script:
    def override = custom_config.name != 'NO_FILE' ? "--override ${custom_config}" : ''
    """
    generate_engine_config.py \
        --config ${relink_config} \
        --engine ${search_engine} \
        ${override}
    """
}
```

## Scout Nextflow Modules

### SCOUT_SEARCH (per sample, parallel)

```groovy
process SCOUT_SEARCH {
    tag "$meta.id"
    label 'process_high'
    container 'ghcr.io/bigbio/relink:<version>'

    input:
    tuple val(meta), path(mzml_file)
    path search_params
    path filter_params
    path fasta

    output:
    tuple val(meta), path("*.buf"), emit: buf_files
    path "versions.yml",            emit: versions

    script:
    """
    run_scout.sh -search -no_filter ${search_params} ${filter_params}

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        scout: \$(run_scout.sh --version 2>&1 || echo "2.1")
    END_VERSIONS
    """
}
```

- Runs once per mzML file, embarrassingly parallel across all samples
- Produces `*.buf` intermediate files
- `*.scout` files are not published (intermediate only)
- Requires Scout >= 2.1 for `-no_filter` flag

### SCOUT_FILTER (once, aggregation)

```groovy
process SCOUT_FILTER {
    label 'process_medium'
    container 'ghcr.io/bigbio/relink:<version>'

    input:
    path buf_files    // collected from all samples
    path filter_params
    path fasta

    output:
    path "output/*.csv", emit: results
    path "versions.yml", emit: versions

    script:
    """
    run_scout.sh -filter ${filter_params} \
        -fasta ${fasta} \
        -i . \
        -o output/

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        scout: \$(run_scout.sh --version 2>&1 || echo "2.1")
    END_VERSIONS
    """
}
```

- Receives all `*.buf` files via `.collect()`
- Single global FDR computation across all samples
- Outputs filtered CSV results + mzIdentML (if Scout supports direct export)

## mzIdentML Export

```groovy
process MZIDENTML_EXPORT {
    label 'process_medium'
    container 'ghcr.io/bigbio/relink:<version>'

    input:
    path fdr_results
    path fasta
    val search_engine

    output:
    path "*.mzid", emit: mzidentml
    path "versions.yml", emit: versions

    script:
    if (search_engine == 'xisearch')
        """
        xi-mzidentml-converter --input ${fdr_results} \
            --fasta ${fasta} --output results.mzid
        """
    else
        """
        scout_to_mzidentml.py --input ${fdr_results} \
            --fasta ${fasta} --output results.mzid
        """
}
```

**xiSEARCH path**: `xi-mzidentml-converter` (Python, already in ecosystem, supports xiFDR CSV -> mzIdentML 1.3).

**Scout path**: Scout can natively export mzIdentML 1.2/1.3. Two options: (a) if Scout `-filter` has a flag to output mzIdentML directly, use that; (b) otherwise, write a `scout_to_mzidentml.py` converter using pyteomics. Determine which option during implementation of issue #7.

Both paths must produce mzIdentML 1.3 compliant with PRIDE deposition requirements.

## Workflow Parameters

```groovy
// Engine selection
params.search_engine         = 'xisearch'    // 'xisearch' or 'scout'

// Input
params.input                 = null           // Path to SDRF file

// Database
params.fasta                 = null           // Target FASTA (no decoys)

// FDR
params.link_fdr              = 5              // Link-level FDR % (both engines)
params.do_fdr                = true           // Enable/disable FDR step

// Recalibration (xiSEARCH path only)
params.do_recalibration      = true
params.do_mass_error_plots   = false

// Override
params.custom_search_config  = null           // Optional engine config override

// Output
params.outdir                = null
```

## Existing Module Changes

| Module | Change |
|--------|--------|
| `THERMORAWFILEPARSER` | Output mzML instead of MGF (change `--format` flag) |
| `XISEARCH` (linear + crosslink) | Accept mzML input instead of MGF |
| `MASS_RECALIBRATION` | Adapt `recalibrate_mgf.py` to read/write mzML (rename to `recalibrate_spectra.py`, use pyteomics.mzml for I/O). The recalibration logic (precursor/fragment mass error estimation and correction) is format-agnostic; only the I/O layer changes. |
| `FORMAT_CORRECTION` | Remove — no longer needed (was MGF-specific) |
| `XIFDR` | No change — reads CSVs, format-agnostic |
| Input validation | Replace CSV samplesheet schema with SDRF validation |

## Container Updates

The existing `ghcr.io/bigbio/relink:1.0.0` container bundles:
- xiSEARCH 1.8.11, xiFDR 2.3.10, Scout 2.0.0, .NET 9.0, Python 3.12, libmpfr

**Required update**: Bump Scout from 2.0.0 to 2.1+ (for `-no_filter` flag). This requires a new container version in `quantms-containers`.

**New dependencies** (if not already present):
- `xi-mzidentml-converter` (Python package for xiSEARCH -> mzIdentML)
- `sdrf-pipelines` (for SDRF parsing, or use separate biocontainers image)

## Test Dataset

**Dataset**: PXD042173 (DSSO crosslinked, recombinant protein standards)

**SDRF**: `https://github.com/bigbio/proteomics-sample-metadata/blob/master/examples/PXD042173/PXD042173.sdrf.tsv`

**Test subset**: 2 RAW files for fast benchmarking:
- `L1_20210727_MxR_FDR_firstbatch_DSSOplate2_B12.raw`
- `L1_20210727_MxR_FDR_firstbatch_DSSOplate2_E12.raw`

**Test scenarios:**
1. `--search_engine xisearch` with SDRF input -> xiFDR -> mzIdentML (validates migration from MGF to mzML, SDRF input)
2. `--search_engine scout` with SDRF input -> Scout FDR -> mzIdentML (validates new Scout path)
3. Compare results between engines on the same 2 files

## Issues to Create

### relink repository (GitHub)

1. **Switch spectral format from MGF to mzML** — update ThermoRawFileParser output, xiSEARCH input, mass recalibration script; remove FORMAT_CORRECTION
2. **Add SDRF input support** — SDRF_PARSING process, input validation, replace CSV samplesheet
3. **Add parameter translator** — `bin/generate_engine_config.py` for SDRF -> xiSEARCH XML / Scout JSON
4. **Add SCOUT_SEARCH module** — per-sample search with `-no_filter`
5. **Add SCOUT_FILTER module** — aggregated FDR computation
6. **Add engine-switching logic in relink.nf** — `params.search_engine` branching
7. **Add MZIDENTML_EXPORT module** — xi-mzidentml-converter for xiSEARCH, Scout native/converter
8. **Add test profile for Scout** — PXD042173 subset, 2 RAW files
9. **Publish both CSVs and mzIdentML** — dual output directories

### sdrf-pipelines repository

10. **Add `convert-relink` converter** — extract XL-MS columns (crosslinker, enrichment, distance) + standard proteomics columns

### proteomics-sample-metadata repository

11. **Validate PXD042173 SDRF for relink compatibility** — ensure all required XL-MS columns are present and correctly formatted

### quantms-containers repository

12. **Update relink container: Scout 2.0.0 -> 2.1+** — required for `-no_filter` flag
13. **Add xi-mzidentml-converter to relink container** — for mzIdentML export

## Implementation Order

1. Container update (Scout 2.1) — unblocks Scout modules
2. MGF -> mzML migration — refactor existing pipeline, validate xiSEARCH still works
3. SDRF converter in sdrf-pipelines — `convert-relink`
4. SDRF parsing + parameter translator in relink
5. SCOUT_SEARCH + SCOUT_FILTER modules
6. Engine-switching logic in relink.nf
7. MZIDENTML_EXPORT module
8. Test dataset + benchmark with PXD042173 (2 files)
9. End-to-end testing both paths

## Future Work (Out of Scope)

- Multi-engine combination (xiSEARCH + Scout together with custom FDR)
- Prosit-XL rescoring integration
- Bruker .d file support on Unix (awaiting Scout parallel version)
- Decoy database generation module (needed for multi-engine, not single-engine switching)
