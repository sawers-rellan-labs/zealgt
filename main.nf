#!/usr/bin/env nextflow
/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    sawers-rellan-labs/zealgt
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    Github : https://github.com/sawers-rellan-labs/zealgt
----------------------------------------------------------------------------------------
*/

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT FUNCTIONS / MODULES / SUBWORKFLOWS / WORKFLOWS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

include { ALIGNMENT } from './workflows/alignment'
include { PIPELINE_INITIALISATION } from './subworkflows/local/utils_nfcore_zealgt_pipeline'
include { PIPELINE_COMPLETION     } from './subworkflows/local/utils_nfcore_zealgt_pipeline'

// typed so that --head from the command line arrives as an integer
params {
    head: Integer = 0
}
/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    NAMED WORKFLOWS FOR PIPELINE
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

//
// WORKFLOW: Run main analysis pipeline depending on type of input
//
workflow SAWERSRELLANLABS_ZEALGT {

    take:
    samplesheet // channel: samplesheet read in from --input

    main:

    //
    // WORKFLOW: Run pipeline
    //
    ALIGNMENT (
        samplesheet,
        params.head,
        params.fasta,
        params.minibwa_index,
        params.multiqc_config,
        params.multiqc_logo,
        params.multiqc_methods_description,
        params.outdir,
    )
    emit:
    multiqc_report = ALIGNMENT.out.multiqc_report // channel: /path/to/multiqc_report.html
    demux_reads    = ALIGNMENT.out.reads          // channel: [ meta, [ R1, R2 ] ], one per sample
    cram           = ALIGNMENT.out.cram           // channel: [ meta, cram, crai ], one per sample
}
/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    RUN MAIN WORKFLOW
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow {

    main:
    //
    // SUBWORKFLOW: Run initialisation tasks
    //
    PIPELINE_INITIALISATION (
        params.version,
        params.validate_params,
        params.monochrome_logs,
        args,
        params.outdir,
        params.input,
        params.help,
        params.help_full,
        params.show_hidden
    )

    //
    // WORKFLOW: Run main workflow
    //
    SAWERSRELLANLABS_ZEALGT (
        PIPELINE_INITIALISATION.out.samplesheet
    )
    //
    // SUBWORKFLOW: Run completion tasks
    //
    PIPELINE_COMPLETION (
        params.monochrome_logs,
    )

    publish:
    // CRAMs always, to permanent storage
    cram = SAWERSRELLANLABS_ZEALGT.out.cram
    // each stage's result, published only during development
    demux_reads = params.publish_intermediates ? SAWERSRELLANLABS_ZEALGT.out.demux_reads : channel.empty()
}

output {
    demux_reads {
        // one name for one-lane (fqtk) and joined (cat/fastq) samples
        path { meta, reads ->
            reads[0] >> "demux/${meta.id}/${meta.id}_R1.fastq.gz"
            reads[1] >> "demux/${meta.id}/${meta.id}_R2.fastq.gz"
        }
    }
    // copied, not linked: the store is another filesystem and outlives work/
    cram {
        path 'cram'
        mode 'copy'
    }
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    THE END
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
