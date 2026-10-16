include { CALL_ANCESTRY                       } from '../../../modules/local/call_ancestry/main'
include { ANCESTRY_GRID                       } from '../../../modules/local/ancestry_grid/main'
include { BCFTOOLS_VIEW as ANCESTRY_VCF_INDEX } from '../../../modules/nf-core/bcftools/view/main'

workflow ANCESTRY_RTIGER {
    take:
    ch_counts   // channel: [ meta, counts.vcf, markers.vcf, union.vcf.gz ], meta.id (line), meta.donor, meta.region
    fit         // string: chromosome (one RTIGER fit per donor x region) | genome (one per donor over its regions)
    genetic_map // file or []: chr, bp, cm; [] = nilHMM's bundled v5 map
    call_tool   // file: bin/call_ancestry.R
    grid_tool   // file: bin/write_ancestry_grid.R

    main:
    // one RTIGER call per donor and fit unit (the region, or 'genome' for all of them), its lines' counts at its markers
    CALL_ANCESTRY(
        ch_counts.map { meta, counts, markers, _union -> [meta.donor, fit == 'genome' ? 'genome' : meta.region, counts, markers] }
            .groupTuple(by: [0, 1])
            .map { donor, u, counts, markers -> [[id: donor, region: u], markers.unique(), counts] },
        call_tool
    )

    // one grid per region from its union, every donor's segments of the unit holding the region, donors in name order
    ANCESTRY_GRID(
        ch_counts.map { meta, _counts, _markers, union -> [meta.region, meta.donor, union] }.unique()
            .map { region, donor, union -> [donor, fit == 'genome' ? 'genome' : region, region, union] }
            .combine(CALL_ANCESTRY.out.segments.map { meta, bed -> [meta.id, meta.region, bed] }, by: [0, 1])
            .map { donor, _u, region, union, bed -> [region, union, [donor, bed]] }
            .groupTuple(by: [0, 1], sort: { x, y -> x[0] <=> y[0] })
            .map { region, union, rows -> [[id: region.replace(':', '_'), region: region], union, [], rows*.getAt(0), rows*.getAt(1)] },
        genetic_map,
        grid_tool
    )

    // each donor's VCF compressed and indexed
    ANCESTRY_VCF_INDEX(
        ANCESTRY_GRID.out.vcf.flatMap { _meta, vcfs -> [vcfs].flatten().collect { v -> [[id: v.name - ~/\.vcf$/], v, []] } },
        [], [], []
    )

    emit:
    segments = CALL_ANCESTRY.out.segments                                       // channel: [ meta, segments.bed ], one per donor x fit unit
    dropped  = CALL_ANCESTRY.out.dropped                                        // channel: [ meta, dropped_lines.tsv ], one per donor x fit unit
    checks   = CALL_ANCESTRY.out.line_checks                                    // channel: [ meta, line_checks.tsv ], one per donor x fit unit
    grid     = ANCESTRY_GRID.out.grid                                           // channel: [ meta, grid.tsv ], one per region
    rqtl     = ANCESTRY_GRID.out.rqtl                                           // channel: [ meta, [ rqtl.csv ] ], one per region
    vcf      = ANCESTRY_VCF_INDEX.out.vcf.join(ANCESTRY_VCF_INDEX.out.index, failOnMismatch: true) // channel: [ meta, vcf.gz, tbi ], one per donor x region
}
