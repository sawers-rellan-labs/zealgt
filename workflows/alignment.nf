include { SEQKIT_HEAD             } from '../modules/nf-core/seqkit/head/main'
include { FASTQ_SEQUALI           } from '../subworkflows/local/fastq_sequali/main'
include { FASTQ_ALIGN_MINIBWA     } from '../subworkflows/local/fastq_align_minibwa/main'
include { CRAM_QC_SAMTOOLS_PICARD } from '../subworkflows/local/cram_qc_samtools_picard/main'
include { MULTIQC                } from '../modules/nf-core/multiqc/main'
include { paramsSummaryMap       } from 'plugin/nf-schema'
include { paramsSummaryMultiqc   } from '../subworkflows/nf-core/utils_nfcore_pipeline'
include { methodsDescriptionText } from '../subworkflows/local/utils_nfcore_zealgt_pipeline'

workflow ALIGNMENT {
    take:
    ch_samplesheet // channel: [ meta, fastq_1, fastq_2 ], one per sample
    head_pairs     // integer: first N read pairs per sample, 0 = all
    read_qc        // boolean: run Sequali and the read-QC report
    fasta         // string: reference FASTA, its .fai next to it
    minibwa_index  // string: glob of the minibwa index files (.l2b, .mbw)
    ch_versions    // channel: the collated software versions YAML
    multiqc_config
    multiqc_logo
    multiqc_methods_description

    main:
    // --head N (test runs): the first N pairs per sample, by seqkit head
    def ch_input = ch_samplesheet
        .map { meta, r1, r2 -> [meta + [single_end: false], [r1, r2]] }
        .branch { _meta, _reads ->
            head: head_pairs > 0
            all: true
        }
    SEQKIT_HEAD(ch_input.head.map { meta, reads -> [meta, reads, head_pairs] })
    def ch_reads = ch_input.all.mix(SEQKIT_HEAD.out.subset)
    // --read_qc: Sequali and its read-QC report, for FASTQs that did not come from our demultiplexing
    FASTQ_SEQUALI(ch_reads.filter { _meta, _reads -> read_qc }, file(multiqc_config ?: "${projectDir}/assets/multiqc_config.yml", checkIfExists: true))

    // reference and its prebuilt minibwa index, read by every alignment task
    def ch_fasta = channel.value([[id: file(fasta).name], file(fasta, checkIfExists: true), file("${fasta}.fai", checkIfExists: true)])
    FASTQ_ALIGN_MINIBWA(ch_reads, ch_fasta, channel.value([[id: file(fasta).name], files(minibwa_index, checkIfExists: true)]))
    CRAM_QC_SAMTOOLS_PICARD(FASTQ_ALIGN_MINIBWA.out.cram, ch_fasta)
    // QC per sample: duplicate counts from markdup, then the CRAM QC tools
    def ch_cram_qc = FASTQ_ALIGN_MINIBWA.out.markdup_stats.mix(CRAM_QC_SAMTOOLS_PICARD.out.qc)

    // MODULE: MultiQC
    def ch_multiqc_files = ch_cram_qc.map { _meta, f -> f }.mix(ch_versions)
    def ch_summary_params = paramsSummaryMap(workflow, parameters_schema: "nextflow_schema.json")
    def ch_workflow_summary = channel.value(paramsSummaryMultiqc(ch_summary_params))
    ch_multiqc_files = ch_multiqc_files.mix(ch_workflow_summary.collectFile(name: 'workflow_summary_mqc.yaml'))
    def ch_multiqc_custom_methods_description = multiqc_methods_description
        ? file(multiqc_methods_description, checkIfExists: true)
        : file("${projectDir}/assets/methods_description_template.yml", checkIfExists: true)
    def ch_methods_description = channel.value(methodsDescriptionText(ch_multiqc_custom_methods_description))
    ch_multiqc_files = ch_multiqc_files.mix(ch_methods_description.collectFile(name: 'methods_description_mqc.yaml', sort: true))
    MULTIQC(
        ch_multiqc_files.flatten().collect().map { files ->
            [
                [id: 'zealgt'],
                files,
                multiqc_config
                    ? file(multiqc_config, checkIfExists: true)
                    : file("${projectDir}/assets/multiqc_config.yml", checkIfExists: true),
                multiqc_logo ? file(multiqc_logo, checkIfExists: true) : [],
                [], [],
            ]
        }
    )
    emit:
    multiqc_report = MULTIQC.out.report.map { _meta, report -> [report] }.toList() // channel: /path/to/multiqc_report.html
    cram           = FASTQ_ALIGN_MINIBWA.out.cram     // channel: [ meta, cram, crai ], one per sample
    cram_qc        = ch_cram_qc                       // channel: [ meta, file ], several per sample
}
