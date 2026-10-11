process CALL_ANCESTRY {
    tag "${meta.id}"
    label 'process_single'

    // nilHMM is not on conda: built from containers/nilhmm/Dockerfile
    container 'ghcr.io/sawers-rellan-labs/zealgt-nilhmm:0.3.1-1'

    input:
    tuple val(meta), path(markers), path(counts, stageAs: 'counts/*')
    path tool

    output:
    tuple val(meta), path("${prefix}.segments.bed"), emit: segments
    tuple val(meta), path("${prefix}.dropped_lines.tsv"), emit: dropped
    tuple val(meta), path("${prefix}.line_checks.tsv"), emit: line_checks
    tuple val("${task.process}"), val('nilHMM'), eval("Rscript -e 'cat(as.character(packageVersion(\"nilHMM\")))'"), topic: versions, emit: versions_nilhmm

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    prefix = task.ext.prefix ?: "${meta.id}"
    // the tool is a path input, so an edit to it reruns the task (docs/running.md)
    """
    Rscript ${tool} --markers ${markers} --counts ${counts} \\
        --segments ${prefix}.segments.bed --dropped ${prefix}.dropped_lines.tsv --line-checks ${prefix}.line_checks.tsv ${args}
    """

    stub:
    prefix = task.ext.prefix ?: "${meta.id}"
    """
    printf '#chrom\\tstart\\tend\\tline\\tstate\\n' > ${prefix}.segments.bed
    printf 'line\\tcovered_markers\\tcut\\n' > ${prefix}.dropped_lines.tsv
    printf 'line\\tn_donor_segments\\tdonor_bp\\tref_reads\\tref_alt_pct\\thet_reads\\thet_alt_pct\\talt_reads\\talt_alt_pct\\n' > ${prefix}.line_checks.tsv
    """
}
