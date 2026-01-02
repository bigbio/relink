process XISEARCH {
    tag "$meta.id"
    label 'process_high'
    label 'process_long'
    label 'error_retry'

    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'oras://ghcr.io/bigbio/relink-sif:1.0.0' :
        'ghcr.io/bigbio/relink:1.0.0' }"

    input:
    tuple val(meta), path(mgf_file)
    path fasta
    path config
    val mode  // 'linear' or 'crosslink'

    output:
    tuple val(meta), path("*_${mode}.csv"), emit: results
    tuple val(meta), path("*_${mode}.peaks.{tsv,csv}"), emit: peaks
    path "versions.yml", emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    def mem = task.memory.toGiga()
    def peaks_ext = mode == 'linear' ? 'tsv' : 'csv'
    """
    java -Xmx${mem}g -jar /opt/xisearch/xiSEARCH.jar \\
        --fasta='${fasta}' \\
        --xiconf=UseCPUs:${task.cpus} \\
        --peaks='${mgf_file}' \\
        --config='${config}' \\
        --output='${prefix}_${mode}.csv' \\
        --peaksout='${prefix}_${mode}.peaks.${peaks_ext}' \\
        ${args}

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        xiSEARCH: 1.8.11
        java: \$(java -version 2>&1 | head -1 | cut -d'"' -f2)
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    def peaks_ext = mode == 'linear' ? 'tsv' : 'csv'
    """
    touch '${prefix}_${mode}.csv'
    touch '${prefix}_${mode}.peaks.${peaks_ext}'

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        xiSEARCH: 1.8.11
        java: stub
    END_VERSIONS
    """
}
