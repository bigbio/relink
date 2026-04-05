process SCOUT_FILTER {
    tag "scout_fdr"
    label 'process_high'
    label 'error_retry'

    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'oras://ghcr.io/bigbio/relink-sif:1.1.0' :
        'ghcr.io/bigbio/relink:1.1.0' }"

    input:
    path buf_files
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
