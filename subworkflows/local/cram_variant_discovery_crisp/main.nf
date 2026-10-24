include { SAMTOOLS_MERGE                     } from '../../../modules/nf-core/samtools/merge/main'
include { SAMTOOLS_ADDREPLACERG              } from '../../../modules/nf-core/samtools/addreplacerg/main'
include { SAMTOOLS_INDEX                     } from '../../../modules/nf-core/samtools/index/main'
include { SAMTOOLS_VIEW as FILTER_BC1        } from '../../../modules/nf-core/samtools/view/main'
include { SAMTOOLS_VIEW as FILTER_WITNESS    } from '../../../modules/nf-core/samtools/view/main'
include { SAMTOOLS_VIEW as FILTER_CHECKS     } from '../../../modules/nf-core/samtools/view/main'
include { CRISP                              } from '../../../modules/local/crisp/main'
include { BCFTOOLS_REHEADER as CRISP_CONTIGS } from '../../../modules/nf-core/bcftools/reheader/main'
include { BCFTOOLS_VIEW as BED_CLIP          } from '../../../modules/nf-core/bcftools/view/main'
include { BCFTOOLS_VIEW as WITNESS_VETO      } from '../../../modules/nf-core/bcftools/view/main'
include { BCFTOOLS_MPILEUP                   } from '../../../modules/nf-core/bcftools/mpileup/main'
include { POOLED_LIKELIHOOD_TIERS            } from '../../../modules/local/pooled_likelihood_tiers/main'

