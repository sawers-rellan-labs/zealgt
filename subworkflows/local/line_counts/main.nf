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

    // each line counted at its donor's markers, per region
    COUNT_LINES(
        ch_cram.filter { meta, _cram, _crai -> meta.role == 'nil' }
            .map { meta, cram, crai -> [meta.donor, meta, cram, crai] }
            .combine(ch_donor_sites, by: 0)
            .map { _donor, meta, cram, crai, region, vcf -> [meta + [region: region], cram, crai, vcf, []] },
        ch_fasta,
        false
    )

    // one record per line and region: its counts, its donor's markers and the region's union, the rows of the counts sheet
    def ch_counts = COUNT_LINES.out.vcf.map { meta, vcf -> [meta.donor, meta.region, meta, vcf] }
        .combine(ch_donor_sites, by: [0, 1])
        .map { _donor, region, meta, vcf, markers -> [region, meta, vcf, markers] }
        .combine(ch_union.map { meta, vcf, _tbi -> [meta.region, vcf] }, by: 0)
        .map { region, meta, vcf, markers, union ->
            [sample_id: meta.id, donor: meta.donor, region: region, counts: vcf, markers: markers, union: union]
        }

    emit:
    counts = ch_counts // channel: [ sample_id:, donor:, region:, counts:, markers:, union: ], one per line x region
}
