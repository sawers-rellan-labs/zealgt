include { SEQUALI } from '../../../modules/nf-core/sequali/main'
include { MULTIQC } from '../../../modules/nf-core/multiqc/main'

workflow FASTQ_SEQUALI {

    take:
    ch_reads       // channel: [ meta, [ R1, R2 ] ], one per sample
    multiqc_config // file: MultiQC config

    main:
    SEQUALI(ch_reads)

    // one read-QC report over every sample's Sequali JSON; MultiQC's Sequali module divides by the read count, so
    // samples without reads stay out of the report (their own Sequali files are still published); stubs write empty JSON
    MULTIQC(
        SEQUALI.out.json
            .filter { _meta, json -> json.size() == 0 || new groovy.json.JsonSlurper().parse(json).summary.total_reads > 0 }
            .map { _meta, json -> json }
            .collect()
            .map { files -> [[id: 'reads'], files, multiqc_config, [], [], []] }
    )

    emit:
    html    = SEQUALI.out.html    // channel: [ meta, html ], one per sample
    json    = SEQUALI.out.json    // channel: [ meta, json ], one per sample
    report  = MULTIQC.out.report  // channel: [ meta, html ]
    data    = MULTIQC.out.data    // channel: [ meta, multiqc_data ]
}
