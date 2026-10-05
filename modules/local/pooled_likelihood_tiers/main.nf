process POOLED_LIKELIHOOD_TIERS {
    tag "${meta.id}"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
        ? 'https://community-cr-prod.seqera.io/docker/registry/v2/blobs/sha256/ea/eab5e327131db0b3743e8264de7ea497bf3f9d2d5c4bab89147c89c0bb7cb765/data'
        : 'community.wave.seqera.io/library/python:3.12.14--e1a45735c4c986d6'}"

    input:
    tuple val(meta), path(vcf), path(controls, stageAs: 'controls/*')
    path tool

    output:
    tuple val(meta), path("${prefix}.sites.tsv.gz"), emit: sites
    tuple val("${task.process}"), val('python'), eval("python3 --version | sed 's/Python //'"), topic: versions, emit: versions_python

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    prefix = task.ext.prefix ?: "${meta.id}"
    // the tool is a path input, so an edit to it reruns the task (docs/running.md)
    """
    python3 ${tool} --vcf ${vcf} --witness ${meta.witness} --controls ${controls} --out ${prefix}.sites.tsv.gz ${args}
    """

    stub:
    prefix = task.ext.prefix ?: "${meta.id}"
    """
    python3 -c "import gzip; gzip.open('${prefix}.sites.tsv.gz', 'wt').close()"
    """
}
