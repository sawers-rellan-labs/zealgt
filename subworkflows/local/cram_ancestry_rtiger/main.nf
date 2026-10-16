include { BCFTOOLS_VIEW as DONOR_SUBSET       } from '../../../modules/nf-core/bcftools/view/main'
include { BCFTOOLS_VIEW as DONOR_ALT_SITES    } from '../../../modules/nf-core/bcftools/view/main'
include { BCFTOOLS_MPILEUP as COUNT_LINES      } from '../../../modules/nf-core/bcftools/mpileup/main'
include { CALL_ANCESTRY                        } from '../../../modules/local/call_ancestry/main'
include { ANCESTRY_GRID                        } from '../../../modules/local/ancestry_grid/main'
include { BCFTOOLS_VIEW as ANCESTRY_VCF_INDEX  } from '../../../modules/nf-core/bcftools/view/main'

workflow CRAM_ANCESTRY_RTIGER {
    take:
    ch_donors        // channel: [ region, donor id ], one per donor x region
    ch_donor_alleles // channel: [ meta, vcf.gz, tbi ], every donor's allele at every union site, one per region
    ch_union     // channel: [ meta, vcf.gz, tbi ], the union sites, one per region
    ch_cram      // channel: [ meta, cram, crai ], meta.role, meta.donor
    ch_fasta     // channel: [ meta, fasta, fai ]
    genetic_map  // file or []: chr, bp, cm; [] = nilHMM's bundled v5 map
    call_tool    // file: bin/call_ancestry.R
    grid_tool    // file: bin/write_ancestry_grid.R

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

    // one RTIGER call per donor x region, its lines' counts at its markers
    CALL_ANCESTRY(
        COUNT_LINES.out.vcf.map { meta, vcf -> [meta.donor, meta.region, vcf] }.groupTuple(by: [0, 1])
            .join(ch_donor_sites, by: [0, 1], failOnMismatch: true)
            .map { donor, region, vcfs, markers -> [[id: donor, region: region], markers, vcfs] },
        call_tool
    )

    // one grid per region from its union, every donor's segments read at it, donors in name order
    ANCESTRY_GRID(
        ch_union.map { meta, vcf, tbi -> [meta.region, meta, vcf, tbi] }
            .combine(CALL_ANCESTRY.out.segments.map { meta, bed -> [meta.region, [meta.id, bed]] }
                .groupTuple(sort: { x, y -> x[0] <=> y[0] }).map { region, rows -> [region] + rows.transpose() }, by: 0)
            .map { _region, meta, vcf, tbi, donors, beds -> [meta, vcf, tbi, donors, beds] },
        genetic_map,
        grid_tool
    )

    // each donor's VCF compressed and indexed
    ANCESTRY_VCF_INDEX(
        ANCESTRY_GRID.out.vcf.flatMap { _meta, vcfs -> [vcfs].flatten().collect { v -> [[id: v.name - ~/\.vcf$/], v, []] } },
        [], [], []
    )

    emit:
    segments = CALL_ANCESTRY.out.segments                                       // channel: [ meta, segments.bed ], one per donor x region
    dropped  = CALL_ANCESTRY.out.dropped                                        // channel: [ meta, dropped_lines.tsv ], one per donor x region
    checks   = CALL_ANCESTRY.out.line_checks                                    // channel: [ meta, line_checks.tsv ], one per donor x region
    grid     = ANCESTRY_GRID.out.grid                                           // channel: [ meta, grid.tsv ], one per region
    rqtl     = ANCESTRY_GRID.out.rqtl                                           // channel: [ meta, [ rqtl.csv ] ], one per region
    vcf      = ANCESTRY_VCF_INDEX.out.vcf.join(ANCESTRY_VCF_INDEX.out.index, failOnMismatch: true) // channel: [ meta, vcf.gz, tbi ], one per donor x region
}
