include { BCFTOOLS_MERGE                            } from '../../../modules/nf-core/bcftools/merge/main'
include { BCFTOOLS_MERGE as DONOR_ALLELES_MERGE     } from '../../../modules/nf-core/bcftools/merge/main'
include { BCFTOOLS_NORM                             } from '../../../modules/nf-core/bcftools/norm/main'
include { BCFTOOLS_VIEW as BIALLELIC_UNION          } from '../../../modules/nf-core/bcftools/view/main'
include { BCFTOOLS_MPILEUP as COUNT_UNION           } from '../../../modules/nf-core/bcftools/mpileup/main'
include { POOLED_LIKELIHOOD_TIERS as UNION_TIERS    } from '../../../modules/local/pooled_likelihood_tiers/main'
include { UNION_SITE_COUNTS                         } from '../../../modules/local/union_site_counts/main'
include { FILL_DONOR_ALLELES                        } from '../../../modules/local/fill_donor_alleles/main'

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

    // each donor's tier-A sites and union table
    def ch_donors = ch_tier_a.map { meta, vcf -> [meta.id, vcf] }
        .join(UNION_TIERS.out.sites.map { meta, tsv -> [meta.id, tsv] }, failOnMismatch: true)

    // the per-site totals over all donors that Eq. eb needs (K own tier-A, R ref gaps), donors in name order
    UNION_SITE_COUNTS(
        ch_union.combine(ch_donors.toSortedList { x, y -> x[0] <=> y[0] }.map { rows -> rows.transpose() }),
        fill_tool
    )

    // each donor's allele at every union site (Eq. eb), one task per donor
    FILL_DONOR_ALLELES(
        ch_donors.combine(ch_union).combine(UNION_SITE_COUNTS.out.tsv)
            .map { donor, tier_a, table, _umeta, union, tbi, _cmeta, counts -> [[id: donor], union, tbi, tier_a, table, counts] },
        fill_tool
    )

    // the donors in one VCF, in name order (the module sorts its inputs by file name)
    DONOR_ALLELES_MERGE(
        FILL_DONOR_ALLELES.out.vcf.map { _meta, vcf, tbi -> [vcf, tbi] }.collect(flat: false)
            .map { rows -> rows.transpose() }
            .map { vcfs, tbis -> [[id: 'donor_alleles'], vcfs, tbis, []] },
        ch_fasta
    )

    emit:
    union         = ch_union                                                                           // channel: [ meta, vcf.gz, tbi ]
    donor_alleles = DONOR_ALLELES_MERGE.out.vcf.join(DONOR_ALLELES_MERGE.out.index, failOnMismatch: true) // channel: [ meta, vcf.gz, tbi ]
}
