include { UNION_MARKERS      } from '../subworkflows/local/union_markers/main'
include { samplesheetToList } from 'plugin/nf-schema'

workflow MARKERS {
    take:
    ch_rows           // channel: [ meta, counts.vcf.gz, markers.vcf, union.vcf.gz ], a variant-calling counts sheet
    crams             // string: that run's CRAM sheet (assets/schema_cram.json)
    fasta             // string: reference FASTA, its .fai next to it
    known_sites       // string: wideseq VCF, its .tbi next to it
    min_mean_coverage // number: lines under this CollectWgsMetrics MEAN_COVERAGE are dropped, as in variant calling

    main:
    // the lines as variant calling took them: excluded rows and samples under the coverage floor dropped
    def ch_cram = channel.fromList(samplesheetToList(crams, "${projectDir}/assets/schema_cram.json"))
        .filter { meta, _cram, _crai, _metrics -> !meta.exclude }
        .splitCsv(elem: 3, sep: '\t', skip: 6, header: true, limit: 1)
        .filter { _meta, _cram, _crai, metrics -> (metrics.MEAN_COVERAGE as double) >= min_mean_coverage }
        .map { meta, cram, crai, _metrics -> [meta, cram, crai] }

    UNION_MARKERS(
        ch_rows,
        ch_cram,
        channel.value([[id: file(fasta).name], file(fasta, checkIfExists: true), file("${fasta}.fai", checkIfExists: true)]),
        [file(known_sites, checkIfExists: true), file("${known_sites}.tbi", checkIfExists: true)],
        file("${projectDir}/bin/flag_marker_sites.py", checkIfExists: true),
    )

    emit:
    counts = UNION_MARKERS.out.counts // channel: [ donor:, region:, counts:, markers:, union: ], one per donor x region
    tables = UNION_MARKERS.out.tables // channel: [ meta, [ flags.tsv, marker_counts.tsv ] ], one per taxon x region
}
