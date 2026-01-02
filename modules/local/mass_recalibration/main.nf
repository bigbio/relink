process MASS_RECALIBRATION {
    tag "$meta.id"
    label 'process_medium'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'oras://ghcr.io/bigbio/relink-sif:1.0.0' :
        'ghcr.io/bigbio/relink:1.0.0' }"

    input:
    tuple val(meta), path(linear_results), path(peaks_file), path(mgf_file)
    val do_plotting

    output:
    tuple val(meta), path("recal_*.mgf"), emit: mgf
    tuple val(meta), path("mass_error_*.csv"), emit: error_report
    tuple val(meta), path("*.png"), optional: true, emit: plots
    path "versions.yml", emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    def plot_flag = do_plotting ? "--plot" : ""
    """
    recalibrate_mgf.py \\
        --linear-results '${linear_results}' \\
        --peaks '${peaks_file}' \\
        --mgf '${mgf_file}' \\
        --output 'recal_${prefix}.mgf' \\
        --error-report 'mass_error_${prefix}.csv' \\
        --prefix '${prefix}' \\
        ${plot_flag} \\
        ${args}

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: \$(python --version | sed 's/Python //g')
        pyopenms: \$(python -c "import pyopenms; print(pyopenms.__version__)")
        polars: \$(python -c "import polars; print(polars.__version__)")
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch 'recal_${prefix}.mgf'
    touch 'mass_error_${prefix}.csv'

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: stub
        pyopenms: stub
        polars: stub
    END_VERSIONS
    """
}

