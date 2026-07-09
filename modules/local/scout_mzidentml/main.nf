process SCOUT_MZIDENTML {
    tag "scout_mzidentml"
    label 'process_medium'

    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'oras://ghcr.io/bigbio/relink-sif:1.1.0' :
        'ghcr.io/bigbio/relink:1.1.0' }"

    input:
    path scout_file
    path spectra_files

    output:
    path "*.mzid",     emit: mzidentml
    path "*-specID.ms2", optional: true, emit: specid
    path "versions.yml", emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def version = task.ext.mzidentml_version ?: '1.3'
    def scout_cmd = task.ext.scout_cmd ?: '/opt/scout/run_scout.sh'
    """
    mkdir -p raws
    for f in *.mzML *.mzml; do
        [ -e "\$f" ] && ln -s "\$(pwd)/\$f" raws/
    done

    ${scout_cmd} -mzid \\
        -v ${version} \\
        -i ${scout_file} \\
        -raws raws/ \\
        -o results.mzid \\
        ${args}

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        scout: 2.1
    END_VERSIONS
    """

    stub:
    """
    touch results.mzid

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        scout: 2.1
    END_VERSIONS
    """
}
