# Milestone 3: CRAM QC

Third step of `ALIGNMENT`: per-sample QC of each CRAM from `FASTQ_ALIGN_MINIBWA`.

## Inputs

- Per sample `[ meta, cram, crai ]` from `FASTQ_ALIGN_MINIBWA` (`emit cram`).
- `--fasta` with its `.fai`, the channel the alignment stage already reads.
- Tests use the `tiny.fa` CRAMs that the Milestone 2 fixtures produce.
- Samplesheet: no new columns.

## Outputs

- Per sample:
  - `<sample_id>.stats` (samtools stats);
  - `<sample_id>.CollectWgsMetrics.coverage_metrics` (Picard);
  - `<sample_id>.CollectMultipleMetrics.alignment_summary_metrics` and `.quality_distribution_metrics` with its PDF
    (Picard);
  - `<sample_id>.mosdepth.summary.txt`, `.mosdepth.global.dist.txt`, `.mosdepth.region.dist.txt` and
    `.regions.bed.gz` with its `.csi` (mosdepth, 500 bp windows).
- All go to `cram/` next to the CRAM, as the workflow output `cram_qc` with `mode 'copy'`, like `cram`.
- The QC files are published in both profiles: `hpc_prod` publishes "only CRAMs and QC" (decision "Development and
  production profiles").

## Processes

Stage `CRAM_QC_SAMTOOLS_PICARD`, four modules from nf-core (`nf-core modules install`), one task per sample each. All
four read the same CRAM in parallel:

1. `SAMTOOLS_STATS`: default options, with the reference so the CRAM decodes.
2. `PICARD_COLLECTWGSMETRICS`: Picard defaults (MAPQ >= 20, base quality >= 20, coverage cap 250, duplicates
   excluded), the whole genome, no interval list. `PCT_EXC_TOTAL` is the floor π of the missing-data model
   (https://sawers-rellan-labs.github.io/zealhmm/analysis/missing-data-floor-model.html).
3. `PICARD_COLLECTMULTIPLEMETRICS`: `--PROGRAM CollectAlignmentSummaryMetrics --PROGRAM QualityScoreDistribution`, one
   pass over the reads, no genome walk. How a `--PROGRAM` list replaces Picard's default list is checked on the
   installed version first.
4. `MOSDEPTH`: `-n --fast-mode --by 500`, as nf-core/sarek for WGS (`conf/modules/modules.config`): no per-base output,
   mean depth per 500 bp window, the depth distribution and per-chromosome summary. Raw aligned depth, between the read
   count and CollectWgsMetrics' usable depth.

## Files

- `subworkflows/local/cram_qc_samtools_picard/main.nf` (new): the four calls on `[ meta, cram, crai ]` and the
  reference.
- `modules/nf-core/{samtools/stats,picard/collectwgsmetrics,picard/collectmultiplemetrics,mosdepth}/`: installed.
- `workflows/alignment.nf`: one call `CRAM_QC_SAMTOOLS_PICARD(FASTQ_ALIGN_MINIBWA.out.cram, ch_fasta)` and a `cram_qc`
  emit.
- `main.nf`: the `cram_qc` workflow output to `cram/`, `mode 'copy'`.
- `conf/modules.config`: `ext.args` of CollectMultipleMetrics and mosdepth.
- `conf/hpc_dev.config`, `conf/hpc_prod.config`: one resource line per process.

## Choices this spec settles (yours to confirm)

- **QC next to the CRAM in `cram/`**, as in the old repo. Rejected: `reports/cram_qc/`, which splits a sample's files
  between two folders.
- **No `--VALIDATION_STRINGENCY SILENT`**. The old repo needed it for imported zealbc1 CRAMs, whose MAPQ 20 / `-F 0x904`
  filter left mates missing. Our CRAMs keep every record, so the default STRICT should pass, and the tool test and hazel
  run check that. Rejected: keeping SILENT, which would hide real errors. `MARKDUP_IMPORT` (next row) decides it again
  for imported CRAMs.
- **CollectWgsMetrics on the whole genome, also in tests.** `tiny.fa` is small, and on hazel the ~10 min genome walk per
  task still fits the 15 min run. Rejected: `--INTERVALS` per chromosome for tests, which would take the denominator of
  `PCT_EXC_TOTAL` from a different region than production.
- **CollectMultipleMetrics for the alignment summary and quality distribution** (user, 2026-10-03): one task and one
  read pass for both. Rejected: separate CollectAlignmentSummaryMetrics and QualityScoreDistribution modules (two
  tasks, two passes); Picard's default program list (adds insert size, quality by cycle, base distribution: not asked).
  The `docs/structure.md` row gets `PICARD_COLLECTMULTIPLEMETRICS`.
- **Mosdepth with sarek's WGS settings** (user, 2026-10-03). Rejected: variantcatalogue's defaults, which write and
  publish per-base depth (GBs per sample); dropping `--fast-mode`, which counts the mates' overlap once, as
  CollectWgsMetrics does, at more run time. CollectWgsMetrics stays: mosdepth has no `PCT_EXC_*`.
- **The stage keeps the name `CRAM_QC_SAMTOOLS_PICARD`.** Rejected: renaming it for mosdepth (e.g. sarek's
  `CRAM_QC_MOSDEPTH_SAMTOOLS`), which drops Picard from the name. The `docs/structure.md` row gets `MOSDEPTH`.
- **A stage subworkflow**, as `docs/structure.md` asks for two or more modules. Rejected: inline calls in `workflows/alignment.nf`.
- **Fixed resources per profile**, from the old measurements, then retuned from this milestone's hazel run. Rejected:
  the old size-scaled `time` closures.
- **Picard in production may outlive the short QOS** (2 h cap): 310 M pairs took 2 h 18 min before. If so, it gets
  `compute`/`normal` QOS, as `MINIBWA_MAP` did.

## Not in this milestone

- MultiQC on these files, and `MARKDUP_IMPORT`: the next row of `docs/structure.md`.
- Other QC tools (FastQC, insert size, GC bias).

## Tests

1. **Wiring** (laptop, stubs, seconds). The pipeline stub test on the fixture libraries checks:
   - one `.stats`, one WGS metrics file and one alignment summary + quality distribution pair per kept sample, next
     to its CRAM, and the mosdepth files without a per-base file;
   - one task per sample for each process.

   The same run writes the channel-level DAG.

2. **Tool behaviour** (laptop, Docker). nf-test of `CRAM_QC_SAMTOOLS_PICARD` on the `tiny.fa` CRAMs checks:
   - `.stats` has `SN` lines and its read count equals the CRAM's;
   - the WGS metrics file has `PCT_EXC_TOTAL` between 0 and 1;
   - CollectMultipleMetrics wrote only the two asked programs' files, `TOTAL_READS` equal to the CRAM's primary reads;
   - both Picard tasks ran under STRICT validation;
   - mosdepth's summary has a `total` mean depth >= CollectWgsMetrics' `MEAN_COVERAGE`, and no per-base file.
3. **Cluster wiring** (hazel, Apptainer): `-profile hpc_dev -stub-run` on the Milestone 1 minimal sheet.
4. **Resource profile** (hazel, under 15 min per process).
   - Samples: S_1A_6, S_1A_12 (96-Plex), PN2_SID151, PN2_SID141 (FlexPrep), other wells `exclude = TRUE`,
     `--head 4000000`.
   - Alignment is resumed from Milestone 2's cache where it still exists.
   - CPU, peak memory and run time go into `conf/hpc_dev.config` / `conf/hpc_prod.config`.

- Budget: all laptop tests together <= 5 min.

## Done when

- Stub and tool tests pass; `nf-core pipelines lint` has no failures.
- The DAG shows `SAMTOOLS_MARKDUP -> SAMTOOLS_INDEX -> { SAMTOOLS_STATS, PICARD_COLLECTWGSMETRICS,
PICARD_COLLECTMULTIPLEMETRICS, MOSDEPTH }` per sample.
- The hazel run published all QC files next to each CRAM, Picard under STRICT validation.
- Resource numbers are in config, measured, one line per process.
- `docs/structure.md` marks the row "built (milestone 3)"; `decisions.md` holds only the choices you confirm.
- The report lists the choices made during the work.
