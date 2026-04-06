process SDRF_PARSING {
    tag "sdrf_parsing"
    label 'process_single'

    container 'biocontainers/sdrf-pipelines:0.1.2--pyhdfd78af_0'

    input:
    path sdrf

    output:
    path "relink_config.tsv", emit: config
    path "versions.yml",      emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    """
    parse_sdrf convert-relink -s ${sdrf} -o relink_config.tsv

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        sdrf-pipelines: \$(pip show sdrf-pipelines 2>/dev/null | grep Version | cut -d' ' -f2 || echo 'unknown')
    END_VERSIONS
    """

    stub:
    """
    touch relink_config.tsv

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        sdrf-pipelines: stub
    END_VERSIONS
    """
}
