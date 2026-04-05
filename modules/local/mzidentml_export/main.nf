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
