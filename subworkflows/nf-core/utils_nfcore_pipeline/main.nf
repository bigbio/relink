//
// Subworkflow with utility functions specific to the nf-core pipeline template
//

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    SUBWORKFLOW DEFINITION
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow UTILS_NFCORE_PIPELINE {

    take:
    help
    workflow_command
    pre_help_text
    post_help_text
    validate_params
    schema_filename

    main:
    def valid_config = true

    //
    // Print help message if required
    //
    if (help) {
        log.info pre_help_text + paramsHelp(workflow_command, parameters_schema: schema_filename) + post_help_text
        System.exit(0)
    }

    //
    // Print parameter summary log to screen
    //
    log.info paramsSummaryLog(workflow, parameters_schema: schema_filename)

    //
    // Validate parameters
    //
    if (validate_params) {
        validateParameters(parameters_schema: schema_filename)
    }

    emit:
    valid_config
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

//
// Generate methods description for MultiQC
//
def methodsDescriptionText(mqc_methods_yaml) {
    def meta = [:]
    meta.workflow = workflow.manifest
    meta["manifest_map"] = workflow.manifest.toMap()

    def yaml_file = file(mqc_methods_yaml)
    def methods_text = ""
    if (yaml_file.exists()) {
        methods_text = yaml_file.text
    }

    def String return_text = methods_text
    return return_text
}

//
// Generate parameter summary string for MultiQC
//
def paramsSummaryMultiqc(summary_params) {
    def summary_section = ''
    for (group in summary_params.keySet()) {
        def group_params = summary_params.get(group)
        if (group_params) {
            summary_section += "    <p style=\"font-size:110%\"><b>$group</b></p>\n"
            summary_section += "    <dl class=\"dl-horizontal\">\n"
            for (param in group_params.keySet()) {
                summary_section += "        <dt>$param</dt><dd><samp>${group_params.get(param) ?: '<span style=\"color:#999999;\">N/A</a>'}</samp></dd>\n"
            }
            summary_section += "    </dl>\n"
        }
    }

    String yaml_file_text  = "id: '${workflow.manifest.name.replace('/','-')}-summary'\n"
    yaml_file_text        += "description: ' - this information is collected when the pipeline is started.'\n"
    yaml_file_text        += "section_name: '${workflow.manifest.name} Workflow Summary'\n"
    yaml_file_text        += "section_href: 'https://github.com/${workflow.manifest.name}'\n"
    yaml_file_text        += "plot_type: 'html'\n"
    yaml_file_text        += "data: |\n"
    yaml_file_text        += "${summary_section}"
    return yaml_file_text
}

//
// Collect software versions and convert to YAML
//
def softwareVersionsToYAML(ch_versions) {
    return ch_versions
        .unique()
        .map { processVersions(it) }
        .unique()
        .map { yaml -> yaml.trim() }
        .collectFile(name: 'versions.yml', newLine: true, sort: true)
}

//
// Process version information
//
def processVersions(version_yaml) {
    return version_yaml
}

//
// Generate completion email text
//
def completionEmail(summary_params, email, email_on_fail, plaintext_email, outdir, monochrome_logs, multiqc_report) {
    def output_dir = new File("${outdir}")
    def output_files = output_dir.exists() ? output_dir.list() : []

    // Set up the e-mail variables
    def subject = "[bigbio/relink] Successful: ${workflow.runName}"
    if (!workflow.success) {
        subject = "[bigbio/relink] FAILED: ${workflow.runName}"
    }

    def email_fields = [:]
    email_fields['version'] = workflow.manifest.version
    email_fields['runName'] = workflow.runName
    email_fields['success'] = workflow.success
    email_fields['dateComplete'] = workflow.complete
    email_fields['duration'] = workflow.duration
    email_fields['exitStatus'] = workflow.exitStatus
    email_fields['errorMessage'] = (workflow.errorMessage ?: 'None')
    email_fields['errorReport'] = (workflow.errorReport ?: 'None')
    email_fields['commandLine'] = workflow.commandLine
    email_fields['projectDir'] = workflow.projectDir
    email_fields['script'] = workflow.scriptFile
    email_fields['launchDir'] = workflow.launchDir
    email_fields['workDir'] = workflow.workDir
    email_fields['userName'] = workflow.userName
    email_fields['pipeline'] = workflow.manifest.name
    email_fields['homeDir'] = workflow.homeDir
    email_fields['sessionId'] = workflow.sessionId
    email_fields['summary'] = summary_params
}

//
// Generate completion summary
//
def completionSummary(monochrome_logs) {
    def summary_section = ''
    if (workflow.success) {
        if (workflow.stats.ignoredCount > 0) {
            summary_section = "-${colors(monochrome_logs).purple}Warning, pipeline completed, but with errored process(es)${colors(monochrome_logs).reset}-"
        } else {
            summary_section = "-${colors(monochrome_logs).green}Pipeline completed successfully${colors(monochrome_logs).reset}-"
        }
    } else {
        summary_section = "-${colors(monochrome_logs).red}Pipeline completed with errors${colors(monochrome_logs).reset}-"
    }

    log.info summary_section
}

//
// Generate IM notification
//
def imNotification(summary_params, hook_url) {
    // Placeholder for IM notification functionality
}

//
// Generate nf-core logo
//
def nfCoreLogo(monochrome_logs) {
    Map colors = colors(monochrome_logs)
    String.format(
        """\n
        ${colors.blue}  ____  _       _     _       ${colors.reset}
        ${colors.blue} | __ )(_) __ _| |__ (_) ___  ${colors.reset}
        ${colors.blue} |  _ \\| |/ _` | '_ \\| |/ _ \\ ${colors.reset}
        ${colors.blue} | |_) | | (_| | |_) | | (_) |${colors.reset}
        ${colors.blue} |____/|_|\\__, |_.__/|_|\\___/ ${colors.reset}
        ${colors.blue}          |___/               ${colors.reset}
        ${colors.purple}  bigbio/relink v${workflow.manifest.version}${colors.reset}
        """.stripIndent()
    )
}

//
// Generate dashed line
//
def dashedLine(monochrome_logs) {
    Map colors = colors(monochrome_logs)
    return "-${colors.dim}-------------------------------------------------------${colors.reset}-"
}

//
// ANSI colors
//
def colors(monochrome_logs) {
    Map colorcodes = [:]
    colorcodes['reset']       = monochrome_logs ? '' : "\033[0m"
    colorcodes['dim']         = monochrome_logs ? '' : "\033[2m"
    colorcodes['black']       = monochrome_logs ? '' : "\033[0;30m"
    colorcodes['green']       = monochrome_logs ? '' : "\033[0;32m"
    colorcodes['yellow']      = monochrome_logs ? '' : "\033[0;33m"
    colorcodes['blue']        = monochrome_logs ? '' : "\033[0;34m"
    colorcodes['purple']      = monochrome_logs ? '' : "\033[0;35m"
    colorcodes['cyan']        = monochrome_logs ? '' : "\033[0;36m"
    colorcodes['white']       = monochrome_logs ? '' : "\033[0;37m"
    colorcodes['red']         = monochrome_logs ? '' : "\033[0;31m"
    return colorcodes
}


