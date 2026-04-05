process SCOUT_SEARCH {
    tag "$meta.id"
    label 'process_high'
    label 'process_long'
    label 'error_retry'

    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'oras://ghcr.io/bigbio/relink-sif:1.1.0' :
        'ghcr.io/bigbio/relink:1.1.0' }"

    input:
    tuple val(meta), path(spectra_file)
    path search_params
    path filter_params
    path fasta

    output:
    tuple val(meta), path("*.buf"), emit: buf_files
    path "versions.yml",            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    """
    /opt/scout/run_scout.sh -search -no_filter \\
        ${search_params} ${filter_params} \\
        ${args}

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        scout: 2.1
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch '${prefix}.buf'

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        scout: 2.1
    END_VERSIONS
    """
}
