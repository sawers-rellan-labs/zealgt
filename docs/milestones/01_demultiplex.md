# Milestone 1: demultiplexing (both kits)

First step of `ALIGNMENT`: raw library reads to one R1/R2 FASTQ pair per sample, as the Twist guides say
(`../decisions.md`, read processing).

## Inputs

- `--input`: `meta/samples.csv` rows (a wave is a subset).
- Minimal columns: `assets/schema_input.json` declares only the columns a process reads: `sample_id`, `library`,
  `raw_location`, `raw_r1`, `raw_r2`, `barcode_r1`, `barcode_r2`, `kit`. Later milestones add theirs (read
  group columns with alignment). Everything else stays in `meta/registry.csv`, joined by `sample_id` when needed.
  To check: how nf-schema treats extra columns in the sheet.
- Three raw layouts:
  - BC1 and BC2S3 batch 2 (`twist_flexprep`): plain lane FASTQs in `raw_location`, about 3 lanes per library.
  - BC2S3 batch 1 (`twist_96plex`): lane FASTQs inside plate tars, `raw_r1`/`raw_r2` = `<tar>:<member>;...`.

## Outputs

- Per sample: `<sample_id>_R1.fastq.gz`, `<sample_id>_R2.fastq.gz`, barcode and skipped bases removed.
- Per library and lane: fqtk's demux metrics, published under `reports/demux/`.
- During development every process publishes its outputs.

## Processes

Stage `FASTQ_DEMULTIPLEX_FQTK`:

1. `EXTRACT_LANE` (local): batch-1 tar members and `--head` lanes become real files.
2. `FQTK` (nf-core `fqtk`, decision "Demultiplexing with fqtk"): one task per library x lane.
   - Read structures by `meta.kit` as module inputs: `twist_flexprep` = `6B2S+T 6B2S+T`, `twist_96plex` = `8B12S+T 8S+T`;
     `--threads` and FlexPrep's `--max-mismatches 1 --min-mismatch-delta 2` in `conf/modules.config` `ext.args`.
   - Sample sheet per library (`sample_id<TAB>barcode`): `barcode_r1` + `barcode_r2` for `twist_flexprep`, `barcode_r1`
     for `twist_96plex`; written with `collectFile` in the stage.
3. `CAT_FASTQ` (nf-core): one task per sample, joins its lane files; single-lane samples skip it.

- `--head N`: first N read pairs per library, split over its lanes, taken before demultiplexing.

## Choices this spec settles

- One task per lane, not one per library: lanes run in parallel and a failed lane reruns alone. Rejected: joining lanes
  first (the demultiplexer takes one file per read, so lanes would be copied into one file before demux).
- nf-core `cat/fastq` for the lane merge. Rejected: the old local `merge_lanes`.
- No local demux report (old `DEMUX_QC`): fqtk's metrics are published as they are. Rejected: a summed per-library
  table, to be added only if MultiQC or the user needs it.
- Mismatches in `ext.args`, read structures by kit in the stage (the module takes them as inputs); no new parameters.

## Open, to check during the work

- Task-disk use of extracted tar members (about 2 x 20 GB per batch-1 lane).

## Tests

1. Wiring (laptop, stubs, seconds): every local module has a `stub:` block and an nf-test `- stub` case; the pipeline
   test runs with `options "-stub"` on both fixture libraries, `tests/fixtures/raw/LIBX` (`twist_flexprep`, 2 plain
   lanes) and `LIBB1` (`twist_96plex`, tar members). Checks: the channels connect and every expected output file
   appears, per sample and per lane. The same stub run writes the channel-level DAG (`-with-dag`: processes, operators
   and channels).
2. Tool behaviour (laptop, Docker, minutes): nf-test of `FASTQ_DEMULTIPLEX_FQTK` on the same fixtures. Checks: reads start
   after the barcode and skipped bases (template = `chrA` of the fixture `tiny.fa`); read counts per sample equal the
   fixtures' assignment (LIBB1 L001: 68 pairs, 30 / 20 / 10 / 0 under exact matching, from the old demux test;
   under 1 mismatch the same; LIBX 150 per sample, 20 unmatched, per lane).
3. Cluster wiring (hazel, Apptainer): `-profile hpc_dev -stub-run` on a minimal sheet (one library per kit, fewest rows),
   since stub time is task count x Slurm overhead.
4. Resource profile (hazel, <= 30 min per process): one BC1 lane and one batch-1 lane with `--head`; CPU, peak memory
   and throughput from the trace, written as numbers in `conf/hpc_dev.config` / `conf/hpc_prod.config`.

- Budget: all laptop tests (1 and 2) together <= 5 min, one test <= 1 min; going over is a bug to fix, not to wait
  out. The report gives the measured times.

## Done when

- Stub and tool tests pass; `nf-core pipelines lint` has no failures.
- The channel-level DAG of the stub run shows `FQTK -> CAT_FASTQ` per library.
- Resource numbers are in `conf/hpc_dev.config` / `conf/hpc_prod.config`, measured, one line per process.
- The report lists the choices made during the work.
