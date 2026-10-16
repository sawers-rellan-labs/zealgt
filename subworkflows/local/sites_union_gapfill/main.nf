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
    ch_tier_a   // channel: [ meta, tier_a.vcf ], one per donor x region, meta.region
    ch_cram     // channel: [ meta, cram, crai ], meta.role, meta.donor
    ch_controls // channel: [ meta, cram, crai ], the B73 controls, per region
    ch_fasta    // channel: [ meta, fasta, fai ]
    score_tool  // file: bin/score_pooled_likelihood.py
    fill_tool   // file: bin/fill_donor_alleles.py

    main:
    // MARKER_UNION: the donors' tier-A sites in one VCF per region; a position with two ALT alleles becomes one record, then dropped
    BCFTOOLS_MERGE(ch_tier_a.map { meta, vcf -> [meta.region, vcf] }.groupTuple().map { region, vcfs -> [[id: 'union', region: region], vcfs, [], []] }, ch_fasta)
    BCFTOOLS_NORM(BCFTOOLS_MERGE.out.vcf.map { meta, vcf -> [meta, vcf, []] }, ch_fasta.map { meta, fasta, _fai -> [meta, fasta] })
    BIALLELIC_UNION(BCFTOOLS_NORM.out.vcf.map { meta, vcf -> [meta, vcf, []] }, [], [], [])
    def ch_union = BIALLELIC_UNION.out.vcf.join(BIALLELIC_UNION.out.index, failOnMismatch: true)
    def ch_union_vcf = ch_union.map { meta, vcf, _tbi -> [meta.region, vcf] }

    // each BC1 sample and each B73 control counted at every union site of each region
    COUNT_UNION(
        ch_cram.filter { meta, _cram, _crai -> meta.role == 'bc1_sample' }
            .combine(ch_union_vcf)
            .map { meta, cram, crai, region, vcf -> [meta + [region: region], cram, crai, vcf, []] }
            .mix(ch_controls.map { meta, cram, crai -> [meta.region, meta, cram, crai] }.combine(ch_union_vcf, by: 0)
                .map { _region, meta, cram, crai, vcf -> [meta, cram, crai, vcf, []] }),
        ch_fasta,
        false
    )
    def ch_counts = COUNT_UNION.out.vcf.branch { meta, _vcf ->
        bc1: meta.donor != null
        control: true
    }

    // each donor scored at every union site of a region from its BC1 samples' counts, the B73 controls as in discovery
    UNION_TIERS(
        ch_counts.bc1.map { meta, vcf -> [meta.region, meta.donor, vcf] }.groupTuple(by: [0, 1])
            .combine(ch_counts.control.map { meta, vcf -> [meta.region, vcf] }.groupTuple(), by: 0)
            .combine(ch_union_vcf, by: 0)
            .map { region, donor, vcfs, controls, union -> [[id: donor, region: region], vcfs, controls, union] },
        score_tool
    )

    // each donor's tier-A sites and union table, per region
    def ch_donors = ch_tier_a.map { meta, vcf -> [meta.region, meta.id, vcf] }
        .join(UNION_TIERS.out.sites.map { meta, tsv -> [meta.region, meta.id, tsv] }, by: [0, 1], failOnMismatch: true)

    // the per-site totals over all donors that Eq. eb needs (K own tier-A, R ref gaps), per region, donors in name order
    UNION_SITE_COUNTS(
        ch_union.map { meta, vcf, tbi -> [meta.region, meta, vcf, tbi] }
            .combine(ch_donors.map { region, donor, tier_a, table -> [region, [donor, tier_a, table]] }
                .groupTuple(sort: { x, y -> x[0] <=> y[0] }).map { region, rows -> [region] + rows.transpose() }, by: 0)
            .map { _region, meta, vcf, tbi, donors, tier_as, tables -> [meta, vcf, tbi, donors, tier_as, tables] },
        fill_tool
    )

    // each donor's allele at every union site of a region (Eq. eb), one task per donor x region
    FILL_DONOR_ALLELES(
        ch_donors.combine(ch_union.map { meta, vcf, tbi -> [meta.region, vcf, tbi] }, by: 0)
            .combine(UNION_SITE_COUNTS.out.tsv.map { meta, tsv -> [meta.region, tsv] }, by: 0)
            .map { region, donor, tier_a, table, union, tbi, counts -> [[id: donor, region: region], union, tbi, tier_a, table, counts] },
        fill_tool
    )

    // the donors in one VCF per region, in name order (the module sorts its inputs by file name)
    DONOR_ALLELES_MERGE(
        FILL_DONOR_ALLELES.out.vcf.map { meta, vcf, tbi -> [meta.region, vcf, tbi] }.groupTuple()
            .map { region, vcfs, tbis -> [[id: 'donor_alleles', region: region], vcfs, tbis, []] },
        ch_fasta
    )

    emit:
    union         = ch_union                                                                           // channel: [ meta, vcf.gz, tbi ], one per region
    donor_alleles = DONOR_ALLELES_MERGE.out.vcf.join(DONOR_ALLELES_MERGE.out.index, failOnMismatch: true) // channel: [ meta, vcf.gz, tbi ], one per region
}
