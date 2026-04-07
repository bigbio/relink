process SDRF_PARSING {
    tag "sdrf_parsing"
    label 'process_single'

    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'oras://ghcr.io/bigbio/relink-sif:1.1.0' :
        'ghcr.io/bigbio/relink:1.1.0' }"

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
    printf 'filename\tsample_id\tfraction\ttechnical_replicate\turi\n' > relink_design.tsv
    printf 'stub_sample.raw\tstub_sample\t1\t1\tstub_sample.raw\n' >> relink_design.tsv
    touch xi_linear.conf
    touch xi_crosslinking.conf
    touch search_params.json
    touch filter_params.json

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        sdrf-pipelines: stub
    END_VERSIONS
    """
}
