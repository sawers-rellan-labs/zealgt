process FGBIO_DEMUXFASTQS {
    tag "${meta.id}"
    label 'process_medium'

    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
        ? 'https://community-cr-prod.seqera.io/docker/registry/v2/blobs/sha256/4d/4d1150a2e123f49f8c268f0ab429847afae642376fa52af713b846b084df4a9f/data'
        : 'community.wave.seqera.io/library/fgbio:3.1.2--6e9400d507a9dc55'}"

    input:
    tuple val(meta), path(read1), path(read2), path(sample_sheet)

    output:
    tuple val(meta), path("demux/*/*.fastq.gz")     , emit: reads
    tuple val(meta), path("*.demux_metrics.txt")    , emit: metrics
    tuple val("${task.process}"), val('fgbio'), eval('fgbio --version 2>&1 | tr -d "[:cntrl:]" | sed -e "s/^.*Version: //;s/\\[.*$//"'), topic: versions, emit: versions_fgbio

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    // JVM heap: the task's memory minus 1 GB for the JVM itself
    def heap   = task.memory ? Math.max(1, task.memory.giga - 1) : 1
    """
    fgbio -Xmx${heap}g --tmp-dir=. DemuxFastqs \\
        --inputs ${read1} ${read2} \\
        --metadata ${sample_sheet} \\
        --output out \\
        --metrics ${prefix}.demux_metrics.txt \\
        --output-type Fastq \\
        --threads ${task.cpus} \\
        ${args}

    # fgbio names files <Sample_Id>-<Sample_Name>-<barcode>_R<n>; keep demux/<prefix>/<Sample_Id>_R<n>, drop unmatched
    mkdir -p demux/${prefix}
    tail -n +2 ${sample_sheet} | while IFS=, read -r id name barcode; do
        for r in R1 R2; do mv "out/\${id}-\${name}-\${barcode}_\${r}.fastq.gz" "demux/${prefix}/\${id}_\${r}.fastq.gz"; done
    done
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    mkdir -p demux/${prefix}
    tail -n +2 ${sample_sheet} | while IFS=, read -r id name barcode; do
        for r in R1 R2; do echo '' | gzip > "demux/${prefix}/\${id}_\${r}.fastq.gz"; done
    done
    touch ${prefix}.demux_metrics.txt
    """
}
