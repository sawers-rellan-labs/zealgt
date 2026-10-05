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
include { GENOTYPE    } from './workflows/genotype'
include { PIPELINE_INITIALISATION } from './subworkflows/local/utils_nfcore_zealgt_pipeline'
include { PIPELINE_COMPLETION     } from './subworkflows/local/utils_nfcore_zealgt_pipeline'
include { softwareVersionsToYAML  } from './subworkflows/nf-core/utils_nfcore_pipeline'

// typed so that --head, --read_qc and the genotype cuts from the command line arrive as numbers and a boolean
params {
    head: Integer = 0
    read_qc: Boolean = false
    max_check_alt_rate: Float = 0.01
    min_mean_coverage: Float = 0.05
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

    // the --step workflow runs; the other ones' outputs stay empty
    def ch_fastq = channel.empty()
    def ch_cram = channel.empty()
    def ch_cram_qc = channel.empty()
    def ch_multiqc_report = channel.empty()
    def ch_discovery_vcf = channel.empty()
    def ch_discovery_sites = channel.empty()
    def ch_b73_checks = channel.empty()
    if (params.step == 'demultiplex') {
        DEMULTIPLEX(samplesheet, params.head, file(params.multiqc_config ?: "${projectDir}/assets/multiqc_config.yml", checkIfExists: true))
        ch_fastq = DEMULTIPLEX.out.fastq
    } else if (params.step == 'genotype') {
        GENOTYPE(
            samplesheet,
            params.b73_controls,
            params.fasta,
            params.lowcopy_bed,
            params.check_sites,
            params.max_check_alt_rate,
            params.min_mean_coverage,
        )
        ch_discovery_vcf = GENOTYPE.out.discovery_vcf
        ch_discovery_sites = GENOTYPE.out.discovery_sites
        ch_b73_checks = GENOTYPE.out.b73_checks
    } else {
        ALIGNMENT (
            samplesheet,
            params.head,
            params.read_qc,
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
    fastq          = ch_fastq          // channel: [ sample_id:, fastq_1:, fastq_2:, source:, library:, lanes:, kit: ], one per sample
    cram           = ch_cram           // channel: [ meta, cram, crai ], one per sample
    cram_qc        = ch_cram_qc        // channel: [ meta, file ], several per sample
    discovery_vcf   = ch_discovery_vcf   // channel: [ meta, vcf.gz, tbi ], one per donor
    discovery_sites = ch_discovery_sites // channel: [ meta, sites.tsv.gz ], one per donor
    b73_checks      = ch_b73_checks      // channel: b73_checks.tsv
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
    discovery_vcf = SAWERSRELLANLABS_ZEALGT.out.discovery_vcf
    discovery_sites = SAWERSRELLANLABS_ZEALGT.out.discovery_sites
    b73_checks = SAWERSRELLANLABS_ZEALGT.out.b73_checks
}

output {
    // per-sample FASTQs, flat per sequencing batch, and the samplesheet ALIGNMENT reads
    fastq {
        // off for alignment runs: an empty channel still writes an empty index over a demultiplex run's sheet
        enabled params.step == 'demultiplex'
        path { r ->
            r.fastq_1 >> "${r.source}/${r.sample_id}_R1.fastq.gz"
            r.fastq_2 >> "${r.source}/${r.sample_id}_R2.fastq.gz"
        }
        index {
            // one sheet per input sheet, so runs into one outdir keep theirs
            path "samplesheets/${file(params.input).baseName}.csv"
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
    // variant discovery per donor and the dropped B73 checks
    discovery_vcf {
        path 'genotype/discovery'
    }
    discovery_sites {
        path 'genotype/discovery'
    }
    b73_checks {
        path 'genotype/discovery'
    }
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    THE END
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
