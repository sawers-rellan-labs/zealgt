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

include { DEMULTIPLEX } from './workflows/demultiplex'
include { ALIGNMENT   } from './workflows/alignment'
include { PIPELINE_INITIALISATION } from './subworkflows/local/utils_nfcore_zealgt_pipeline'
include { PIPELINE_COMPLETION     } from './subworkflows/local/utils_nfcore_zealgt_pipeline'
include { softwareVersionsToYAML  } from './subworkflows/nf-core/utils_nfcore_pipeline'

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
    // software versions of every task, from the versions topic, into pipeline_info
    def topic_versions = channel.topic("versions")
        .distinct()
        .branch { entry ->
            versions_file: entry instanceof Path
            versions_tuple: true
        }
    def topic_versions_string = topic_versions.versions_tuple
        .map { process, tool, version ->
            [ process[process.lastIndexOf(':')+1..-1], "  ${tool}: ${version}" ]
        }
        .groupTuple(by:0)
        .map { process, tool_versions ->
            tool_versions.unique().sort()
            "${process}:\n${tool_versions.join('\n')}"
        }
    def ch_collated_versions = softwareVersionsToYAML(topic_versions.versions_file)
        .mix(topic_versions_string)
        .collectFile(
            storeDir: "${params.outdir}/pipeline_info",
            name:  'zealgt_software_'  + 'mqc_'  + 'versions.yml',
            sort: true, newLine: true
        )

    // the --step workflow runs; the other one's outputs stay empty
    def ch_fastq = channel.empty()
    def ch_cram = channel.empty()
    def ch_cram_qc = channel.empty()
    def ch_multiqc_report = channel.empty()
    if (params.step == 'demultiplex') {
        DEMULTIPLEX(samplesheet, params.head)
        ch_fastq = DEMULTIPLEX.out.fastq
    } else {
        ALIGNMENT (
            samplesheet,
            params.head,
            params.fasta,
            params.minibwa_index,
            ch_collated_versions,
            params.multiqc_config,
            params.multiqc_logo,
            params.multiqc_methods_description,
        )
        ch_cram = ALIGNMENT.out.cram
        ch_cram_qc = ALIGNMENT.out.cram_qc
        ch_multiqc_report = ALIGNMENT.out.multiqc_report
    }

    emit:
    multiqc_report = ch_multiqc_report // channel: /path/to/multiqc_report.html
    fastq          = ch_fastq          // channel: [ sample_id:, fastq_1:, fastq_2:, library:, lanes:, kit: ], one per sample
    cram           = ch_cram           // channel: [ meta, cram, crai ], one per sample
    cram_qc        = ch_cram_qc        // channel: [ meta, file ], several per sample
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
        params.step,
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
    fastq = SAWERSRELLANLABS_ZEALGT.out.fastq
    // CRAMs and their QC always, to permanent storage
    cram = SAWERSRELLANLABS_ZEALGT.out.cram
    cram_qc = SAWERSRELLANLABS_ZEALGT.out.cram_qc
}

output {
    // per-sample FASTQs and the samplesheet ALIGNMENT reads, with the published paths
    fastq {
        // off for alignment runs: an empty channel still writes an empty index over a demultiplex run's sheet
        enabled params.step == 'demultiplex'
        path { r ->
            r.fastq_1 >> "fastq/${r.sample_id}/${r.sample_id}_R1.fastq.gz"
            r.fastq_2 >> "fastq/${r.sample_id}/${r.sample_id}_R2.fastq.gz"
        }
        index {
            path 'fastq/samplesheet.csv'
            header true
        }
    }
    // copied, not linked: the store is another filesystem and outlives work/
    cram {
        path 'cram'
        mode 'copy'
    }
    // QC next to its CRAM
    cram_qc {
        path 'cram'
        mode 'copy'
    }
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    THE END
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
