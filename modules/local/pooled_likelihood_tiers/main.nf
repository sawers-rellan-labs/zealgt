process POOLED_LIKELIHOOD_TIERS {
    tag "${meta.id}"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
        ? 'https://community-cr-prod.seqera.io/docker/registry/v2/blobs/sha256/c4/c4d29cca51c733d2c51ba1c49850478c62f41e1bd28f7aae1fc7ae12bed1a556/data'
        : 'community.wave.seqera.io/library/python_pysam:3717afc71d152b3b'}"

    input:
    tuple val(meta), path(vcf, stageAs: 'pools/*'), path(controls, stageAs: 'controls/*'), path(sites)
    path tool

    output:
    tuple val(meta), path("${prefix}.sites.tsv.gz"), emit: sites
    tuple val(meta), path("${prefix}.tier_a.vcf"), emit: tier_a
    tuple val("${task.process}"), val('python'), eval("python3 --version | sed 's/Python //'"), topic: versions, emit: versions_python
    tuple val("${task.process}"), val('pysam'), eval("python3 -c 'import pysam; print(pysam.__version__)'"), topic: versions, emit: versions_pysam

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    prefix = task.ext.prefix ?: "${meta.id}"
    // the witness-vetoed CRISP VCF (discovery), or the BC1 pools' counts at the given sites (the union)
    def input = sites ? "--bc1-vcf ${vcf} --sites ${sites}" : "--vcf ${vcf} --witness ${meta.witness}"
    // the tool is a path input, so an edit to it reruns the task (docs/running.md)
    """
    python3 ${tool} ${input} --controls ${controls} --out ${prefix}.sites.tsv.gz --tier-a-vcf ${prefix}.tier_a.vcf ${args}
    """

    stub:
    prefix = task.ext.prefix ?: "${meta.id}"
    """
    python3 -c "import gzip; gzip.open('${prefix}.sites.tsv.gz', 'wt').close()"
    touch ${prefix}.tier_a.vcf
    """
}
