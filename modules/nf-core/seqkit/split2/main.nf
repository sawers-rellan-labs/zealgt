process SEQKIT_SPLIT2 {
    tag "${meta.id}"
    label 'process_medium'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
        ? 'https://community-cr-prod.seqera.io/docker/registry/v2/blobs/sha256/4f/4fe272ab9a519cf418160471a485b5ef50ea3f571a8e4555a826f70a4d8243ae/data'
        : 'community.wave.seqera.io/library/seqkit:2.13.0--05c0a96bf9fb2751'}"

    input:
    tuple val(meta), path(reads)

    output:
    tuple val(meta), path("${prefix}/*"), emit: reads
    tuple val("${task.process}"), val('seqkit'), eval("seqkit version | sed 's/^.*v//'"), emit: versions_seqkit, topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    prefix = task.ext.prefix ?: "${meta.id}"
    // seqkit writes no part for an empty input: then one empty part_001 per read
    def parts = [reads].flatten().collect { f -> f.name.replaceFirst(/(\.f(ast)?q(\.gz)?)$/, '.part_001$1') }
    def empty = parts.collect { f -> "printf '' | gzip > ${prefix}/${f}" }.join('; ')
    if (meta.single_end) {
        """
        seqkit \\
            split2 \\
            ${args} \\
            --threads ${task.cpus} \\
            ${reads} \\
            --out-dir ${prefix}

        ls ${prefix}/* > /dev/null 2>&1 || { mkdir -p ${prefix}; ${empty}; }
        """
    }
    else {
        """
        seqkit \\
            split2 \\
            ${args} \\
            --threads ${task.cpus} \\
            --read1 ${reads[0]} \\
            --read2 ${reads[1]} \\
            --out-dir ${prefix}

        ls ${prefix}/* > /dev/null 2>&1 || { mkdir -p ${prefix}; ${empty}; }
        """
    }

    stub:
    def args = task.ext.args ?: ''
    prefix = task.ext.prefix ?: "${meta.id}"
    // one chunk named as seqkit names its parts
    def parts = [reads].flatten().collect { f -> f.name.replaceFirst(/(\.f(ast)?q(\.gz)?)$/, '.part_001$1') }
    if (meta.single_end) {
        """
        echo ${args}

        mkdir -p ${prefix}
        echo '' | gzip > ${prefix}/${parts[0]}
        """
    }
    else {
        """
        echo ${args}

        mkdir -p ${prefix}
        echo '' | gzip > ${prefix}/${parts[0]}
        echo '' | gzip > ${prefix}/${parts[1]}
        """
    }
}
