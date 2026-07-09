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
    path "output/*.csv",   emit: results
    path "output/*.scout", emit: scout_file
    path "versions.yml",   emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def scout_cmd = task.ext.scout_cmd ?: '/opt/scout/run_scout.sh'
    """
    mkdir -p output

    ${scout_cmd} -filter \\
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
    touch 'output/results.scout'

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        scout: 2.1
    END_VERSIONS
    """
}
