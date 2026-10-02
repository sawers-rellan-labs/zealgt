process EXTRACT_LANE {
    tag "${meta.id}"
    label 'process_single'

    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
        ? 'https://community-cr-prod.seqera.io/docker/registry/v2/blobs/sha256/52/52ccce28d2ab928ab862e25aae26314d69c8e38bd41ca9431c67ef05221348aa/data'
        : 'community.wave.seqera.io/library/coreutils_grep_gzip_lbzip2_pruned:838ba80435a629f8'}"

    input:
    tuple val(meta), path(source1), path(source2), val(member1), val(member2), val(head_pairs)

    output:
    tuple val(meta), path("${meta.id}_R1.fastq.gz"), path("${meta.id}_R2.fastq.gz"), emit: reads
    tuple val("${task.process}"), val('tar'), eval('tar --version | head -n 1 | sed "s/^.* //"'), topic: versions, emit: versions_tar

    when:
    task.ext.when == null || task.ext.when

    script:
    // a lane is a tar member (batch 1) or a plain file; head_pairs > 0 keeps its first pairs only
    def reader1 = member1 ? "tar -xOf '${source1}' '${member1}'" : "cat '${source1}'"
    def reader2 = member2 ? "tar -xOf '${source2}' '${member2}'" : "cat '${source2}'"
    def lines   = 4 * (head_pairs as long)
    if (!lines) {
        """
        ${reader1} > ${meta.id}_R1.fastq.gz
        ${reader2} > ${meta.id}_R2.fastq.gz
        """
    } else {
        """
        # the readers may stop with SIGPIPE (141) once head has its lines; head and gzip must succeed
        set +o pipefail
        ${reader1} | gzip -dc | head -n ${lines} | gzip -1 > ${meta.id}_R1.fastq.gz
        s1=( "\${PIPESTATUS[@]}" )
        ${reader2} | gzip -dc | head -n ${lines} | gzip -1 > ${meta.id}_R2.fastq.gz
        s2=( "\${PIPESTATUS[@]}" )
        set -o pipefail
        for st in "\${s1[@]:0:2}" "\${s2[@]:0:2}"; do [[ \$st == 0 || \$st == 141 ]] || { echo "reader failed: \$st" >&2; exit 1; }; done
        for st in "\${s1[@]:2}" "\${s2[@]:2}"; do [[ \$st == 0 ]] || { echo "head or gzip failed: \$st" >&2; exit 1; }; done
        """
    }

    stub:
    """
    echo '' | gzip > ${meta.id}_R1.fastq.gz
    echo '' | gzip > ${meta.id}_R2.fastq.gz
    """
}
