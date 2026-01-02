//
// Subworkflow with utility functions for the Nextflow pipeline
//

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    SUBWORKFLOW DEFINITION
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow UTILS_NEXTFLOW_PIPELINE {

    take:
    print_version        // boolean: Print pipeline version
    dump_parameters      // boolean: Dump parameters to JSON
    outdir               // path: Base output directory
    check_conda_channels // boolean: Check Conda channels are correct

    main:

    //
    // Print version if required
    //
    if (print_version) {
        log.info "${workflow.manifest.name} ${getWorkflowVersion()}"
        System.exit(0)
    }

    //
    // Dump parameters to JSON
    //
    if (dump_parameters && outdir) {
        dumpParametersToJSON(outdir)
    }

    //
    // Check Conda channels are correctly configured
    //
    if (check_conda_channels) {
        checkCondaChannels()
    }
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

//
// Get workflow version
//
def getWorkflowVersion() {
    String version_string = ""
    if (workflow.manifest.version) {
        def prefix_v = workflow.manifest.version[0] != 'v' ? 'v' : ''
        version_string += "${prefix_v}${workflow.manifest.version}"
    }

    if (workflow.commitId) {
        def git_shortsha = workflow.commitId.substring(0, 7)
        version_string += "-g${git_shortsha}"
    }

    return version_string
}

//
// Dump pipeline parameters to JSON
//
def dumpParametersToJSON(outdir) {
    def timestamp  = new java.util.Date().format('yyyy-MM-dd_HH-mm-ss')
    def filename   = "params_${timestamp}.json"
    def temp_pf    = new File(workflow.launchDir.toString(), ".${filename}")
    def jsonStr    = groovy.json.JsonOutput.toJson(params)
    temp_pf.text   = groovy.json.JsonOutput.prettyPrint(jsonStr)

    nextflow.io.file.FileHelper.moveTo(
        temp_pf.toPath(),
        nextflow.io.file.FileHelper.toPath("${outdir}/pipeline_info/${filename}")
    )
}

//
// Check Conda channels are correctly configured
//
def checkCondaChannels() {
    def channels = ['conda-forge', 'bioconda', 'defaults']
    try {
        def proc = "conda config --show channels".execute()
        def stdout = new StringBuffer()
        proc.waitForProcessOutput(stdout, System.err)
        def result = stdout.toString()
        for (channel in channels) {
            if (!result.contains(channel)) {
                log.warn "Channel '${channel}' not found in Conda configuration"
            }
        }
    } catch (Exception e) {
        log.debug "Could not check Conda channels: ${e.message}"
    }
}


