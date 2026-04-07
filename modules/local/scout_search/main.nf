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
    def scout_cmd = task.ext.scout_cmd ?: '/opt/scout/run_scout.sh'
    """
    # Inject actual file paths into search_params.json
    python3 -c "
import json
with open('${search_params}') as f:
    p = json.load(f)
p['FastaFile'] = '${fasta}'
p['RawPath'] = '.'
p['OutputFolder'] = '.'
with open('patched_search_params.json', 'w') as f:
    json.dump(p, f, indent=2)
"

    ${scout_cmd} -search -no_filter \\
        patched_search_params.json ${filter_params} \\
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
