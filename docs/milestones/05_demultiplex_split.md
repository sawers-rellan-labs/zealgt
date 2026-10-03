# Milestone 5: demultiplexing as its own workflow

## Why

User, 2026-10-03: demultiplexing inside every run "ties up my hands" for choosing samples, in development and in
production batches. After the split `DEMULTIPLEX` runs once per set of libraries, and `ALIGNMENT` starts from
per-sample FASTQs. A development run is then a sheet with a few rows, and a production batch is a slice of the sheet.

## Workflows and how they are chosen

- `--step demultiplex | alignment` (the `--step` entry in `../structure.md`). `main.nf` calls one workflow.
  - No default: a run without `--step` fails at parameter validation.
  - Rejected: `-entry`. The nf-core template has a single entry workflow (with `PIPELINE_INITIALISATION`, validation
    and the `output` block), and nf-core/sarek chooses its starting step with `--step` in the same way.
- The two workflows are separate runs, linked by files, as `ALIGNMENT` -> `GENOTYPE` will be.
  - The FASTQ samplesheet is the contract between them.
  - A new demultiplexing does not start alignment on its own.

## DEMULTIPLEX: libraries to per-sample FASTQs

- Input: `--input` with the `meta/samples.csv` rows, unchanged (`assets/schema_input.json`).
- Stage: `FASTQ_DEMULTIPLEX_FQTK` as built in Milestone 1 (`EXTRACT_LANE` -> `FQTK` -> `CAT_FASTQ`), moved as is.
- `exclude` lives only here. Excluded wells are demultiplexed but not published.
  - The check that fails a sheet with every row excluded moves with the stage.
- `--head N` stays as decided on 2026-10-02: the first N pairs per library, before demultiplexing; for tests only.
- Outputs, under `--outdir`:
  - `fastq/<sample_id>/<sample_id>_R{1,2}.fastq.gz`, one pair per kept sample, with the lanes joined.
  - `fastq/samplesheet.csv`, written by the workflow-output `index`: `sample_id,fastq_1,fastq_2,library,lanes,kit`.
    - Paths are absolute, to the published files.
    - Tested on 26.04.6 (`agent/demux_split/try_index/`).
  - `reports/demux/<library>.<lane>.demux_metrics.txt` (fqtk), as now.
  - `pipeline_info/`: the params, the execution report and the software versions.
- Profiles:
  - `hpc_dev`: the outdir is on `/share`, and files are hard-linked.
  - `hpc_prod`: the outdir is a `/rsstu` folder next to the multiplexed originals, and files are copied, the global
    mode. The originals stay.
  - Production runs are out of scope here.

## ALIGNMENT: per-sample FASTQs to CRAMs

- Input: `--input` with rows of a FASTQ samplesheet, checked by a new `assets/schema_fastq.json`.
  - `PIPELINE_INITIALISATION` reads the sheet with the schema of the chosen `--step`.
  - The `input` parameter keeps its file-path checks; its fixed `schema` key goes.
- Meta: `id`, `library`, `lanes` (the read group PU), `kit` (information only: nothing after fqtk reads it) and
  `single_end: false`.
- `--head N`: the first N pairs per sample, cut by the existing `EXTRACT_LANE` (plain file, `head_pairs`), one task per
  sample, only when N > 0. No new module.
  - Rejected: no head in `ALIGNMENT`. A development run on the kept FASTQs would then need a headed `DEMULTIPLEX` of
    the whole library first, which ties sample choice to libraries again.
  - Rejected: nf-core `seqtk/sample`. It samples randomly and reads the whole file.
- Stages after this are unchanged: `FASTQ_ALIGN_MINIBWA`, `CRAM_QC_SAMTOOLS_PICARD`, `MULTIQC`.

## Deletions

- The `demux_reads` output of `ALIGNMENT` goes. `DEMULTIPLEX` publishes the FASTQs instead.
- `params.publish_intermediates` goes: `demux_reads` was its only use. Its settings in `hpc_dev`/`test` and the schema
  entry go with it.
- The `--head` 2026-10-02 decision gets one line for `ALIGNMENT`. "Development and production profiles" loses
  `publish_intermediates`.

## Not settled here

- Production `DEMULTIPLEX` on all libraries: run grouping against the 20 TB quota (work/ peak ~2 x raw) and the
  `/rsstu` folder. The user decides after point 4 of Tests.
- One samplesheet per production run, or one merged sheet: decided with the runs.

## Tests

1. Wiring (laptop, stubs, seconds). There is one pipeline stub test per step, both kits:
   - `demultiplex` on the fixture libraries. It publishes the 6 kept samples and a sheet with 6 rows.
   - `alignment` on a tracked FASTQ sheet fixture.
   - Each test writes its channel-level DAG.
2. Tool behaviour (laptop, Docker). The existing `FASTQ_DEMULTIPLEX_FQTK` and alignment tests keep passing.
   - The MultiQC test runs `alignment` on the tracked fixture FASTQs.
   - These FASTQs are the real fqtk output of the fixture libraries, made once by the `demultiplex` test.
   - Laptop tests together take <= 5 min.
3. Cluster wiring (hazel): `-stub-run` of both steps on a minimal sheet, one kept row per kit (S_1A_6, PN2_SID141).
4. Small real data (hazel, `/share`):
   - `demultiplex` BZea5 with `--head 4000000`, then `alignment` on PN5_SID464 and PN5_SID465 from its sheet.
   - Expected: the same pairs per sample and the same `samtools stats` summary as the old in-one-run job 1065735
     (`e2e_bzea5/out_2lines`).
5. fqtk vs cutadapt (priority, user 2026-10-03), not a pipeline change. The scripts go in `agent/demux_split/`.
   - Input: the same 5,000,000-pair head of one FlexPrep lane (1A) and one 96-Plex lane (BZea5 L001), with the same
     barcode sheet for both tools.
   - cutadapt uses zealgt-old's settings exactly, in a container: `-e 0 --no-indels --discard-untrimmed -Z`, anchored
     `^<barcode>N{skip}`, and `--pair-adapters` for FlexPrep.
   - fqtk runs as `DEMULTIPLEX` runs it.
   - For each sample, compared by read name: pairs both tools give the same sample, pairs only one tool assigns, and
     pairs they give different samples. Also unmatched pairs per tool, and read lengths after barcode removal.
   - Output: `docs/later/fqtk_vs_cutadapt.md`, with the setup, the table and a recommendation. The user decides.
- No resource profile: no new process. `EXTRACT_LANE` runs per sample only on headed development runs.

## Done when

- Tests 1-4 pass, and `nf-core pipelines lint` has no failures.
- The DAGs show `EXTRACT_LANE -> FQTK -> CAT_FASTQ` for `demultiplex`, and the FASTQ sheet -> `MINIBWA_MAP` ... ->
  `MULTIQC` for `alignment`.
- `decisions.md`, `structure.md`, `running.md` and `usage.md` describe the two steps.
- `docs/later/fqtk_vs_cutadapt.md` is written.
- The report lists the choices made during the work.
