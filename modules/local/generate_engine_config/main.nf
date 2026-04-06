process GENERATE_ENGINE_CONFIG {
    tag "generate_config"
    label 'process_single'

    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'oras://ghcr.io/bigbio/relink-sif:1.1.0' :
        'ghcr.io/bigbio/relink:1.1.0' }"

    input:
    path relink_config
    val search_engine
    path custom_config

    output:
    path "*.conf", emit: xisearch_configs, optional: true
    path "*.json", emit: scout_configs, optional: true
    path "versions.yml", emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def override = custom_config.name != 'NO_FILE' ? "--override ${custom_config}" : ''
    """
    python ${projectDir}/bin/generate_engine_config.py \\
        --config ${relink_config} \\
        --engine ${search_engine} \\
        --output-prefix generated \\
        ${override}

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        generate_engine_config: 1.0.0
    END_VERSIONS
    """

    stub:
    """
    touch generated_linear.conf
    touch generated_crosslinking.conf

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        generate_engine_config: stub
    END_VERSIONS
    """
}
