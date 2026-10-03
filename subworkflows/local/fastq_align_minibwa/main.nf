include { MINIBWA_MAP      } from '../../../modules/nf-core/minibwa/map/main'
include { FGUMI_CLIP       } from '../../../modules/nf-core/fgumi/clip/main'
include { SAMTOOLS_FIXMATE } from '../../../modules/nf-core/samtools/fixmate/main'
include { SAMTOOLS_SORT    } from '../../../modules/nf-core/samtools/sort/main'
include { SAMTOOLS_MARKDUP } from '../../../modules/nf-core/samtools/markdup/main'
include { SAMTOOLS_INDEX   } from '../../../modules/nf-core/samtools/index/main'

workflow FASTQ_ALIGN_MINIBWA {

    take:
    ch_reads // channel: [ meta + lanes, [ R1, R2 ] ], one per sample
    ch_fasta // channel: [ meta, fasta, fai ], value
    ch_index // channel: [ meta, [ l2b, mbw ] ], value

    main:
    def ch_fa = ch_fasta.map { meta, fasta, _fai -> [meta, fasta] }

    // query-grouped alignment with the sample's read group, soft clips past the mate, mate tags, coordinate order
    MINIBWA_MAP(ch_reads, ch_index, ch_fa, false)
    FGUMI_CLIP(MINIBWA_MAP.out.aligned, ch_fa)
    SAMTOOLS_FIXMATE(FGUMI_CLIP.out.bam, ch_fasta)
    SAMTOOLS_SORT(SAMTOOLS_FIXMATE.out.bam, ch_fasta, '')

    // duplicates flagged, not removed; CRAM against the reference, then its index
    SAMTOOLS_MARKDUP(SAMTOOLS_SORT.out.bam, ch_fasta)
    SAMTOOLS_INDEX(SAMTOOLS_MARKDUP.out.cram)

    emit:
    cram          = SAMTOOLS_MARKDUP.out.cram.join(SAMTOOLS_INDEX.out.index, failOnMismatch: true) // channel: [ meta, cram, crai ], one per sample
    markdup_stats = SAMTOOLS_MARKDUP.out.stats                                                    // channel: [ meta, markdup.stats ], one per sample
}
