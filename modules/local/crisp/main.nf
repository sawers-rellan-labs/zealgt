process CRISP {
    tag "${meta.id}"
    label 'process_medium'

    // CRISP is not on conda: vibansal/crisp at commit 1a9027e, built from containers/crisp/Dockerfile
    container 'ghcr.io/sawers-rellan-labs/zealgt-crisp:1a9027e'

    input:
    tuple val(meta), path(crams, arity: '1..*', stageAs: 'bc1/*'), path(crais, arity: '1..*', stageAs: 'bc1/*'), path(witness, stageAs: 'witness/*'), path(witness_index, stageAs: 'witness/*'), path(checks, stageAs: 'checks/*'), path(checks_index, stageAs: 'checks/*')
    tuple val(meta2), path(fasta), path(fai)
    path bed

    output:
    tuple val(meta), path("${prefix}.crisp.vcf"), emit: vcf
    tuple val(meta), path("${prefix}.crisp.log"), emit: log
    tuple val("${task.process}"), val('crisp'), val('1a9027e'), topic: versions, emit: versions_crisp

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    prefix = task.ext.prefix ?: "${meta.id}"
    // --sm 0 names each pool by its file name, which must start with ./ (CRISP drops a bare name's first character); the NIL pool first, the check pool second
    """
    printf '%s\\n' ./${witness} ./${checks} ${crams.collect { c -> "./${c}" }.join(' ')} > bams.txt

    # CRISP exits 1 on success: success is the finish line in its log
    CRISP --bams bams.txt --ref ${fasta} --bed ${bed} --sm 0 ${args} --VCF ${prefix}.crisp.vcf 2>&1 | tee ${prefix}.crisp.log >&2 || [ \$? -eq 1 ]
    grep -q 'CRISP has finished processing' ${prefix}.crisp.log
    """

    stub:
    prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}.crisp.vcf ${prefix}.crisp.log
    """
}
