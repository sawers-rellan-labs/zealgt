# Structure (proposal)

A guide, not a contract: stages are split, merged or renamed when building and debugging show a better cut. Changes
are recorded here. Terms as in `TERMINOLOGY.md`, decisions in `decisions.md`.

![zealgt full metro map](images/zealgt_metro_full.svg)

Production steps of the built workflows (source `images/zealgt_metro_full.mmd`, drawn with nf-metro 2.1.0); the README
shows the same map without CRAM QC (`images/zealgt_metro.mmd`).

## Levels

Read top down; each level only names the one below it.

| level    | file                                                  | holds                                         | limit         |
| -------- | ----------------------------------------------------- | --------------------------------------------- | ------------- |
| pipeline | `main.nf`                                             | the `--step` choice and the software versions | template size |
| workflow | `workflows/<name>.nf`                                 | the list of stage calls, MultiQC at the end   | 100 lines     |
| stage    | `subworkflows/local/<stage>/main.nf`                  | one stage's channel wiring                    | 100 lines     |
| tool     | `modules/local/<tool>/main.nf`, `modules/nf-core/...` | one tool call                                 | 100 lines     |
| settings | `conf/*.config`                                       | resources, `ext.args`, publishing; no logic   |               |

- A stage becomes a subworkflow when it chains two or more modules; a single module is called inline.
- Stage names follow nf-core: `<input>_<operation>_<tool>`.
- `subworkflows/local/utils_nfcore_zealgt_pipeline/` keeps the template's code plus the samplesheet-to-channel step,
  nothing else. No Groovy function files.

## DEMULTIPLEX (`--step demultiplex`): library reads to one FASTQ pair per sample

| stage                    | modules                                                                     | status                  |
| ------------------------ | --------------------------------------------------------------------------- | ----------------------- |
| `FASTQ_DEMULTIPLEX_FQTK` | `EXTRACT_LANE` -> `FQTK` -> `CAT_FASTQ`; FASTQs and `fastq/samplesheet.csv` | built (milestones 1, 5) |

## ALIGNMENT (`--step alignment`): per-sample FASTQs to one CRAM per sample

| stage                     | modules                                                                                                          | status              |
| ------------------------- | ---------------------------------------------------------------------------------------------------------------- | ------------------- |
| inline                    | `SEQKIT_HEAD` with `--head N` only (test runs): the first N pairs per sample                                     | built               |
| `FASTQ_ALIGN_MINIBWA`     | `MINIBWA_MAP` -> `FGUMI_CLIP` -> `SAMTOOLS_FIXMATE` -> `SAMTOOLS_SORT` -> `SAMTOOLS_MARKDUP` -> `SAMTOOLS_INDEX` | built (milestone 2) |
| `CRAM_QC_SAMTOOLS_PICARD` | `SAMTOOLS_STATS`, `PICARD_COLLECTWGSMETRICS`, `MOSDEPTH`                                                         | built (milestone 3) |
| inline                    | `MULTIQC` on the CRAM QC files                                                                                   | built (milestone 4) |

## GENOTYPE: CRAMs to genotypes (development scope: one chromosome end to end)

Provisional, from the old repository's stages; which of them are kept is decided per milestone.

| stage                          | modules (old names)                                                                                     |
| ------------------------------ | ------------------------------------------------------------------------------------------------------- |
| `PREPARE_REGIONS`              | `REGION_BED`, `MASK_READ_STARTS`; once, passed to every stage below                                     |
| `CRAM_SAMPLEQC`                | `MIN_COVERAGE`, `COVERAGE_QC`, `RELATEDNESS_QC`, `DONOR_CONTENT_QC`, `SAMPLE_QC_TABLE`                  |
| `CRAM_VARIANT_DISCOVERY_CRISP` | `WITNESS_POOL` -> `CRISP` -> `BED_CLIP` -> `WITNESS_VETO`, site counts -> `POOLED_LIKELIHOOD_TIERS`     |
| `CRAM_ANCESTRY_RTIGER`         | `RTIGER_MARKERS` -> `LINE_ALLELE_COUNTS` -> `LINE_MARKER_QC` -> `RTIGER`                                |
| `CRAM_ALLELE_CALLING_POOLED`   | union counts -> `JOINT_POOLED_LIKELIHOOD` -> `GAP_FILLING_BC1` / `GAP_FILLING_LINES` -> `DONOR_FOUNDER` |
| `GENOTYPE_REPORTING`           | `SAMPLE_LABELS`, `GENOTYPE_SUMMARY`, `CHROMOSOME_PAINTING`, `READ_POSITION_QC`                          |
| inline                         | `MARKER_UNION`, `RASTERIZE`                                                                             |

## Not built

Store, checkpoints, run guards, registry snapshots, provenance files, cleanup scripts: Nextflow's `-resume`, `work/`,
`publishDir` and `pipeline_info/` do these.
