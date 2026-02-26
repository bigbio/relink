process FORMAT_CORRECTION {
    tag "$meta.id"
    label 'process_light'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'oras://ghcr.io/bigbio/relink-sif:1.0.0' :
        'ghcr.io/bigbio/relink:1.0.0' }"

    input:
    tuple val(meta), path(mgf_file)

    output:
    tuple val(meta), path("reformatted_*.mgf"), emit: mgf
    path "versions.yml", emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    python ${projectDir}/bin/format_correction.py \\
        --mgf '${mgf_file}' \\
        --output 'reformatted_${prefix}.mgf'

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: \$(python --version | sed 's/Python //g')
    END_VERSIONS
    """
}
