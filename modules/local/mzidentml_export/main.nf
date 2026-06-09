process MZIDENTML_EXPORT {
    tag "mzidentml_export"
    label 'process_medium'

    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'oras://ghcr.io/bigbio/relink-sif:1.1.0' :
        'ghcr.io/bigbio/relink:1.1.0' }"

    input:
    path fdr_results

    output:
    path "results.mzid", emit: mzidentml
    path "versions.yml", emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    """
    process_dataset \\
        --validate ${fdr_results} \\
		--no-peak-list \\
        ${args} > results.mzid

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        xi-mzidentml-converter: \$(pip show xi-mzidentml-converter 2>/dev/null | grep Version | cut -d' ' -f2 || echo 'unknown')
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
