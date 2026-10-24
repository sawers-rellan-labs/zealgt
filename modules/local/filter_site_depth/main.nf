process FILTER_SITE_DEPTH {
    tag "${meta.id}"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
        ? 'https://community-cr-prod.seqera.io/docker/registry/v2/blobs/sha256/c4/c4d29cca51c733d2c51ba1c49850478c62f41e1bd28f7aae1fc7ae12bed1a556/data'
        : 'community.wave.seqera.io/library/python_pysam:3717afc71d152b3b'}"

    input:
    tuple val(meta), val(donors), path(counts, stageAs: 'counts/*'), path(markers, stageAs: 'markers*/*')
    path tool

    output:
    tuple val(meta), path("*.markers.vcf"), emit: markers
    tuple val("${task.process}"), val('python'), eval("python3 --version | sed 's/Python //'"), topic: versions, emit: versions_python

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def tag = meta.region.replace(':', '_')
    // donors, their count VCFs and their markers come in the same order; each donor's kept markers named by donor and region
    def donor_args = [donors, [counts].flatten(), [markers].flatten()].transpose()
        .collect { d, c, m -> "--donor ${c} ${m} ${d}.${tag}.markers.vcf" }.join(' ')
    // the tool is a path input, so an edit to it reruns the task (docs/running.md)
    """
    python3 ${tool} ${donor_args} ${args}
    """

    stub:
    def tag = meta.region.replace(':', '_')
    """
    touch ${donors.collect { d -> "${d}.${tag}.markers.vcf" }.join(' ')}
    """
}
