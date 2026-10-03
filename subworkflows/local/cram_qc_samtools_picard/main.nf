include { SAMTOOLS_STATS           } from '../../../modules/nf-core/samtools/stats/main'
include { PICARD_COLLECTWGSMETRICS } from '../../../modules/nf-core/picard/collectwgsmetrics/main'
include { MOSDEPTH                 } from '../../../modules/nf-core/mosdepth/main'

workflow CRAM_QC_SAMTOOLS_PICARD {

    take:
    ch_cram  // channel: [ meta, cram, crai ], one per sample
    ch_fasta // channel: [ meta, fasta, fai ], value

    main:
    // alignment summary and duplicates, usable depth with its exclusions, raw depth per 500 bp window
    SAMTOOLS_STATS(ch_cram, ch_fasta)
    PICARD_COLLECTWGSMETRICS(ch_cram, ch_fasta.map { meta, fasta, _fai -> [meta, fasta] }, ch_fasta.map { meta, _fasta, fai -> [meta, fai] }, [])
    MOSDEPTH(ch_cram.map { meta, cram, crai -> [meta, cram, crai, []] }, ch_fasta, [])

    emit:
    qc = SAMTOOLS_STATS.out.stats // channel: [ meta, file ], several per sample
        .mix(PICARD_COLLECTWGSMETRICS.out.metrics)
        .mix(MOSDEPTH.out.summary_txt, MOSDEPTH.out.global_txt, MOSDEPTH.out.regions_txt, MOSDEPTH.out.regions_bed, MOSDEPTH.out.regions_csi)
}
