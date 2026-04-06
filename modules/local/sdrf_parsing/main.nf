process SDRF_PARSING {
    tag "sdrf_parsing"
    label 'process_single'

    container 'biocontainers/sdrf-pipelines:0.1.2--pyhdfd78af_0'

    input:
    path sdrf
    val search_engine

    output:
    path "relink_design.tsv", emit: design
    path "xi_linear.conf",    emit: xi_linear_config, optional: true
    path "xi_crosslinking.conf", emit: xi_crosslink_config, optional: true
    path "search_params.json", emit: scout_search_params, optional: true
    path "filter_params.json", emit: scout_filter_params, optional: true
    path "versions.yml",       emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    """
    parse_sdrf convert-relink -s ${sdrf} -e ${search_engine}

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        sdrf-pipelines: \$(pip show sdrf-pipelines 2>/dev/null | grep Version | cut -d' ' -f2 || echo 'unknown')
    END_VERSIONS
    """

    stub:
    """
    touch relink_design.tsv
    touch xi_linear.conf
    touch xi_crosslinking.conf

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        sdrf-pipelines: stub
    END_VERSIONS
    """
}
