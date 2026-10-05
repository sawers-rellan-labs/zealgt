include { BCFTOOLS_MERGE                            } from '../../../modules/nf-core/bcftools/merge/main'
include { BCFTOOLS_NORM                             } from '../../../modules/nf-core/bcftools/norm/main'
include { BCFTOOLS_VIEW as BIALLELIC_UNION          } from '../../../modules/nf-core/bcftools/view/main'
include { BCFTOOLS_MPILEUP as COUNT_UNION           } from '../../../modules/nf-core/bcftools/mpileup/main'
include { POOLED_LIKELIHOOD_TIERS as UNION_TIERS    } from '../../../modules/local/pooled_likelihood_tiers/main'
include { FILL_DONOR_ALLELES                        } from '../../../modules/local/fill_donor_alleles/main'
include { BCFTOOLS_VIEW as DONOR_ALLELES_INDEX      } from '../../../modules/nf-core/bcftools/view/main'

workflow SITES_UNION_GAPFILL {
    take:
    ch_tier_a   // channel: [ meta, tier_a.vcf ], one per donor
    ch_cram     // channel: [ meta, cram, crai ], meta.role, meta.donor
    ch_controls // channel: [ meta, cram, crai ], the B73 controls
    ch_fasta    // channel: [ meta, fasta, fai ]
    score_tool  // file: bin/score_pooled_likelihood.py
    fill_tool   // file: bin/fill_donor_alleles.py

    main:
    // MARKER_UNION: the donors' tier-A sites in one VCF; a position with two ALT alleles becomes one record, then dropped
    BCFTOOLS_MERGE(ch_tier_a.map { _meta, vcf -> vcf }.collect().map { vcfs -> [[id: 'union'], vcfs, [], []] }, ch_fasta)
    BCFTOOLS_NORM(BCFTOOLS_MERGE.out.vcf.map { meta, vcf -> [meta, vcf, []] }, ch_fasta.map { meta, fasta, _fai -> [meta, fasta] })
    BIALLELIC_UNION(BCFTOOLS_NORM.out.vcf.map { meta, vcf -> [meta, vcf, []] }, [], [], [])
    def ch_union = BIALLELIC_UNION.out.vcf.join(BIALLELIC_UNION.out.index, failOnMismatch: true)

    // each BC1 sample and each B73 control counted at every union site
    COUNT_UNION(
        ch_cram.filter { meta, _cram, _crai -> meta.role == 'bc1_sample' }
            .mix(ch_controls)
            .combine(ch_union)
            .map { meta, cram, crai, _umeta, vcf, _tbi -> [meta, cram, crai, vcf, []] },
        ch_fasta,
        false
    )
    def ch_counts = COUNT_UNION.out.vcf.branch { meta, _vcf ->
        bc1: meta.donor != null
        control: true
    }

    // each donor scored at every union site from its BC1 samples' counts, the B73 controls as in discovery
    UNION_TIERS(
        ch_counts.bc1.map { meta, vcf -> [meta.donor, vcf] }.groupTuple()
            .combine(ch_counts.control.map { _meta, vcf -> vcf }.collect().toList())
            .combine(ch_union)
            .map { donor, vcfs, controls, _umeta, union, _tbi -> [[id: donor], vcfs, controls, union] },
        score_tool
    )

    // every donor's allele at every union site (Eq. eb), donors in name order
    def ch_donors = ch_tier_a.map { meta, vcf -> [meta.id, vcf] }
        .join(UNION_TIERS.out.sites.map { meta, tsv -> [meta.id, tsv] }, failOnMismatch: true)
        .toSortedList { x, y -> x[0] <=> y[0] }
        .map { rows -> rows.transpose() }
    FILL_DONOR_ALLELES(
        ch_union.combine(ch_donors).map { meta, union, _tbi, donors, tier_a, tables -> [meta, union, donors, tier_a, tables] },
        fill_tool
    )
    DONOR_ALLELES_INDEX(FILL_DONOR_ALLELES.out.vcf.map { meta, vcf -> [meta, vcf, []] }, [], [], [])

    emit:
    union         = ch_union                                                                // channel: [ meta, vcf.gz, tbi ]
    donor_alleles = DONOR_ALLELES_INDEX.out.vcf.join(DONOR_ALLELES_INDEX.out.index, failOnMismatch: true) // channel: [ meta, vcf.gz, tbi ]
}
