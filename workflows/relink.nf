/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT MODULES / SUBWORKFLOWS / FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

include { THERMORAWFILEPARSER           } from '../modules/bigbio/thermorawfileparser/main'
include { XISEARCH as XISEARCH_LINEAR   } from '../modules/local/xisearch/main'
include { XISEARCH as XISEARCH_CROSSLINK } from '../modules/local/xisearch/main'
include { MASS_RECALIBRATION            } from '../modules/local/mass_recalibration/main'
include { XIFDR                         } from '../modules/local/xifdr/main'
include { SCOUT_SEARCH                  } from '../modules/local/scout_search/main'
include { SCOUT_FILTER                  } from '../modules/local/scout_filter/main'
include { SCOUT_MZIDENTML               } from '../modules/local/scout_mzidentml/main'
include { MZIDENTML_EXPORT              } from '../modules/local/mzidentml_export/main'
include { PMULTIQC                      } from '../modules/bigbio/pmultiqc/main'
include { paramsSummaryMap              } from 'plugin/nf-validation'
include { paramsSummaryMultiqc          } from '../subworkflows/nf-core/utils_nfcore_pipeline'
include { softwareVersionsToYAML        } from '../subworkflows/nf-core/utils_nfcore_pipeline'

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    RUN MAIN WORKFLOW
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow RELINK {

    take:
    ch_files               // channel: [ val(meta), path(file) ]
    ch_linear_config       // channel: path(xi_linear.conf)
    ch_crosslink_config    // channel: path(xi_crosslinking.conf)
    ch_scout_search_params // channel: path(search_params.json)
    ch_scout_filter_params // channel: path(filter_params.json)

    main:

    ch_versions = Channel.empty()
    ch_multiqc_files = Channel.empty()

    //
    // Resolve FASTA from params
    //
    ch_fasta = Channel.fromPath(params.fasta, checkIfExists: true).first()

    //
    // Branch input files by type: RAW files need conversion, mzML pass through
    //
    ch_files
        .branch {
            raw: it[1].name.toLowerCase().endsWith('.raw')
            mzml: it[1].name.toLowerCase().endsWith('.mzml')
        }
        .set { ch_input_by_type }

    // =========================================================================
    // STEP 1: File Conversion (RAW → mzML)
    // =========================================================================

    //
    // MODULE: Convert RAW files to mzML format
    //
    THERMORAWFILEPARSER (
        ch_input_by_type.raw
    )
    ch_versions = ch_versions.mix(THERMORAWFILEPARSER.out.versions.first())

    // Combine converted mzML with input mzML files
    ch_mzml = THERMORAWFILEPARSER.out.convert_files
        .mix(ch_input_by_type.mzml)

    // =========================================================================
    // STEP 2: Search Engine Branch
    // =========================================================================

    if (params.search_engine == 'xisearch') {

        // =================================================================
        // xiSEARCH path
        // =================================================================

        // Collect configs (single value channels)
        ch_xi_linear = ch_linear_config.first()
        ch_xi_crosslink = ch_crosslink_config.first()

        // -----------------------------------------------------------------
        // Linear Search (for mass recalibration)
        // -----------------------------------------------------------------

        if (params.do_recalibration) {

            //
            // MODULE: Run xiSEARCH linear search
            //
            XISEARCH_LINEAR (
                ch_mzml,
                ch_fasta,
                ch_xi_linear,
                'linear'
            )
            ch_versions = ch_versions.mix(XISEARCH_LINEAR.out.versions.first())

            // Prepare input for recalibration: join linear results with original mzML
            ch_for_recal = XISEARCH_LINEAR.out.results
                .join(XISEARCH_LINEAR.out.peaks)
                .join(ch_mzml)

            //
            // MODULE: Calculate mass error and recalibrate spectra files
            //
            MASS_RECALIBRATION (
                ch_for_recal,
                params.do_mass_error_plots
            )
            ch_versions = ch_versions.mix(MASS_RECALIBRATION.out.versions.first())

            ch_mzml_for_crosslink = MASS_RECALIBRATION.out.mzml

        } else {
            ch_mzml_for_crosslink = ch_mzml
        }

        // -----------------------------------------------------------------
        // Crosslinking Search
        // -----------------------------------------------------------------

        if (params.do_crosslinking_search) {

            //
            // MODULE: Run xiSEARCH crosslinking search
            //
            XISEARCH_CROSSLINK (
                ch_mzml_for_crosslink,
                ch_fasta,
                ch_xi_crosslink,
                'crosslink'
            )
            ch_versions = ch_versions.mix(XISEARCH_CROSSLINK.out.versions.first())

            ch_crosslink_results = XISEARCH_CROSSLINK.out.results

            // ---------------------------------------------------------
            // FDR Correction
            // ---------------------------------------------------------

            if (params.do_fdr) {

                //
                // MODULE: Run xiFDR for FDR correction
                //
                XIFDR (
                    ch_crosslink_results.map { meta, csv -> csv }.collect(),
                    ch_fasta,
                    ch_xi_crosslink,
                    params.link_fdr
                )
                ch_versions = ch_versions.mix(XIFDR.out.versions.first())

                //
                // MODULE: Export xiFDR results to mzIdentML
                //
                MZIDENTML_EXPORT (
                    XIFDR.out.results,
                    ch_fasta
                )
                ch_versions = ch_versions.mix(MZIDENTML_EXPORT.out.versions.first())
            }
        }

    } else if (params.search_engine == 'scout') {

        // =================================================================
        // Scout path
        // =================================================================

        ch_search_params = ch_scout_search_params.first()
        ch_filter_params = ch_scout_filter_params.first()

        //
        // MODULE: Run Scout crosslink search (per-sample, -no_filter)
        //
        SCOUT_SEARCH (
            ch_mzml,
            ch_search_params,
            ch_filter_params,
            ch_fasta
        )
        ch_versions = ch_versions.mix(SCOUT_SEARCH.out.versions.first())

        // -----------------------------------------------------------------
        // Scout FDR filtering (aggregated across all samples)
        // -----------------------------------------------------------------

        if (params.do_fdr) {

            //
            // MODULE: Run Scout FDR filtering
            //
            SCOUT_FILTER (
                SCOUT_SEARCH.out.buf_files.map { meta, buf -> buf }.collect(),
                ch_filter_params,
                ch_fasta
            )
            ch_versions = ch_versions.mix(SCOUT_FILTER.out.versions.first())

            //
            // MODULE: Export Scout results to mzIdentML 1.3 (native Scout CLI)
            //
            SCOUT_MZIDENTML (
                SCOUT_FILTER.out.scout_file,
                ch_mzml.map { meta, mzml -> mzml }.collect()
            )
            ch_versions = ch_versions.mix(SCOUT_MZIDENTML.out.versions.first())
        }

    } else {
        error "Unknown search_engine: '${params.search_engine}'. Supported values: 'xisearch', 'scout'."
    }

    // =========================================================================
    // STEP 3: Reporting
    // =========================================================================

    //
    // Collate and save software versions
    //
    softwareVersionsToYAML(ch_versions)
        .collectFile(
            storeDir: "${params.outdir}/pipeline_info",
            name: 'nf_core_pipeline_software_mqc_versions.yml',
            sort: true,
            newLine: true
        ).set { ch_collated_versions }

    //
    // MODULE: MultiQC
    //
    ch_multiqc_config        = Channel.fromPath("$projectDir/assets/multiqc_config.yml", checkIfExists: false)
    ch_multiqc_custom_config = params.multiqc_config ? Channel.fromPath(params.multiqc_config, checkIfExists: true) : Channel.empty()
    ch_multiqc_logo          = params.multiqc_logo   ? Channel.fromPath(params.multiqc_logo, checkIfExists: true)   : Channel.empty()

    summary_params      = paramsSummaryMap(workflow, parameters_schema: "nextflow_schema.json")
    ch_workflow_summary = Channel.value(paramsSummaryMultiqc(summary_params))

    ch_multiqc_custom_methods_description = params.multiqc_methods_description ? file(params.multiqc_methods_description, checkIfExists: true) : file("$projectDir/assets/methods_description_template.yml", checkIfExists: false)
    ch_methods_description                = Channel.value(ch_multiqc_custom_methods_description)

    ch_multiqc_files = ch_multiqc_files.mix(ch_workflow_summary.collectFile(name: 'workflow_summary_mqc.yaml'))
    ch_multiqc_files = ch_multiqc_files.mix(ch_collated_versions)

    PMULTIQC (
        [ id: 'relink' ],
        ch_multiqc_files.collect()
    )
    ch_multiqc_report = PMULTIQC.out.report.map { meta, report -> report }
    ch_versions = ch_versions.mix(PMULTIQC.out.versions)

    emit:
    multiqc_report = ch_multiqc_report // channel: /path/to/multiqc_report.html
    versions       = ch_versions       // channel: [ path(versions.yml) ]
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    THE END
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
