include { BCFTOOLS_VIEW as DONOR_SUBSET    } from '../../../modules/nf-core/bcftools/view/main'
include { BCFTOOLS_VIEW as DONOR_ALT_SITES } from '../../../modules/nf-core/bcftools/view/main'
include { BCFTOOLS_MPILEUP as COUNT_LINES   } from '../../../modules/nf-core/bcftools/mpileup/main'

workflow LINE_COUNTS {
    take:
    ch_donors        // channel: [ region, donor id ], one per donor x region
    ch_donor_alleles // channel: [ meta, vcf.gz, tbi ], every donor's allele at every union site, one per region
    ch_union         // channel: [ meta, vcf.gz, tbi ], the union sites, one per region
    ch_cram          // channel: [ meta, cram, crai ], meta.role, meta.donor
    ch_fasta         // channel: [ meta, fasta, fai ]

    main:
    // each donor's markers: the union sites gap filling called ALT for it; -i in a second view, as with -s it tests all samples
    DONOR_SUBSET(
        ch_donors.combine(ch_donor_alleles.map { meta, vcf, tbi -> [meta.region, vcf, tbi] }, by: 0)
            .map { region, donor, vcf, tbi -> [[id: donor, region: region], vcf, tbi] },
        [], [], []
    )
    DONOR_ALT_SITES(DONOR_SUBSET.out.vcf.map { meta, vcf -> [meta, vcf, []] }, [], [], [])
    def ch_donor_sites = DONOR_ALT_SITES.out.vcf.map { meta, vcf -> [meta.id, meta.region, vcf] }

    // a donor's lines counted together at its markers, one VCF per region with a sample per line (named by sample_id)
    COUNT_LINES(
        ch_cram.filter { meta, _cram, _crai -> meta.role == 'nil' }
            .map { meta, cram, crai -> [meta.donor, meta.id, cram, crai] }.groupTuple()
            .combine(ch_donor_sites, by: 0)
            .map { donor, ids, crams, crais, region, vcf -> [[id: donor, region: region, samples: ids], crams, crais, vcf, []] },
        ch_fasta,
        false
    )

    // one record per donor and region: its lines' counts, its markers and the region's union, the rows of the counts sheet
    def ch_counts = COUNT_LINES.out.vcf.map { meta, vcf -> [meta.id, meta.region, vcf] }
        .join(ch_donor_sites, by: [0, 1], failOnMismatch: true)
        .map { donor, region, vcf, markers -> [region, donor, vcf, markers] }
        .combine(ch_union.map { meta, vcf, _tbi -> [meta.region, vcf] }, by: 0)
        .map { region, donor, vcf, markers, union -> [donor: donor, region: region, counts: vcf, markers: markers, union: union] }

    emit:
    counts = ch_counts // channel: [ donor:, region:, counts:, markers:, union: ], one per donor x region
}
