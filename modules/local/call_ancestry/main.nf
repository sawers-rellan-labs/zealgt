process CALL_ANCESTRY {
    tag "${meta.id}"
    label 'process_single'

    // nilHMM is not on conda: built from containers/nilhmm/Dockerfile
    container 'ghcr.io/sawers-rellan-labs/zealgt-nilhmm:0.3.1-1'

    input:
    tuple val(meta), path(tier_a), path(counts, stageAs: 'counts/*')
    path tool

    output:
    tuple val(meta), path("${prefix}.segments.bed"), emit: segments
    tuple val(meta), path("${prefix}.dropped_lines.tsv"), emit: dropped
    tuple val("${task.process}"), val('nilHMM'), eval("Rscript -e 'cat(as.character(packageVersion(\"nilHMM\")))'"), topic: versions, emit: versions_nilhmm

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    prefix = task.ext.prefix ?: "${meta.id}"
    // the tool is a path input, so an edit to it reruns the task (docs/running.md)
    """
    Rscript ${tool} --tier-a ${tier_a} --counts ${counts} \\
        --segments ${prefix}.segments.bed --dropped ${prefix}.dropped_lines.tsv ${args}
    """

    stub:
    prefix = task.ext.prefix ?: "${meta.id}"
    """
    printf '#chrom\\tstart\\tend\\tline\\tstate\\n' > ${prefix}.segments.bed
    printf 'line\\tcovered_markers\\tcut\\n' > ${prefix}.dropped_lines.tsv
    """
}
