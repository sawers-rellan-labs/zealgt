# Milestone 4: MultiQC

Last step of the default `ALIGNMENT` path: one MultiQC report built from the CRAM QC files of Milestone 3 and the
duplicate counts of `samtools markdup`.

## Inputs

- Per sample, the `cram_qc` files from `CRAM_QC_SAMTOOLS_PICARD` (`emit qc`): `.stats`,
  `.CollectWgsMetrics.coverage_metrics`, the mosdepth summary and distributions.
- Per sample, `<sample_id>.markdup.stats` from `SAMTOOLS_MARKDUP` (`-f`): reads examined, duplicates split into PCR
  and optical, estimated library size.
- The template's inputs already wired in `workflows/alignment.nf`: software versions, the parameter summary, the methods
  description and `assets/multiqc_config.yml`.
- Samplesheet: no new columns.

## Outputs

- `multiqc/multiqc_report.html`, `multiqc/multiqc_data/` and `multiqc/multiqc_plots/` (`export_plots: true`).
- Sections: samtools stats, samtools markdup, Picard WgsMetrics, mosdepth, one row per sample; General Statistics with
  their default columns.
- `cram/<sample_id>.markdup.stats`, next to the CRAM with the other QC files (workflow output `cram_qc`).
- Published in both profiles: `hpc_prod` publishes "only CRAMs and QC" (decision "Development and production
  profiles").

## Processes

- `MULTIQC` (nf-core, already installed, MultiQC 1.35), one task per run. No new module.
- `SAMTOOLS_MARKDUP` also writes its counts (`-f`); no new task.

## Files

- `modules/nf-core/samtools/markdup/`: patched (`nf-core modules patch`) with an optional `stats` output and its stub
  file.
- `conf/modules.config`: markdup `ext.args` gets `-f ${meta.id}.markdup.stats`.
- `subworkflows/local/fastq_align_minibwa/main.nf`: emits `markdup_stats`.
- `workflows/alignment.nf`: the markdup stats join `CRAM_QC_SAMTOOLS_PICARD.out.qc` as `cram_qc`, which goes to
  `ch_multiqc_files` (files only, `map { _meta, f -> f }`) and to the `cram_qc` emit.
- `conf/hpc_dev.config`, `conf/hpc_prod.config`: one resource line for `MULTIQC`, from the hazel run.
- `docs/structure.md`: the `inline` row splits into `MULTIQC` "built (milestone 4)" and `MARKDUP_IMPORT` "later".

## Choices this spec settles (yours to confirm)

- **Two milestones: MultiQC now, `MARKDUP_IMPORT` next** (user, 2026-10-03). Rejected: one milestone for both.
- **markdup writes its counts** (user, 2026-10-03): the only source of the optical/PCR split (`-d 2500`) and the
  estimated library size; samtools stats and Picard give only the total. Rejected: duplicates from samtools stats alone.
  Changing markdup's arguments reruns markdup and everything after it on `-resume`.
- **Only the CRAM QC and markdup files go in.** Rejected for now: the fqtk demux metrics (no MultiQC module; would need a
  custom-content entry in `assets/multiqc_config.yml`) and fgumi clip metrics (not written, no MultiQC module); both
  stay as they are (fqtk metrics in `reports/demux/`).
- **All `cram_qc` files go in, unfiltered**, including the mosdepth `.regions.bed.gz`/`.csi`: MultiQC skips what it does not
  parse and the files are staged as links. Rejected: a `filter` on file names, one more operator for no output change.
- **The template's MultiQC publishing stays** (`publishDir` in `conf/modules.config`, `multiqc/`). Rejected: moving it to a
  workflow output or to `reports/multiqc/`, a change no output needs.
- **MultiQC defaults and the template config**: sample names from file names (`<sample_id>`), no custom General
  Statistics columns. Rejected: tuning columns before seeing the report on real data.

## Not in this milestone

- `MARKDUP_IMPORT` (`--step markduplicates` for imported zealbc1/nilhmm CRAMs): Milestone 5.
- fqtk demux metrics and other QC in MultiQC.

## Tests

1. **Wiring** (laptop, stubs, seconds). The pipeline stub test on the fixture libraries checks:
   - one `MULTIQC` task, after every QC task of every kept sample;
   - `multiqc/multiqc_report.html` published;
   - `cram/<sample_id>.markdup.stats` published per kept sample.

   The same run writes the channel-level DAG.

2. **Tool behaviour** (laptop, Docker). The pipeline test on the `tiny.fa` fixtures (not stub) checks that
   `multiqc_data/multiqc_sources.txt` lists samtools stats, samtools markdup, Picard WgsMetrics and mosdepth, each
   with every kept sample, named by `sample_id`. If it does not fit the 5 min laptop budget, it runs on the Milestone 3
   subworkflow outputs instead.
3. **Cluster wiring** (hazel, Apptainer): `-profile hpc_dev -stub-run` on the Milestone 1 minimal sheet.
4. **Resource profile** (hazel): the Milestone 3 run (4 samples, `--head 4000000`) resumed from its cache in
   `zealgt_dev`; markdup and everything after it rerun. `MULTIQC`'s CPU, peak memory and run time go into config;
   markdup's are checked against its config line.

- Budget: all laptop tests together <= 5 min.

## Done when

- Stub and tool tests pass; `nf-core pipelines lint` has no failures.
- The DAG shows `{ SAMTOOLS_MARKDUP, SAMTOOLS_STATS, PICARD_COLLECTWGSMETRICS, MOSDEPTH } -> MULTIQC`.
- The hazel report has the four sections with the 4 samples.
- Resource numbers are in config, measured, one line.
- `docs/structure.md` marks `MULTIQC` "built (milestone 4)"; `decisions.md` holds only the choices you confirm.
- The report lists the choices made during the work.
