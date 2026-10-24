include { ANCESTRY_RTIGER } from '../subworkflows/local/ancestry_rtiger/main'

workflow ANCESTRY {
    take:
    ch_samplesheet // channel: [ meta, counts.vcf.gz, markers.vcf, union.vcf.gz ], one per donor x region (a VARIANT_CALLING counts sheet)
    fit            // string: chromosome | genome, the RTIGER fit unit
    genetic_map    // string or null: TSV chr, bp, cm for the ancestry grid; null = nilHMM's bundled v5 map

    main:
    ANCESTRY_RTIGER(
        ch_samplesheet,
        fit,
        genetic_map ? file(genetic_map, checkIfExists: true) : [],
        file("${projectDir}/bin/call_ancestry.R", checkIfExists: true),
        file("${projectDir}/bin/write_ancestry_grid.R", checkIfExists: true),
    )

    emit:
    ancestry = ANCESTRY_RTIGER.out.segments.mix( // channel: [ meta, files ], the grid and each donor's outputs
        ANCESTRY_RTIGER.out.dropped, ANCESTRY_RTIGER.out.checks, ANCESTRY_RTIGER.out.markers, ANCESTRY_RTIGER.out.grid, ANCESTRY_RTIGER.out.rqtl, ANCESTRY_RTIGER.out.vcf
    )
}
