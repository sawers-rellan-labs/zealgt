include { BCFTOOLS_VIEW as DONOR_SUBSET    } from '../../../modules/nf-core/bcftools/view/main'
include { BCFTOOLS_VIEW as DONOR_ALT_SITES } from '../../../modules/nf-core/bcftools/view/main'
include { BCFTOOLS_ISEC as KNOWN_SITES     } from '../../../modules/nf-core/bcftools/isec/main'
include { BCFTOOLS_MPILEUP as COUNT_LINES  } from '../../../modules/nf-core/bcftools/mpileup/main'
include { FILTER_SITE_DEPTH                } from '../../../modules/local/filter_site_depth/main'

workflow LINE_COUNTS {
    take:
    ch_donors        // channel: [ region, donor id ], one per donor x region
    ch_donor_alleles // channel: [ meta, vcf.gz, tbi ], every donor's allele at every union site, one per region
    ch_union         // channel: [ meta, vcf.gz, tbi ], the union sites, one per region
    ch_cram          // channel: [ meta, cram, crai ], meta.role, meta.donor
    ch_fasta         // channel: [ meta, fasta, fai ]
    known_sites      // list: [ vcf.gz, tbi ], the known variants
    depth_tool       // file: bin/filter_site_depth.py

    main:
    // each donor's markers: the union sites gap filling called ALT for it; -i in a second view, as with -s it tests all samples
    DONOR_SUBSET(
        ch_donors.combine(ch_donor_alleles.map { meta, vcf, tbi -> [meta.region, vcf, tbi] }, by: 0)
            .map { region, donor, vcf, tbi -> [[id: donor, region: region], vcf, tbi] },
        [], [], []
    )
    DONOR_ALT_SITES(DONOR_SUBSET.out.vcf.map { meta, vcf -> [meta, vcf, []] }, [], [], [])
    // the markers that are known sites (same CHROM, POS, REF and ALT)
    KNOWN_SITES(
        DONOR_ALT_SITES.out.vcf.join(DONOR_ALT_SITES.out.index, failOnMismatch: true)
            .map { meta, vcf, tbi -> [meta, [vcf, known_sites[0]], [tbi, known_sites[1]], [], [], []] }
    )
    def ch_donor_sites = KNOWN_SITES.out.results.map { meta, dir -> [meta.id, meta.region, dir.resolve('0000.vcf.gz')] }

    // a donor's lines counted together at its markers, one VCF per region with a sample per line (named by sample_id)
    COUNT_LINES(
        ch_cram.filter { meta, _cram, _crai -> meta.role == 'nil' }
            .map { meta, cram, crai -> [meta.donor, meta.id, cram, crai] }.groupTuple()
            .combine(ch_donor_sites, by: 0)
            .map { donor, ids, crams, crais, region, vcf -> [[id: donor, region: region, samples: ids], crams, crais, vcf, []] },
        ch_fasta,
        false
    )
    def ch_counted = COUNT_LINES.out.vcf.map { meta, vcf -> [meta.id, meta.region, vcf] }
        .join(ch_donor_sites, by: [0, 1], failOnMismatch: true)

    // the depth filter per region over all donors' counts (once all are in: groupKey), donors in name order
    def n_donors = ch_donors.map { region, _donor -> [region, 1] }.groupTuple().map { region, ones -> [region, ones.size()] }
    FILTER_SITE_DEPTH(
        ch_counted.map { donor, region, vcf, markers -> [region, donor, vcf, markers] }.combine(n_donors, by: 0)
            .map { region, donor, vcf, markers, n -> [groupKey(region, n), [donor, vcf, markers]] }
            .groupTuple(sort: { x, y -> x[0] <=> y[0] })
            .map { key, rows -> [[id: key.getGroupTarget().replace(':', '_'), region: key.getGroupTarget()]] + rows.transpose() },
        depth_tool
    )
    def ch_markers = FILTER_SITE_DEPTH.out.markers.flatMap { meta, vcfs ->
        [vcfs].flatten().collect { v -> [v.name - ".${meta.id}.markers.vcf", meta.region, v] }
    }

    // one record per donor and region: its lines' counts, its kept markers and the region's union, the rows of the counts sheet
    def ch_counts = ch_counted.map { donor, region, vcf, _markers -> [donor, region, vcf] }
        .join(ch_markers, by: [0, 1], failOnMismatch: true)
        .map { donor, region, vcf, markers -> [region, donor, vcf, markers] }
        .combine(ch_union.map { meta, vcf, _tbi -> [meta.region, vcf] }, by: 0)
        .map { region, donor, vcf, markers, union -> [donor: donor, region: region, counts: vcf, markers: markers, union: union] }

    emit:
    counts = ch_counts // channel: [ donor:, region:, counts:, markers:, union: ], one per donor x region
}
