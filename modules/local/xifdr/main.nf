process XIFDR {
    tag "fdr_correction"
    label 'process_high'
    label 'error_retry'

    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'oras://ghcr.io/bigbio/relink-sif:1.0.0' :
        'ghcr.io/bigbio/relink:1.0.0' }"

    input:
    path crosslink_results  // Collected from all samples
    path fasta
    path config
    val link_fdr

    output:
    path "fdr_*.csv", emit: results
    path "versions.yml", emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def mem = task.memory.toGiga()
    def input_files = crosslink_results.collect { "'${it}'" }.join(' ')
    """
    java -Xmx${mem}g -jar /opt/xisearch/xiFDR.jar \\
        --fasta='${fasta}' \\
        --xiconfig='${config}' \\
        --linkfdr=${link_fdr} \\
        --xiversion=1.8.11 \\
        --csvOutDir=./ \\
        --csvOutBaseName=fdr_ \\
        ${args} \\
        ${input_files}

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        xiFDR: 2.3.10
        java: \$(java -version 2>&1 | head -1 | cut -d'"' -f2)
    END_VERSIONS
    """

    stub:
    """
    touch 'fdr_results.csv'

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        xiFDR: 2.3.10
        java: stub
    END_VERSIONS
    """
}


