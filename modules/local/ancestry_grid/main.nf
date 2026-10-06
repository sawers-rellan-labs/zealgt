process ANCESTRY_GRID {
    tag "${meta.id}"
    label 'process_single'

    // nilHMM is not on conda: built from containers/nilhmm/Dockerfile
    container 'ghcr.io/sawers-rellan-labs/zealgt-nilhmm:0.3.1-1'

    input:
    tuple val(meta), path(union), path(tbi), val(donors), path(segments, stageAs: 'segments/*')
    path map
    path tool

    output:
    tuple val(meta), path("${prefix}.grid.tsv"), emit: grid
    tuple val(meta), path("*.${prefix}.rqtl.csv"), emit: rqtl
    tuple val(meta), path("*.${prefix}.ancestry.vcf"), emit: vcf
    tuple val("${task.process}"), val('nilHMM'), eval("Rscript -e 'cat(as.character(packageVersion(\"nilHMM\")))'"), topic: versions, emit: versions_nilhmm

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    prefix = task.ext.prefix ?: "${meta.id}"
    // the bundled v5 map unless a map file is given
    def map_arg = map ? "--map ${map}" : ''
    // the tool is a path input, so an edit to it reruns the task (docs/running.md)
    """
    Rscript ${tool} --union ${union} --donors ${donors.join(' ')} --segments ${segments} --prefix ${prefix} ${map_arg} ${args}
    """

    stub:
    prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}.grid.tsv
    for d in ${donors.join(' ')}; do
        touch \$d.${prefix}.rqtl.csv \$d.${prefix}.ancestry.vcf
    done
    """
}