workflow CRAM_VARIANT_DISCOVERY_CRISP {
    take:
    ch_cram         // channel: [ meta, cram, crai ], meta.role, meta.donor
    ch_regions      // channel: region, one per region
    ch_b73_controls // channel: [ meta, cram, crai ], the B73 reference controls
    ch_b73_checks   // channel: sample_id, one per QC-PASS B73 check
    ch_fasta        // channel: [ meta, fasta, fai ]
    lowcopy_bed     // file: low-copy BED
    score_tool      // file: bin/score_pooled_likelihood.py

    main:
    // BC1 pools and lines by donor, the QC-PASS B73 checks (the check samples listed); other roles take no part
    def ch_role = ch_cram.branch { meta, _cram, _crai ->
        bc1: meta.role == 'bc1_sample'
        nil: meta.role == 'nil'
        check: meta.role == 'check'
    }
    // no QC-PASS check among the samples stops the run, since without the check pool CRISP never runs
    def ch_check = ch_role.check.map { meta, cram, crai -> [meta.id, cram, crai] }.combine(ch_b73_checks.map { id -> [id] }, by: 0)
        .ifEmpty { error("None of the --b73_checks samples is a check sample in the CRAM samplesheet above the coverage floor") }

    // one pool per donor's lines (the NIL pool, called witness in the code), one of the QC-PASS checks, one per B73 control; each per region
    def ch_pool = ch_role.nil.map { meta, cram, crai -> [meta.donor, cram, crai] }.groupTuple()
        .map { donor, crams, crais -> [[id: "${donor.replace('.', '')}_witness", donor: donor], crams, crais] }
        .mix(
            ch_check.map { _id, cram, crai -> ['B73_checks', cram, crai] }.groupTuple()
                .map { id, crams, crais -> [[id: id], crams, crais] },
            ch_b73_controls.map { meta, cram, crai -> [[id: meta.id], [cram], [crai]] }
        )
        .combine(ch_regions)
        .map { meta, crams, crais, region -> [meta + [region: region], crams, crais] }
    def ch_fasta_gzi = ch_fasta.map { meta, fasta, fai -> [meta, fasta, fai, []] }
    SAMTOOLS_MERGE(ch_pool, ch_fasta_gzi, '')
    // one read group per pool: CRISP and mpileup see one sample
    SAMTOOLS_ADDREPLACERG(SAMTOOLS_MERGE.out.cram.map { meta, cram -> [meta, cram, [], "'@RG\\tID:${meta.id}\\tSM:${meta.id}\\tPL:ILLUMINA'"] }, ch_fasta_gzi)
    def ch_pool_rg = SAMTOOLS_ADDREPLACERG.out.cram.branch { meta, _cram -> witness: meta.donor != null; control: true }
    SAMTOOLS_INDEX(ch_pool_rg.control)
    def ch_controls = ch_pool_rg.control.join(SAMTOOLS_INDEX.out.index, failOnMismatch: true)
    // CRISP reads copies without supplementary records (vibansal/crisp#35), cut to the low-copy ranges: the BC1 CRAMs
    // whole, the NIL pool and the check pool per region
    def ch_bed = [[id: 'lowcopy'], lowcopy_bed]
    FILTER_BC1(ch_role.bc1.map { meta, cram, _crai -> [meta, cram, []] }, ch_fasta, [[], []], ch_bed, 'crai')
    FILTER_WITNESS(ch_pool_rg.witness.map { meta, cram -> [meta, cram, []] }, ch_fasta, [[], []], ch_bed, 'crai')
    FILTER_CHECKS(ch_pool_rg.control.filter { meta, _cram -> meta.id == 'B73_checks' }.map { meta, cram -> [meta, cram, []] }, ch_fasta, [[], []], ch_bed, 'crai')
    // CRISP per donor x region: its NIL pool, the check pool over the region and its BC1 pools (by name, once all are in: groupKey)
    def ch_n_bc1 = ch_role.bc1.map { meta, _cram, _crai -> [meta.donor, 1] }.groupTuple().map { donor, ones -> [donor, ones.size()] }
    def ch_crisp = FILTER_BC1.out.cram.join(FILTER_BC1.out.crai, failOnMismatch: true).map { meta, cram, crai -> [meta.donor, cram, crai] }
        .combine(ch_n_bc1, by: 0).map { donor, cram, crai, n -> [groupKey(donor, n), cram, crai] }.groupTuple(sort: { a, b -> a.name <=> b.name })
        .combine(ch_regions).map { key, crams, crais, region -> [key.getGroupTarget(), region, crams, crais] }
        .join(FILTER_WITNESS.out.cram.join(FILTER_WITNESS.out.crai, failOnMismatch: true)
            .map { meta, cram, crai -> [meta.donor, meta.region, meta.id, cram, crai] }, by: [0, 1])
        .map { donor, region, crams, crais, witness, wcram, wcrai -> [region, [id: donor, witness: witness, region: region], crams, crais, wcram, wcrai] }
        .combine(FILTER_CHECKS.out.cram.join(FILTER_CHECKS.out.crai, failOnMismatch: true).map { meta, cram, crai -> [meta.region, cram, crai] }, by: 0)
        .map { _region, meta, crams, crais, wcram, wcrai, ccram, ccrai -> [meta, crams, crais, wcram, wcrai, ccram, ccrai] }
    CRISP(ch_crisp, ch_fasta, lowcopy_bed)
    // contig lines from the .fai, which CRISP does not write and bcftools needs to drop a sample
    CRISP_CONTIGS(CRISP.out.vcf.map { meta, vcf -> [meta, vcf, [], []] }, ch_fasta.map { meta, _fasta, fai -> [meta, fai] })
    // records inside the low-copy ranges (CRISP also calls the base past each range end) and not called in the check pool,
    // without the check pool's column; then the NIL rule (the witness veto)
    BED_CLIP(CRISP_CONTIGS.out.vcf.map { meta, vcf -> [meta, vcf, []] }, [], lowcopy_bed, [])
    WITNESS_VETO(BED_CLIP.out.vcf.map { meta, vcf -> [meta, vcf, []] }, [], [], [])

    // the B73 controls counted at each donor's kept sites in the same region
    BCFTOOLS_MPILEUP(
        ch_controls.map { meta, cram, crai -> [meta.region, meta, cram, crai] }
            .combine(WITNESS_VETO.out.vcf.map { meta, vcf -> [meta.region, meta, vcf] }, by: 0)
            .map { _region, meta, cram, crai, donor_meta, vcf -> [meta + [donor: donor_meta.id], cram, crai, vcf, []] },
        ch_fasta, false
    )
    // control pools per region (the B73 controls and the check pool): each donor x region goes on once its counts are in
    def ch_n_controls = ch_b73_controls.count().map { n -> n + 1 }
    def ch_score = WITNESS_VETO.out.vcf.map { meta, vcf -> [meta.id, meta.region, meta, vcf] }
        .join(BCFTOOLS_MPILEUP.out.vcf.combine(ch_n_controls).map { meta, vcf, n -> [groupKey([meta.donor, meta.region], n), vcf] }
            .groupTuple().map { key, vcfs -> key.getGroupTarget() + [vcfs] }, by: [0, 1])
        .map { _donor, _region, meta, vcf, controls -> [meta, vcf, controls, []] }
    POOLED_LIKELIHOOD_TIERS(ch_score, score_tool)

    emit:
    vcf                = WITNESS_VETO.out.vcf.join(WITNESS_VETO.out.index) // channel: [ meta, vcf.gz, tbi ], one per donor x region
    sites              = POOLED_LIKELIHOOD_TIERS.out.sites                 // channel: [ meta, sites.tsv.gz ], one per donor x region
    tier_a             = POOLED_LIKELIHOOD_TIERS.out.tier_a                // channel: [ meta, tier_a.vcf ], one per donor x region
    controls           = ch_controls                                       // channel: [ meta, cram, crai ], the B73 controls and the check pool, per region
    n_controls         = ch_n_controls                                     // channel: value, the control pools per region
}
