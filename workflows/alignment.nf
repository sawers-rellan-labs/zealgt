include { FASTQ_DEMULTIPLEX_FQTK } from '../subworkflows/local/fastq_demultiplex_fqtk/main'
include { FASTQ_ALIGN_MINIBWA   } from '../subworkflows/local/fastq_align_minibwa/main'
include { CRAM_QC_SAMTOOLS_PICARD } from '../subworkflows/local/cram_qc_samtools_picard/main'
include { MULTIQC                } from '../modules/nf-core/multiqc/main'
include { paramsSummaryMap       } from 'plugin/nf-schema'
include { paramsSummaryMultiqc   } from '../subworkflows/nf-core/utils_nfcore_pipeline'
include { softwareVersionsToYAML } from '../subworkflows/nf-core/utils_nfcore_pipeline'
include { methodsDescriptionText } from '../subworkflows/local/utils_nfcore_zealgt_pipeline'

workflow ALIGNMENT {
    take:
    ch_samplesheet // channel: [ meta, raw_location, raw_r1, raw_r2 ], one per sample
    head_pairs     // integer: first N read pairs per library, 0 = all
    fasta          // string: reference FASTA, its .fai next to it
    minibwa_index  // string: glob of the minibwa index files (.l2b, .mbw)
    multiqc_config
    multiqc_logo
    multiqc_methods_description
    outdir

    main:
    def ch_versions = channel.empty()
    def ch_multiqc_files = channel.empty()
    FASTQ_DEMULTIPLEX_FQTK(ch_samplesheet, head_pairs)
    // reference and its prebuilt minibwa index, read by every alignment task
    def ch_fasta = channel.value([[id: file(fasta).name], file(fasta, checkIfExists: true), file("${fasta}.fai", checkIfExists: true)])
    FASTQ_ALIGN_MINIBWA(FASTQ_DEMULTIPLEX_FQTK.out.reads, ch_fasta, channel.value([[id: file(fasta).name], files(minibwa_index, checkIfExists: true)]))
    CRAM_QC_SAMTOOLS_PICARD(FASTQ_ALIGN_MINIBWA.out.cram, ch_fasta)
    // QC per sample: duplicate counts from markdup, then the CRAM QC tools
    def ch_cram_qc = FASTQ_ALIGN_MINIBWA.out.markdup_stats.mix(CRAM_QC_SAMTOOLS_PICARD.out.qc)
    ch_multiqc_files = ch_multiqc_files.mix(ch_cram_qc.map { _meta, f -> f })

    // Collate and save software versions
    def topic_versions = channel.topic("versions")
        .distinct()
        .branch { entry ->
            versions_file: entry instanceof Path
            versions_tuple: true
        }
    def topic_versions_string = topic_versions.versions_tuple
        .map { process, tool, version ->
            [ process[process.lastIndexOf(':')+1..-1], "  ${tool}: ${version}" ]
        }
        .groupTuple(by:0)
        .map { process, tool_versions ->
            tool_versions.unique().sort()
            "${process}:\n${tool_versions.join('\n')}"
        }
    def ch_collated_versions = softwareVersionsToYAML(ch_versions.mix(topic_versions.versions_file))
        .mix(topic_versions_string)
        .collectFile(
            storeDir: "${outdir}/pipeline_info",
            name:  'zealgt_software_'  + 'mqc_'  + 'versions.yml',
            sort: true, newLine: true
        )
    // MODULE: MultiQC
    ch_multiqc_files = ch_multiqc_files.mix(ch_collated_versions)
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
    reads          = FASTQ_DEMULTIPLEX_FQTK.out.reads // channel: [ meta, [ R1, R2 ] ], one per sample
    cram           = FASTQ_ALIGN_MINIBWA.out.cram     // channel: [ meta, cram, crai ], one per sample
    cram_qc        = ch_cram_qc                       // channel: [ meta, file ], several per sample
    versions       = ch_versions                      // channel: [ path(versions.yml) ]
}
