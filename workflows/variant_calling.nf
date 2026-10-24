include { CRAM_VARIANT_DISCOVERY_CRISP } from '../subworkflows/local/cram_variant_discovery_crisp/main'
include { SITES_UNION_GAPFILL          } from '../subworkflows/local/sites_union_gapfill/main'
include { LINE_COUNTS                  } from '../subworkflows/local/line_counts/main'
include { samplesheetToList            } from 'plugin/nf-schema'

workflow VARIANT_CALLING {
    take:
    ch_samplesheet     // channel: [ meta, cram, crai, wgs_metrics ], one per sample
    b73_controls       // string: CSV of the B73 reference controls (assets/schema_b73_controls.json)
    fasta              // string: reference FASTA, its .fai next to it
    lowcopy_bed        // string: low-copy BED
    b73_checks         // string: CSV of the QC-PASS B73 checks (sample_id)
    known_sites        // string: sites VCF of known variants, its .tbi next to it
    min_mean_coverage  // number: samples under this CollectWgsMetrics MEAN_COVERAGE are dropped
    regions            // string: comma-separated regions, each called on its own (chr9,chr10 or chr10:1-20000000)

    main:
    // excluded rows and samples under the coverage floor dropped first; MEAN_COVERAGE is in the metrics table's first row
    def ch_cram = ch_samplesheet
        .filter { meta, _cram, _crai, _metrics -> !meta.exclude }
        .splitCsv(elem: 3, sep: '\t', skip: 6, header: true, limit: 1)
        .filter { _meta, _cram, _crai, metrics -> (metrics.MEAN_COVERAGE as double) >= min_mean_coverage }
        .map { meta, cram, crai, _metrics -> [meta, cram, crai] }

    def ch_fasta = channel.value([[id: file(fasta).name], file(fasta, checkIfExists: true), file("${fasta}.fai", checkIfExists: true)])
    CRAM_VARIANT_DISCOVERY_CRISP(
        ch_cram,
        channel.fromList(regions.tokenize(',')).unique(), // a region given twice runs once
        channel.fromList(samplesheetToList(b73_controls, "${projectDir}/assets/schema_b73_controls.json")),
        channel.fromPath(b73_checks, checkIfExists: true).splitCsv(header: true).map { row -> row.sample_id },
        ch_fasta,
        file(lowcopy_bed, checkIfExists: true),
        file("${projectDir}/bin/score_pooled_likelihood.py", checkIfExists: true),
    )

    SITES_UNION_GAPFILL(
        CRAM_VARIANT_DISCOVERY_CRISP.out.tier_a,
        ch_cram,
        CRAM_VARIANT_DISCOVERY_CRISP.out.controls,
        CRAM_VARIANT_DISCOVERY_CRISP.out.n_controls,
        ch_fasta,
        file("${projectDir}/bin/score_pooled_likelihood.py", checkIfExists: true),
        file("${projectDir}/bin/fill_donor_alleles.py", checkIfExists: true),
    )

    LINE_COUNTS(
        CRAM_VARIANT_DISCOVERY_CRISP.out.tier_a.map { meta, _vcf -> [meta.region, meta.id] },
        SITES_UNION_GAPFILL.out.donor_alleles,
        SITES_UNION_GAPFILL.out.union,
        ch_cram,
        ch_fasta,
        [file(known_sites, checkIfExists: true), file("${known_sites}.tbi", checkIfExists: true)],
        file("${projectDir}/bin/filter_site_depth.py", checkIfExists: true),
    )

    emit:
    discovery_vcf      = CRAM_VARIANT_DISCOVERY_CRISP.out.vcf                // channel: [ meta, vcf.gz, tbi ], one per donor x region
    discovery_sites    = CRAM_VARIANT_DISCOVERY_CRISP.out.sites              // channel: [ meta, sites.tsv.gz ], one per donor x region
    union              = SITES_UNION_GAPFILL.out.union                       // channel: [ meta, vcf.gz, tbi ], one per region
    donor_alleles      = SITES_UNION_GAPFILL.out.donor_alleles               // channel: [ meta, vcf.gz, tbi ], one per region
    counts             = LINE_COUNTS.out.counts                              // channel: [ donor:, region:, counts:, markers:, union: ], one per donor x region
}
