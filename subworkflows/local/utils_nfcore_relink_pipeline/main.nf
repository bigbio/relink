//
// Subworkflow with functionality specific to the bigbio/relink pipeline
//

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT FUNCTIONS / MODULES / SUBWORKFLOWS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

include { paramsSummaryLog; paramsSummaryMap  } from 'plugin/nf-validation'
include { UTILS_NFCORE_PIPELINE     } from '../../nf-core/utils_nfcore_pipeline'
include { completionEmail           } from '../../nf-core/utils_nfcore_pipeline'
include { completionSummary         } from '../../nf-core/utils_nfcore_pipeline'
include { dashedLine                } from '../../nf-core/utils_nfcore_pipeline'
include { nfCoreLogo                } from '../../nf-core/utils_nfcore_pipeline'
include { imNotification            } from '../../nf-core/utils_nfcore_pipeline'
include { UTILS_NEXTFLOW_PIPELINE   } from '../../nf-core/utils_nextflow_pipeline'
include { SDRF_PARSING              } from '../../../modules/local/sdrf_parsing/main'

/*
========================================================================================
    SUBWORKFLOW TO INITIALISE PIPELINE
========================================================================================
*/

workflow PIPELINE_INITIALISATION {

    take:
    version           // boolean: Display version and exit
    help              // boolean: Display help text
    validate_params   // boolean: Boolean whether to validate parameters against the schema at runtime
    monochrome_logs   // boolean: Do not use coloured log outputs
    nextflow_cli_args //   array: List of positional nextflow CLI args
    outdir            //  string: The output directory where the results will be saved

    main:

    ch_versions = channel.empty()

    //
    // Print version and exit if required and dump pipeline parameters to JSON file
    //
    UTILS_NEXTFLOW_PIPELINE (
        version,
        true,
        outdir,
        workflow.profile.tokenize(',').intersect(['conda', 'mamba']).size() >= 1
    )

    //
    // Validate parameters and generate parameter summary to stdout
    //
    pre_help_text = nfCoreLogo(monochrome_logs)
    post_help_text = '\n' + dashedLine(monochrome_logs)
    def String workflow_command = "nextflow run ${workflow.manifest.name} -profile <docker/singularity/.../institute> --input sdrf.tsv --fasta database.fasta --outdir <OUTDIR>"
    UTILS_NFCORE_PIPELINE (
        help,
        workflow_command,
        pre_help_text,
        post_help_text,
        validate_params,
        "nextflow_schema.json"
    )

    //
    // Check config provided to the pipeline
    //
    UTILS_NFCORE_PIPELINE.out.valid_config
        .set { valid_config }

    //
    // Validate required parameters
    //
    if (!params.input) {
        error("Please provide an SDRF file to the pipeline e.g. '--input sdrf.tsv'")
    }
    if (!params.fasta) {
        error("Please provide a FASTA database e.g. '--fasta database.fasta'")
    }

    //
    // MODULE: Parse SDRF to generate design TSV and engine-specific configs
    //
    ch_sdrf = channel.fromPath(params.input, checkIfExists: true)

    SDRF_PARSING (
        ch_sdrf,
        params.search_engine
    )
    ch_versions = ch_versions.mix(SDRF_PARSING.out.versions)

    //
    // Build per-file channel from relink_design.tsv
    // Columns: filename, sample_id, fraction, technical_replicate, uri
    //
    SDRF_PARSING.out.design
        .splitCsv(header: true, sep: '\t')
        .map { row ->
            def filename = row.filename
            def sample_id = row.sample_id ?: filename.take(filename.lastIndexOf('.'))

            // Resolve file path: root_folder + filename, or URI from SDRF
            def filestr
            if (params.root_folder) {
                filestr = "${params.root_folder}/${filename}"
            } else if (row.uri) {
                filestr = row.uri
            } else {
                error("No root_folder provided and no URI found in SDRF for file: ${filename}")
            }

            def meta = [id: sample_id]
            return [ meta, file(filestr) ]
        }
        .set { ch_files }

    //
    // Resolve engine configs: use param overrides if provided, otherwise SDRF-generated
    //
    if (params.search_engine == 'xisearch') {
        ch_linear_config = params.xi_linear_config
            ? channel.fromPath(params.xi_linear_config, checkIfExists: true)
            : SDRF_PARSING.out.xi_linear_config
        ch_crosslink_config = params.xi_crosslink_config
            ? channel.fromPath(params.xi_crosslink_config, checkIfExists: true)
            : SDRF_PARSING.out.xi_crosslink_config
    } else {
        ch_linear_config = channel.empty()
        ch_crosslink_config = channel.empty()
    }

    if (params.search_engine == 'scout') {
        ch_scout_search_params = params.scout_search_params
            ? channel.fromPath(params.scout_search_params, checkIfExists: true)
            : SDRF_PARSING.out.scout_search_params
        ch_scout_filter_params = params.scout_filter_params
            ? channel.fromPath(params.scout_filter_params, checkIfExists: true)
            : SDRF_PARSING.out.scout_filter_params
    } else {
        ch_scout_search_params = channel.empty()
        ch_scout_filter_params = channel.empty()
    }

    emit:
    ch_files             = ch_files              // channel: [ val(meta), path(file) ]
    ch_linear_config     = ch_linear_config      // channel: path(xi_linear.conf)
    ch_crosslink_config  = ch_crosslink_config   // channel: path(xi_crosslinking.conf)
    ch_scout_search_params = ch_scout_search_params // channel: path(search_params.json)
    ch_scout_filter_params = ch_scout_filter_params // channel: path(filter_params.json)
    versions             = ch_versions           // channel: [ path(versions.yml) ]
}

/*
========================================================================================
    SUBWORKFLOW FOR PIPELINE COMPLETION
========================================================================================
*/

workflow PIPELINE_COMPLETION {

    take:
    email           //  string: email address
    email_on_fail   //  string: email address sent on pipeline failure
    plaintext_email // boolean: Send plain-text email instead of HTML
    outdir          //    path: Path to output directory where results will be published
    monochrome_logs // boolean: Disable ANSI colour codes in log output
    hook_url        //  string: hook URL for notifications
    multiqc_report  //  string: Path to MultiQC report

    main:

    summary_params = paramsSummaryMap(workflow, parameters_schema: "nextflow_schema.json")

    //
    // Completion email and summary
    //
    workflow.onComplete {
        if (email || email_on_fail) {
            completionEmail(summary_params, email, email_on_fail, plaintext_email, outdir, monochrome_logs, multiqc_report.toList())
        }

        completionSummary(monochrome_logs)

        if (hook_url) {
            imNotification(summary_params, hook_url)
        }
    }

    workflow.onError {
        log.error "Pipeline failed. Please refer to troubleshooting docs: https://nf-co.re/docs/usage/troubleshooting"
    }
}
