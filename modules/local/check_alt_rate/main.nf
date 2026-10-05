process CHECK_ALT_RATE {
    tag "${meta.id}"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
        ? 'https://community-cr-prod.seqera.io/docker/registry/v2/blobs/sha256/0b/0b4d52ca9a56d07be3f78a12af654e5116f5112908dba277e6796fd9dfb83fe5/data'
        : 'community.wave.seqera.io/library/bcftools_htslib:1.23.1--9f08ec665533d64a'}"

    input:
    tuple val(meta), path(vcf)

    output:
    tuple val(meta), path("${prefix}.alt_rate.tsv"), emit: tsv
    tuple val(meta), env('ALT_RATE'), emit: rate
    tuple val("${task.process}"), val('bcftools'), eval("bcftools --version | sed '1!d; s/^.*bcftools //'"), topic: versions, emit: versions_bcftools

    when:
    task.ext.when == null || task.ext.when

    script:
    prefix = task.ext.prefix ?: "${meta.id}"
    // reads and non-REF reads summed over the check's AD at every site: sample, reads, ALT reads, ALT share
    """
    bcftools query -f '[%AD]\\n' ${vcf} \\
        | awk -F, -v OFS='\\t' -v s=${meta.id} '{ for (i = 1; i <= NF; i++) { n += \$i; if (i > 1) a += \$i } } END { printf "%s\\t%d\\t%d\\t%.6f\\n", s, n, a, (n ? a / n : 0) }' \\
        > ${prefix}.alt_rate.tsv
    ALT_RATE=\$(cut -f4 ${prefix}.alt_rate.tsv)
    echo "\$(date '+%F %T') ${meta.id}: \$(cut -f2-4 ${prefix}.alt_rate.tsv | tr '\\t' ' ') (reads, ALT reads, ALT share)" >&2
    """

    stub:
    prefix = task.ext.prefix ?: "${meta.id}"
    """
    printf '%s\\t0\\t0\\t0\\n' ${meta.id} > ${prefix}.alt_rate.tsv
    ALT_RATE=0
    """
}
