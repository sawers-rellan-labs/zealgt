include { FASTQ_DEMULTIPLEX_FQTK } from '../subworkflows/local/fastq_demultiplex_fqtk/main'
include { FASTQ_SEQUALI         } from '../subworkflows/local/fastq_sequali/main'

workflow DEMULTIPLEX {
    take:
    ch_samplesheet // channel: [ meta, raw_location, raw_r1, raw_r2 ], one per library row
    head_pairs     // integer: first N read pairs per library, 0 = all
    multiqc_config // file: MultiQC config for the read-QC report

    main:
    FASTQ_DEMULTIPLEX_FQTK(ch_samplesheet, head_pairs)
    FASTQ_SEQUALI(FASTQ_DEMULTIPLEX_FQTK.out.reads, multiqc_config)

    emit:
    // one samplesheet row per kept sample, the columns of assets/schema_fastq.json
    fastq = FASTQ_DEMULTIPLEX_FQTK.out.reads.map { meta, reads ->
        [sample_id: meta.id, fastq_1: reads[0], fastq_2: reads[1], source: meta.source, library: meta.library, lanes: meta.lanes, kit: meta.kit]
    }
}
