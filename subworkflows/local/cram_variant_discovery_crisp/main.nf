include { BCFTOOLS_MPILEUP as CHECK_COUNTS } from '../../../modules/nf-core/bcftools/mpileup/main'
include { CHECK_ALT_RATE                   } from '../../../modules/local/check_alt_rate/main'
include { SAMTOOLS_MERGE                   } from '../../../modules/nf-core/samtools/merge/main'
include { SAMTOOLS_ADDREPLACERG            } from '../../../modules/nf-core/samtools/addreplacerg/main'
include { SAMTOOLS_INDEX                   } from '../../../modules/nf-core/samtools/index/main'
include { CRISP                            } from '../../../modules/local/crisp/main'
include { BCFTOOLS_VIEW as BED_CLIP        } from '../../../modules/nf-core/bcftools/view/main'
include { BCFTOOLS_VIEW as WITNESS_VETO    } from '../../../modules/nf-core/bcftools/view/main'
include { BCFTOOLS_MPILEUP                 } from '../../../modules/nf-core/bcftools/mpileup/main'
include { POOLED_LIKELIHOOD_TIERS          } from '../../../modules/local/pooled_likelihood_tiers/main'

workflow CRAM_VARIANT_DISCOVERY_CRISP {
    take:
    ch_cram            // channel: [ meta, cram, crai ], meta.role, meta.donor, meta.pedigree
    ch_b73_controls    // channel: [ meta, cram, crai ], the B73 reference controls
    ch_fasta           // channel: [ meta, fasta, fai ]
    lowcopy_bed        // file: low-copy BED
    check_sites        // file: VCF of the sites the B73 check filter counts
    max_check_alt_rate // number: B73 checks with a larger share of ALT reads are dropped
    score_tool         // file: bin/score_pooled_likelihood.py

    main:
    // BC1 pools and lines by donor, batch-1 B73 checks; other roles take no part
    def ch_role = ch_cram.branch { meta, _cram, _crai ->
        bc1: meta.role == 'bc1_sample'
        line: meta.role == 'line'
        check: meta.role == 'check' && meta.pedigree == 'B73-bulk'
    }

    // B73 check filter: each check's share of ALT reads at the check sites
    CHECK_COUNTS(ch_role.check.map { meta, cram, _crai -> [meta, cram, check_sites, []] }, ch_fasta, false)
    CHECK_ALT_RATE(CHECK_COUNTS.out.vcf)
    def ch_check = ch_role.check.join(CHECK_ALT_RATE.out.rate).branch { _meta, _cram, _crai, rate ->
        kept: (rate as double) <= max_check_alt_rate
        dropped: true
    }
    // the dropped checks with their counts
    def ch_b73_checks = CHECK_ALT_RATE.out.tsv.join(ch_check.dropped)
        .map { _meta, tsv, _cram, _crai, _rate -> tsv }
        .collectFile(name: 'b73_checks.tsv', seed: "sample_id\treads\talt_reads\talt_rate\n", sort: true)

    // one pool per donor's lines (the witness), one of the kept B73 checks, one per B73 control
    def ch_pool = ch_role.line
        .map { meta, cram, crai -> [meta.donor, cram, crai] }
        .groupTuple()
        .map { donor, crams, crais -> [[id: "${donor.replace('.', '')}_witness", donor: donor], crams, crais] }
        .mix(
            ch_check.kept.map { _meta, cram, crai, _rate -> ['B73_checks', cram, crai] }.groupTuple()
                .map { id, crams, crais -> [[id: id], crams, crais] },
            ch_b73_controls.map { meta, cram, crai -> [[id: meta.id], [cram], [crai]] }
        )
    def ch_fasta_gzi = ch_fasta.map { meta, fasta, fai -> [meta, fasta, fai, []] }
    SAMTOOLS_MERGE(ch_pool, ch_fasta_gzi, '')
    // one read group per pool: CRISP and mpileup see one sample
    SAMTOOLS_ADDREPLACERG(
        SAMTOOLS_MERGE.out.cram.map { meta, cram -> [meta, cram, [], "'@RG\\tID:${meta.id}\\tSM:${meta.id}\\tPL:ILLUMINA'"] },
        ch_fasta_gzi
    )
    SAMTOOLS_INDEX(SAMTOOLS_ADDREPLACERG.out.cram)
    def ch_pool_rg = SAMTOOLS_ADDREPLACERG.out.cram.join(SAMTOOLS_INDEX.out.index, failOnMismatch: true).branch { meta, _cram, _crai ->
        witness: meta.donor != null
        control: true
    }

    // CRISP per donor: its BC1 pools and its witness
    def ch_crisp = ch_role.bc1
        .map { meta, cram, crai -> [meta.donor, cram, crai] }
        .groupTuple()
        .join(ch_pool_rg.witness.map { meta, cram, crai -> [meta.donor, meta.id, cram, crai] })
        .map { donor, crams, crais, witness, wcram, wcrai -> [[id: donor, witness: witness], crams, crais, wcram, wcrai] }
    CRISP(ch_crisp, ch_fasta, lowcopy_bed)
    // records inside the low-copy ranges (CRISP also calls the base past each range end), then the witness veto
    BED_CLIP(CRISP.out.vcf.map { meta, vcf -> [meta, vcf, []] }, [], lowcopy_bed, [])
    WITNESS_VETO(BED_CLIP.out.vcf.map { meta, vcf -> [meta, vcf, []] }, [], [], [])

    // the B73 controls counted at each donor's kept sites
    BCFTOOLS_MPILEUP(
        ch_pool_rg.control.combine(WITNESS_VETO.out.vcf)
            .map { meta, cram, _crai, donor_meta, vcf -> [meta + [donor: donor_meta.id], cram, vcf, []] },
        ch_fasta,
        false
    )
    def ch_score = WITNESS_VETO.out.vcf.map { meta, vcf -> [meta.id, meta, vcf] }
        .join(BCFTOOLS_MPILEUP.out.vcf.map { meta, vcf -> [meta.donor, vcf] }.groupTuple())
        .map { _donor, meta, vcf, controls -> [meta, vcf, controls] }
    POOLED_LIKELIHOOD_TIERS(ch_score, score_tool)

    emit:
    vcf        = WITNESS_VETO.out.vcf.join(WITNESS_VETO.out.index) // channel: [ meta, vcf.gz, tbi ], one per donor
    sites      = POOLED_LIKELIHOOD_TIERS.out.sites                 // channel: [ meta, sites.tsv.gz ], one per donor
    b73_checks = ch_b73_checks                                     // channel: b73_checks.tsv, the dropped B73 checks
}
