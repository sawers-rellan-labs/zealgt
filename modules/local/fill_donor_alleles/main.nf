process FILL_DONOR_ALLELES {
    tag "${meta.id}"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
        ? 'https://community-cr-prod.seqera.io/docker/registry/v2/blobs/sha256/c4/c4d29cca51c733d2c51ba1c49850478c62f41e1bd28f7aae1fc7ae12bed1a556/data'
        : 'community.wave.seqera.io/library/python_pysam:3717afc71d152b3b'}"

    input:
    tuple val(meta), path(union), path(union_tbi), path(tier_a), path(table), path(counts)
    path tool

    output:
    tuple val(meta), path("${prefix}.vcf.gz"), path("${prefix}.vcf.gz.tbi"), emit: vcf
    tuple val("${task.process}"), val('python'), eval("python3 --version | sed 's/Python //'"), topic: versions, emit: versions_python
    tuple val("${task.process}"), val('pysam'), eval("python3 -c 'import pysam; print(pysam.__version__)'"), topic: versions, emit: versions_pysam

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    prefix = task.ext.prefix ?: "${meta.id}"
    // the tool is a path input, so an edit to it reruns the task (docs/running.md)
    """
    python3 ${tool} fill --union ${union} --donor ${meta.id} ${tier_a} ${table} --counts ${counts} --out ${prefix}.vcf.gz ${meta.outside_counts ? '--outside-counts' : ''} ${args}
    """

    stub:
    prefix = task.ext.prefix ?: "${meta.id}"
    """
    python3 -c "import gzip; gzip.open('${prefix}.vcf.gz', 'wt').close()"
    touch ${prefix}.vcf.gz.tbi
    """
}
