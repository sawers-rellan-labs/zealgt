# Milestone 1: demultiplexing (both kits)

First step of `ALIGNMENT`: raw library reads to one R1/R2 FASTQ pair per sample, as the Twist guides say
(`../decisions.md`, read processing).

## Inputs
- `--input`: `meta/samples.csv` rows (a wave is a subset).
- Minimal columns: `assets/schema_input.json` declares only the columns a process reads: `sample_id`, `library`,
  `raw_location`, `raw_r1`, `raw_r2`, `barcode_r1`, `barcode_r2`, `barcode_layout`. Later milestones add theirs (read
  group columns with alignment). Everything else stays in `meta/registry.csv`, joined by `sample_id` when needed.
  To check: how nf-schema treats extra columns in the sheet.
- Three raw layouts:
  - BC1 and BC2S3 batch 2 (`symmetric`, FlexPrep): plain lane FASTQs in `raw_location`, about 3 lanes per library.
  - BC2S3 batch 1 (`r1_only`, 96-Plex): lane FASTQs inside plate tars, `raw_r1`/`raw_r2` = `<tar>:<member>;...`.

## Outputs
- Per sample: `<sample_id>_R1.fastq.gz`, `<sample_id>_R2.fastq.gz`, barcode and skipped bases removed.
- Per library and lane: fgbio's demux metrics, published under `reports/demux/`.
- During development every process publishes its outputs.

## Processes
1. `FGBIO_DEMUXFASTQS` (local; nf-core has none): one task per library x lane.
   - Read structures and mismatches in `conf/modules.config` `ext.args`, chosen by `meta.barcode_layout`:
     `symmetric` = `6B2S+T 6B2S+T --max-mismatches 1 --min-mismatch-delta 2`; `r1_only` = `8B12S+T 8S+T`.
   - Batch-1 tar members are extracted to real files in the task first (fgbio reads its inputs twice).
   - Metadata sheet per library (`Sample_Id,Sample_Barcode`): `barcode_r1` + `barcode_r2` for `symmetric`, `barcode_r1`
     for `r1_only`; written with `collectFile` in the workflow.
2. `CAT_FASTQ` (nf-core): one task per sample, joins its lane files.
- `--head N`: first N read pairs per library, split over its lanes, taken before demultiplexing.

## Choices this spec settles
- One task per lane, not one per library: lanes run in parallel and a failed lane reruns alone. Rejected: joining lanes
  first (fgbio takes one file per read, so lanes would be copied into one file before demux).
- nf-core `cat/fastq` for the lane merge. Rejected: the old local `merge_lanes`.
- No local demux report (old `DEMUX_QC`): fgbio's metrics are published as they are. Rejected: a summed per-library
  table, to be added only if MultiQC or the user needs it.
- Settings in `ext.args`, no new parameters for read structures or mismatches.

## Open, to check during the work
- Whether the nf-core fgbio 3.1.2 image has `tar` (needed for batch 1); if not, the extraction is its own process.
- Task-disk use of extracted tar members (about 2 x 20 GB per batch-1 lane).

## Tests
- Wiring (laptop, Docker, minutes): nf-test on `FGBIO_DEMUXFASTQS` and on the pipeline with `-profile test`, on
  `tests/fixtures/raw/LIBX` (symmetric, 2 plain lanes) and `LIBB1` (r1_only, tar members). Checks: every sample gets a
  pair; reads start after the barcode and skipped bases (template = `chrA` of the fixture `tiny.fa`); read counts per
  sample equal the fixtures' assignment (LIBB1 L001: 68 pairs, 30 / 20 / 10 / 0 assigned under exact matching, from the
  old demux test; recomputed for fgbio's 1 mismatch; LIBX counts derived from its reads, the old test checked names only).
- Resource profile (hazel, Apptainer, <= 30 min per process): one BC1 lane and one batch-1 lane with `--head`;
  CPU, peak memory and throughput from the trace, written as numbers in `conf/hazel.config`.

## Done when
- Wiring tests pass; `nf-core pipelines lint` has no failures.
- The DAG of the run shows `FGBIO_DEMUXFASTQS -> CAT_FASTQ` per library.
- Resource numbers are in `conf/hazel.config`, measured, one line per process.
- The report lists the choices made during the work.
