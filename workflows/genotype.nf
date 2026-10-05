include { CRAM_VARIANT_DISCOVERY_CRISP } from '../subworkflows/local/cram_variant_discovery_crisp/main'
include { SITES_UNION_GAPFILL          } from '../subworkflows/local/sites_union_gapfill/main'
include { samplesheetToList            } from 'plugin/nf-schema'

workflow GENOTYPE {
    take:
    ch_samplesheet     // channel: [ meta, cram, crai, wgs_metrics ], one per sample
    b73_controls       // string: CSV of the B73 reference controls (assets/schema_b73_controls.json)
    fasta              // string: reference FASTA, its .fai next to it
    lowcopy_bed        // string: low-copy BED
    check_sites        // string: VCF of the sites the B73 check filter counts
    max_check_alt_rate // number: B73 checks with a larger share of ALT reads are dropped
    min_mean_coverage  // number: samples under this CollectWgsMetrics MEAN_COVERAGE are dropped

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
        channel.fromList(samplesheetToList(b73_controls, "${projectDir}/assets/schema_b73_controls.json")),
        ch_fasta,
        file(lowcopy_bed, checkIfExists: true),
        file(check_sites, checkIfExists: true),
        max_check_alt_rate,
        file("${projectDir}/bin/score_pooled_likelihood.py", checkIfExists: true),
    )

    SITES_UNION_GAPFILL(
        CRAM_VARIANT_DISCOVERY_CRISP.out.tier_a,
        ch_cram,
        CRAM_VARIANT_DISCOVERY_CRISP.out.controls,
        ch_fasta,
        file("${projectDir}/bin/score_pooled_likelihood.py", checkIfExists: true),
        file("${projectDir}/bin/fill_donor_alleles.py", checkIfExists: true),
    )

    emit:
    discovery_vcf      = CRAM_VARIANT_DISCOVERY_CRISP.out.vcf                // channel: [ meta, vcf.gz, tbi ], one per donor
    discovery_sites    = CRAM_VARIANT_DISCOVERY_CRISP.out.sites              // channel: [ meta, sites.tsv.gz ], one per donor
    dropped_b73_checks = CRAM_VARIANT_DISCOVERY_CRISP.out.dropped_b73_checks // channel: dropped_b73_checks.tsv
    union              = SITES_UNION_GAPFILL.out.union                       // channel: [ meta, vcf.gz, tbi ]
    donor_alleles      = SITES_UNION_GAPFILL.out.donor_alleles               // channel: [ meta, vcf.gz, tbi ]
}
