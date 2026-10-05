process FILL_DONOR_ALLELES {
    tag "${meta.id}"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
        ? 'https://community-cr-prod.seqera.io/docker/registry/v2/blobs/sha256/ea/eab5e327131db0b3743e8264de7ea497bf3f9d2d5c4bab89147c89c0bb7cb765/data'
        : 'community.wave.seqera.io/library/python:3.12.14--e1a45735c4c986d6'}"

    input:
    tuple val(meta), path(union), val(donors), path(tier_a, stageAs: 'tier_a/*'), path(tables, stageAs: 'tables/*')
    path tool

    output:
    tuple val(meta), path("${prefix}.vcf"), emit: vcf
    tuple val("${task.process}"), val('python'), eval("python3 --version | sed 's/Python //'"), topic: versions, emit: versions_python

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    prefix = task.ext.prefix ?: "${meta.id}"
    // donors, their tier-A VCFs and their union tables come in the same order
    def donor_args = [donors, [tier_a].flatten(), [tables].flatten()].transpose().collect { d, a, t -> "--donor ${d} ${a} ${t}" }.join(' ')
    // the tool is a path input, so an edit to it reruns the task (docs/running.md)
    """
    python3 ${tool} --union ${union} ${donor_args} --out ${prefix}.vcf ${args}
    """

    stub:
    prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}.vcf
    """
}
