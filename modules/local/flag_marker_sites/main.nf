process FLAG_MARKER_SITES {
    tag "${meta.id}"
    label 'process_single'

    conda "${moduleDir}/../fill_donor_alleles/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
        ? 'https://community-cr-prod.seqera.io/docker/registry/v2/blobs/sha256/c4/c4d29cca51c733d2c51ba1c49850478c62f41e1bd28f7aae1fc7ae12bed1a556/data'
        : 'community.wave.seqera.io/library/python_pysam:3717afc71d152b3b'}"

    input:
    tuple val(meta), path(recounts), path(markers), path(counts)
    tuple path(known_sites), path(known_sites_tbi)
    path tool

    output:
    tuple val(meta), path("${prefix}.union_markers.vcf"), emit: union
    tuple val(meta), path("${prefix}.{flags,marker_counts}.tsv"), emit: tables
    tuple val("${task.process}"), val('pysam'), eval("python3 -c 'import pysam; print(pysam.__version__)'"), topic: versions, emit: versions_pysam

    when:
    task.ext.when == null || task.ext.when

    script:
    prefix = task.ext.prefix ?: "${meta.id}"
    // one --donor/--recount/--markers/--counts group per donor, in the order the lists arrive
    def donors = [meta.donors, recounts, markers, counts].transpose().collect { d, r, m, c -> "--donor ${d} --recount ${r} --markers ${m} --counts ${c}" }.join(' ')
    // the tool is a path input, so an edit to it reruns the task (docs/running.md)
    """
    python3 ${tool} --region ${meta.region} --known-sites ${known_sites} --prefix ${prefix} ${donors}
    """

    stub:
    prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}.union_markers.vcf ${prefix}.flags.tsv ${prefix}.marker_counts.tsv
    """
}
