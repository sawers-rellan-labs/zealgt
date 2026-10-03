include { MINIBWA_MAP      } from '../../../modules/nf-core/minibwa/map/main'
include { FGUMI_CLIP       } from '../../../modules/nf-core/fgumi/clip/main'
include { SAMTOOLS_FIXMATE } from '../../../modules/nf-core/samtools/fixmate/main'
include { SAMTOOLS_SORT    } from '../../../modules/nf-core/samtools/sort/main'
include { SAMTOOLS_MERGE   } from '../../../modules/nf-core/samtools/merge/main'
include { SAMTOOLS_MARKDUP } from '../../../modules/nf-core/samtools/markdup/main'
include { SAMTOOLS_INDEX   } from '../../../modules/nf-core/samtools/index/main'

workflow FASTQ_ALIGN_MINIBWA {

    take:
    ch_reads // channel: [ meta + lane + n_lanes, [ R1, R2 ] ], one per sample x lane
    ch_fasta // channel: [ meta, fasta, fai ], value
    ch_index // channel: [ meta, [ l2b, mbw ] ], value

    main:
    def ch_fa = ch_fasta.map { meta, fasta, _fai -> [meta, fasta] }

    // per lane: query-grouped alignment with the lane's read group, soft clips past the mate, mate tags, coordinate order
    MINIBWA_MAP(ch_reads, ch_index, ch_fa, false)
    FGUMI_CLIP(MINIBWA_MAP.out.aligned, ch_fa)
    SAMTOOLS_FIXMATE(FGUMI_CLIP.out.bam, ch_fasta)
    SAMTOOLS_SORT(SAMTOOLS_FIXMATE.out.bam, ch_fasta, '')

    // per sample: its lane BAMs, released when all lanes of the library are in; one-lane samples skip the merge
    def ch_sample_bams = SAMTOOLS_SORT.out.bam
        .map { meta, bam -> [groupKey(meta - meta.subMap('lane'), meta.n_lanes), bam] }
        .groupTuple()
        .map { key, bams -> [key.getGroupTarget(), bams] }
        .branch { _meta, bams ->
            one_lane: bams.size() == 1
            lanes: true
        }

    SAMTOOLS_MERGE(
        ch_sample_bams.lanes.map { meta, bams -> [meta, bams, []] },
        ch_fasta.map { meta, fasta, fai -> [meta, fasta, fai, []] },
        ''
    )

    // duplicates flagged, not removed; CRAM against the reference, then its index
    SAMTOOLS_MARKDUP(
        ch_sample_bams.one_lane.map { meta, bams -> [meta, bams[0]] }.mix(SAMTOOLS_MERGE.out.bam),
        ch_fasta
    )
    SAMTOOLS_INDEX(SAMTOOLS_MARKDUP.out.cram)

    emit:
    cram = SAMTOOLS_MARKDUP.out.cram.join(SAMTOOLS_INDEX.out.index, failOnMismatch: true) // channel: [ meta, cram, crai ], one per sample
}
