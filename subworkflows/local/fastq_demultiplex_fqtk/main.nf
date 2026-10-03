include { EXTRACT_LANE } from '../../../modules/local/extract_lane/main'
include { FQTK         } from '../../../modules/nf-core/fqtk/main'

workflow FASTQ_DEMULTIPLEX_FQTK {

    take:
    ch_samplesheet // channel: [ meta, raw_location, raw_r1, raw_r2 ], one per sample
    head_pairs     // integer: first N read pairs per library, 0 = all

    main:
    // one fqtk sample sheet per library, excluded wells included; FlexPrep barcodes are the R1 and R2 barcodes joined
    def ch_sheets = ch_samplesheet
        .map { meta, _loc, _r1, _r2 -> ["${meta.library}.tsv", "${meta.id}\t${meta.barcode_r1}${meta.barcode_r2 ?: ''}\n"] }
        .collectFile(seed: "sample_id\tbarcode\n", sort: true)
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
                : files("${loc}/*_{1,2}.fq.gz").groupBy { f -> f.name - ~/_[12]\.fq\.gz$/ }.collect { lane, pair ->
                    def (f1, f2) = pair.sort { f -> f.name }
                    [lane, f1, f2, '', '']
                }
            lanes.collect { lane, s1, s2, m1, m2 -> [lib + [id: "${lib.id}.${lane}", lane: lane, n_lanes: lanes.size()], s1, s2, m1, m2] }
        }
        .branch { _meta, _s1, _s2, m1, _m2 ->
            extract: m1 || head_pairs
            direct: true
        }

    // tar members and --head lanes become real files first
    EXTRACT_LANE(
        ch_lanes.extract.map { meta, s1, s2, m1, m2 -> [meta, s1, s2, m1, m2, head_pairs ? Math.ceil(head_pairs / meta.n_lanes) as long : 0] }
    )
    def ch_lane_reads = ch_lanes.direct
        .map { meta, s1, s2, _m1, _m2 -> [meta, s1, s2] }
        .mix(EXTRACT_LANE.out.reads)

    // fqtk reads both lane files from their directory, with the read structures of the kit's Twist guide
    FQTK(
        ch_lane_reads
            .map { meta, r1, r2 -> [meta.library, meta, r1, r2] }
            .combine(ch_sheets, by: 0)
            .map { _library, meta, r1, r2, sheet ->
                def (rs1, rs2) = meta.kit == 'twist_96plex' ? ['8B12S+T', '8S+T'] : ['6B2S+T', '6B2S+T']
                [meta, sheet, r1.parent, [[r1.name, rs1], [r2.name, rs2]]]
            }
    )

    // kept samples by id; excluded ones are demultiplexed only so their reads leave ours
    def ch_kept = ch_samplesheet.filter { meta, _loc, _r1, _r2 -> !meta.exclude }.map { meta, _loc, _r1, _r2 -> [meta.id, meta] }

    // per sample x lane: its read pair, lane stem and the library's lane count in meta
    def ch_sample_lanes = FQTK.out.sample_fastq
        .flatMap { meta, files ->
            files.findAll { f -> !f.name.startsWith('unmatched') }
                .groupBy { f -> f.name - ~/\.R[12]\.fq\.gz$/ }
                .collect { sample, pair -> [sample, meta.lane, meta.n_lanes, pair.sort { f -> f.name }] }
        }
        // drops the lanes of excluded samples: only ids of kept rows match
        .combine(ch_kept, by: 0)
        .map { _sample, lane, n_lanes, pair, meta -> [meta + [lane: lane, n_lanes: n_lanes, single_end: false], pair] }

    emit:
    reads   = ch_sample_lanes // channel: [ meta + lane + n_lanes, [ R1, R2 ] ], one per sample x lane
    metrics = FQTK.out.metrics // channel: [ meta, demux-metrics.txt ], one per lane
}
