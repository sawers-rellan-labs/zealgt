include { BCFTOOLS_MPILEUP as COUNT_LINES      } from '../../../modules/nf-core/bcftools/mpileup/main'
include { CALL_ANCESTRY                        } from '../../../modules/local/call_ancestry/main'
include { ANCESTRY_GRID                        } from '../../../modules/local/ancestry_grid/main'
include { BCFTOOLS_VIEW as ANCESTRY_VCF_INDEX  } from '../../../modules/nf-core/bcftools/view/main'

workflow CRAM_ANCESTRY_RTIGER {
    take:
    ch_tier_a    // channel: [ meta, tier_a.vcf ], one per donor
    ch_union     // channel: [ meta, vcf.gz, tbi ], the union sites
    ch_cram      // channel: [ meta, cram, crai ], meta.role, meta.donor
    ch_fasta     // channel: [ meta, fasta, fai ]
    genetic_map  // file or []: chr, bp, cm; [] = nilHMM's bundled v5 map
    call_tool    // file: bin/call_ancestry.R
    grid_tool    // file: bin/write_ancestry_grid.R

    main:
    def ch_donor_sites = ch_tier_a.map { meta, vcf -> [meta.id, vcf] }

    // each line counted at its donor's tier-A sites
    COUNT_LINES(
        ch_cram.filter { meta, _cram, _crai -> meta.role == 'nil' }
            .map { meta, cram, crai -> [meta.donor, meta, cram, crai] }
            .combine(ch_donor_sites, by: 0)
            .map { _donor, meta, cram, crai, vcf -> [meta, cram, crai, vcf, []] },
        ch_fasta,
        false
    )

    // one RTIGER call per donor, its lines' counts at its tier-A sites
    CALL_ANCESTRY(
        COUNT_LINES.out.vcf.map { meta, vcf -> [meta.donor, vcf] }.groupTuple()
            .join(ch_donor_sites, failOnMismatch: true)
            .map { donor, vcfs, tier_a -> [[id: donor], tier_a, vcfs] },
        call_tool
    )

    // one grid from the union, every donor's segments read at it, donors in name order
    ANCESTRY_GRID(
        ch_union.combine(
            CALL_ANCESTRY.out.segments.toSortedList { x, y -> x[0].id <=> y[0].id }
                .map { rows -> [rows.collect { r -> r[0].id }, rows.collect { r -> r[1] }] }
        ).map { meta, vcf, tbi, donors, beds -> [meta, vcf, tbi, donors, beds] },
        genetic_map,
        grid_tool
    )

    // each donor's VCF compressed and indexed
    ANCESTRY_VCF_INDEX(
        ANCESTRY_GRID.out.vcf.flatMap { _meta, vcfs -> [vcfs].flatten().collect { v -> [[id: v.name - ~/\.vcf$/], v, []] } },
        [], [], []
    )

    emit:
    segments = CALL_ANCESTRY.out.segments                                       // channel: [ meta, segments.bed ], one per donor
    dropped  = CALL_ANCESTRY.out.dropped                                        // channel: [ meta, dropped_lines.tsv ], one per donor
    grid     = ANCESTRY_GRID.out.grid                                           // channel: [ meta, grid.tsv ]
    rqtl     = ANCESTRY_GRID.out.rqtl                                           // channel: [ meta, [ rqtl.csv ] ]
    vcf      = ANCESTRY_VCF_INDEX.out.vcf.join(ANCESTRY_VCF_INDEX.out.index, failOnMismatch: true) // channel: [ meta, vcf.gz, tbi ], one per donor
}
