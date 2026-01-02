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
    ch_samplesheet // channel: [ val(meta), path(file), path(fasta), path(linear_config), path(crosslink_config) ]

    main:

    ch_versions = Channel.empty()
    ch_multiqc_files = Channel.empty()

    //
    // Prepare input channels
    //
    ch_samplesheet
        .map { meta, file, fasta, linear_config, crosslink_config ->
            [ meta, file ]
        }
        .branch {
            raw: it[1].name.toLowerCase().endsWith('.raw')
            mgf: it[1].name.toLowerCase().endsWith('.mgf')
        }
        .set { ch_input_by_type }

    // Get FASTA and configs from first row (assumed same for all samples)
    ch_fasta = ch_samplesheet.map { meta, file, fasta, linear_config, crosslink_config -> fasta }.first()
    ch_linear_config = ch_samplesheet.map { meta, file, fasta, linear_config, crosslink_config -> linear_config }.first()
    ch_crosslink_config = ch_samplesheet.map { meta, file, fasta, linear_config, crosslink_config -> crosslink_config }.first()

    // =========================================================================
    // STEP 1: File Conversion (RAW → MGF)
    // =========================================================================

    //
    // MODULE: Convert RAW files to MGF format
    //
    THERMORAWFILEPARSER (
        ch_input_by_type.raw
    )
    ch_versions = ch_versions.mix(THERMORAWFILEPARSER.out.versions.first())

    // Combine converted MGF with input MGF files
    ch_mgf = THERMORAWFILEPARSER.out.convert_files
        .mix(ch_input_by_type.mgf)

    // =========================================================================
    // STEP 2: Linear Search (for mass recalibration)
    // =========================================================================

    if (params.do_recalibration) {

        //
        // MODULE: Run xiSEARCH linear search
        //
        XISEARCH_LINEAR (
            ch_mgf,
            ch_fasta,
            ch_linear_config,
            'linear'
        )
        ch_versions = ch_versions.mix(XISEARCH_LINEAR.out.versions.first())

        // =====================================================================
        // STEP 3: Mass Recalibration
        // =====================================================================

        // Prepare input for recalibration: join linear results with original MGF
        ch_for_recal = XISEARCH_LINEAR.out.results
            .join(XISEARCH_LINEAR.out.peaks)
            .join(ch_mgf)

        //
        // MODULE: Calculate mass error and recalibrate MGF files
        //
        MASS_RECALIBRATION (
            ch_for_recal,
            params.do_mass_error_plots
        )
        ch_versions = ch_versions.mix(MASS_RECALIBRATION.out.versions.first())

        ch_mgf_for_crosslink = MASS_RECALIBRATION.out.mgf

    } else {
        ch_mgf_for_crosslink = ch_mgf
    }

    // =========================================================================
    // STEP 4: Crosslinking Search
    // =========================================================================

    if (params.do_crosslinking_search) {

        //
        // MODULE: Run xiSEARCH crosslinking search
        //
        XISEARCH_CROSSLINK (
            ch_mgf_for_crosslink,
            ch_fasta,
            ch_crosslink_config,
            'crosslink'
        )
        ch_versions = ch_versions.mix(XISEARCH_CROSSLINK.out.versions.first())

        ch_crosslink_results = XISEARCH_CROSSLINK.out.results

        // =====================================================================
        // STEP 5: FDR Correction
        // =====================================================================

        if (params.do_fdr) {

            //
            // MODULE: Run xiFDR for FDR correction
            //
            XIFDR (
                ch_crosslink_results.map { meta, csv -> csv }.collect(),
                ch_fasta,
                ch_crosslink_config,
                params.link_fdr
            )
            ch_versions = ch_versions.mix(XIFDR.out.versions.first())
        }
    }

    // =========================================================================
    // STEP 6: Reporting
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


