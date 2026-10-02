/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT MODULES / SUBWORKFLOWS / FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
include { EXTRACT_LANE           } from '../modules/local/extract_lane/main'
include { FGBIO_DEMUXFASTQS      } from '../modules/local/fgbio/demuxfastqs/main'
include { CAT_FASTQ              } from '../modules/nf-core/cat/fastq/main'
include { MULTIQC                } from '../modules/nf-core/multiqc/main'
include { paramsSummaryMap       } from 'plugin/nf-schema'
include { paramsSummaryMultiqc   } from '../subworkflows/nf-core/utils_nfcore_pipeline'
include { softwareVersionsToYAML } from '../subworkflows/nf-core/utils_nfcore_pipeline'
include { methodsDescriptionText } from '../subworkflows/local/utils_nfcore_zealgt_pipeline'

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    RUN MAIN WORKFLOW
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow ALIGNMENT {

    take:
    ch_samplesheet // channel: [ meta, raw_location, raw_r1, raw_r2 ], one per sample
    head_pairs     // integer: first N read pairs per library, 0 = all
    multiqc_config
    multiqc_logo
    multiqc_methods_description
    outdir

    main:

    def ch_versions = channel.empty()
    def ch_multiqc_files = channel.empty()
    // one fgbio sample sheet per library; FlexPrep barcodes are the R1 and R2 barcodes joined
    def ch_sheets = ch_samplesheet
        .map { meta, _loc, _r1, _r2 -> ["${meta.library}.csv", "${meta.id},${meta.id},${meta.barcode_r1}${meta.barcode_r2 ?: ''}\n"] }
        .collectFile(seed: "Sample_Id,Sample_Name,Sample_Barcode\n", sort: true)
        .map { sheet -> [sheet.baseName, sheet] }

    // one entry per library lane: [ meta, R1 source, R2 source, R1 tar member, R2 tar member ]
    // tar lanes come from raw_r1/raw_r2 (<tar>:<member>;...), plain lanes from <raw_location>/*_{1,2}.fq.gz
    def ch_lanes = ch_samplesheet
        .map { meta, loc, r1, r2 -> [[id: meta.library, library: meta.library, kit: meta.kit], loc, r1 ?: '', r2 ?: ''] }
        .unique()
        .flatMap { lib, loc, r1, r2 ->
            def lanes = r1
                ? [r1.tokenize(';'), r2.tokenize(';')].transpose().collect { a, b ->
                    def (t1, m1) = a.tokenize(':')
                    def (t2, m2) = b.tokenize(':')
                    [file(m1).name - ~/_R1_\d+\.fastq\.gz$/, file("${loc}/${t1}"), file("${loc}/${t2}"), m1, m2]
                }
                : files("${loc}/*_{1,2}.fq.gz").sort().collate(2).collect { f1, f2 -> [f1.name - ~/_1\.fq\.gz$/, f1, f2, '', ''] }
            lanes.collect { lane, s1, s2, m1, m2 -> [lib + [id: "${lib.id}.${lane}", lane: lane, n_lanes: lanes.size()], s1, s2, m1, m2] }
        }
        .branch { _meta, _s1, _s2, m1, _m2 ->
            extract: m1 || head_pairs
            direct: true
        }

    // tar members and --head lanes become real files first (fgbio reads its inputs twice)
    EXTRACT_LANE(
        ch_lanes.extract.map { meta, s1, s2, m1, m2 -> [meta, s1, s2, m1, m2, head_pairs ? Math.ceil(head_pairs / meta.n_lanes) as long : 0] }
    )
    def ch_lane_reads = ch_lanes.direct
        .map { meta, s1, s2, _m1, _m2 -> [meta, s1, s2] }
        .mix(EXTRACT_LANE.out.reads)

    FGBIO_DEMUXFASTQS(
        ch_lane_reads
            .map { meta, r1, r2 -> [meta.library, meta, r1, r2] }
            .combine(ch_sheets, by: 0)
            .map { _library, meta, r1, r2, sheet -> [meta, r1, r2, sheet] }
    )

    // per sample: its lane pairs in lane order (R1, R2, R1, R2, ...), released when all lanes are in
    def ch_sample_lanes = FGBIO_DEMUXFASTQS.out.reads
        .flatMap { meta, files ->
            files.groupBy { f -> f.name - ~/_R[12]\.fastq\.gz$/ }
                .collect { sample, pair -> [groupKey(sample, meta.n_lanes), meta.lane, pair.sort { f -> f.name }] }
        }
        .groupTuple()
        .map { sample, lanes, pairs -> [sample.toString(), [lanes, pairs].transpose().sort { l -> l[0] }.collect { l -> l[1] }.flatten()] }
        .join(ch_samplesheet.map { meta, _loc, _r1, _r2 -> [meta.id, meta] })
        .map { _id, reads, meta -> [meta + [single_end: false], reads] }
        .branch { _meta, reads ->
            one_lane: reads.size() == 2
            lanes: true
        }

    CAT_FASTQ(ch_sample_lanes.lanes)
    def ch_reads = ch_sample_lanes.one_lane.mix(CAT_FASTQ.out.reads)

    //
    // Collate and save software versions
    //
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

    def ch_collated_versions = softwareVersionsToYAML(ch_versions.mix(topic_versions.versions_file))
        .mix(topic_versions_string)
        .collectFile(
            storeDir: "${outdir}/pipeline_info",
            name:  'zealgt_software_'  + 'mqc_'  + 'versions.yml',
            sort: true,
            newLine: true
        )

    //
    // MODULE: MultiQC
    //
    ch_multiqc_files = ch_multiqc_files.mix(ch_collated_versions)
    def ch_summary_params = paramsSummaryMap(workflow, parameters_schema: "nextflow_schema.json")
    def ch_workflow_summary = channel.value(paramsSummaryMultiqc(ch_summary_params))
    ch_multiqc_files = ch_multiqc_files.mix(ch_workflow_summary.collectFile(name: 'workflow_summary_mqc.yaml'))
    def ch_multiqc_custom_methods_description = multiqc_methods_description
        ? file(multiqc_methods_description, checkIfExists: true)
        : file("${projectDir}/assets/methods_description_template.yml", checkIfExists: true)
    def ch_methods_description = channel.value(methodsDescriptionText(ch_multiqc_custom_methods_description))
    ch_multiqc_files = ch_multiqc_files.mix(ch_methods_description.collectFile(name: 'methods_description_mqc.yaml', sort: true))
    MULTIQC(
        ch_multiqc_files.flatten().collect().map { files ->
            [
                [id: 'zealgt'],
                files,
                multiqc_config
                    ? file(multiqc_config, checkIfExists: true)
                    : file("${projectDir}/assets/multiqc_config.yml", checkIfExists: true),
                multiqc_logo ? file(multiqc_logo, checkIfExists: true) : [],
                [],
                [],
            ]
        }
    )
    emit:multiqc_report = MULTIQC.out.report.map { _meta, report -> [report] }.toList() // channel: /path/to/multiqc_report.html
    reads          = ch_reads                    // channel: [ meta, [ R1, R2 ] ], one per sample
    versions       = ch_versions                 // channel: [ path(versions.yml) ]
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    THE END
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
