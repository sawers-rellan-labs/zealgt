include { BCFTOOLS_MPILEUP as RECOUNT_LINES     } from '../../../modules/nf-core/bcftools/mpileup/main'
include { BCFTOOLS_MPILEUP as COUNT_TAXON_UNION } from '../../../modules/nf-core/bcftools/mpileup/main'
include { FLAG_MARKER_SITES                     } from '../../../modules/local/flag_marker_sites/main'

workflow UNION_MARKERS {
    take:
    ch_rows     // channel: [ meta, counts.vcf.gz, markers.vcf, union.vcf.gz ], a variant-calling counts sheet, one per donor x region
    ch_cram     // channel: [ meta, cram, crai ], meta.role, meta.donor
    ch_fasta    // channel: [ meta, fasta, fai ]
    known_sites // tuple: [ vcf.gz, tbi ], wideseq
    tool        // file: bin/flag_marker_sites.py

    main:
    // each donor's lines; a donor's taxon is its ID's prefix (Zx.0580_P2: Zx)
    def ch_lines = ch_cram.filter { meta, _cram, _crai -> meta.role == 'nil' }
        .map { meta, cram, crai -> [meta.donor, meta.id, cram, crai] }.groupTuple()
    def ch_row = ch_rows.map { meta, counts, markers, union -> [meta.donor, meta.region, meta.donor.tokenize('.')[0], counts, markers, union] }

    // the donor's lines at its markers, MAPQ >= 60 / BQ >= 30
    RECOUNT_LINES(
        ch_lines.combine(ch_row, by: 0)
            .map { donor, ids, crams, crais, region, _taxon, _counts, markers, _union -> [[id: donor, region: region, samples: ids], crams, crais, markers, []] },
        ch_fasta,
        false
    )

    // per taxon x region, once all its donors' recounts are in: site flags, each donor's kept markers, the taxon union
    def ch_n = ch_row.map { _donor, region, taxon, _c, _m, _u -> [[taxon, region], 1] }.groupTuple().map { key, ones -> [key, ones.size()] }
    FLAG_MARKER_SITES(
        RECOUNT_LINES.out.vcf.map { meta, vcf -> [meta.id, meta.region, vcf] }
            .join(ch_row, by: [0, 1], failOnMismatch: true)
            .map { donor, region, recount, taxon, counts, markers, _union -> [[taxon, region], donor, recount, markers, counts] }
            .combine(ch_n, by: 0)
            .map { key, donor, recount, markers, counts, n -> [groupKey(key, n), donor, recount, markers, counts] }
            .groupTuple()
            .map { key, donors, recounts, markers, counts -> [[id: key[0], region: key[1], donors: donors], recounts, markers, counts] },
        known_sites,
        tool
    )

    // each donor's lines at its taxon's union, MAPQ >= 60 / BQ >= 30
    def ch_union = FLAG_MARKER_SITES.out.union.map { meta, vcf -> [meta.id, meta.region, vcf] }
    COUNT_TAXON_UNION(
        ch_row.map { donor, region, taxon, _c, _m, _u -> [taxon, region, donor] }
            .combine(ch_union, by: [0, 1])
            .map { _taxon, region, donor, union -> [donor, region, union] }
            .combine(ch_lines, by: 0)
            .map { donor, region, union, ids, crams, crais -> [[id: donor, region: region, samples: ids], crams, crais, union, []] },
        ch_fasta,
        false
    )

    // the counts sheet's rows: the union counts, the taxon union as markers, the source run's union for the grid
    def ch_counts = COUNT_TAXON_UNION.out.vcf.map { meta, vcf -> [meta.id, meta.region, vcf] }
        .join(ch_row, by: [0, 1], failOnMismatch: true)
        .map { donor, region, vcf, taxon, _counts, _markers, union -> [taxon, region, donor, vcf, union] }
        .combine(ch_union, by: [0, 1])
        .map { _taxon, region, donor, vcf, union, markers -> [donor: donor, region: region, counts: vcf, markers: markers, union: union] }

    emit:
    counts = ch_counts                     // channel: [ donor:, region:, counts:, markers:, union: ], one per donor x region
    tables = FLAG_MARKER_SITES.out.tables  // channel: [ meta, [ flags.tsv, marker_counts.tsv ] ], one per taxon x region
}
