# Run plan: pilot alignment

## Why

User, 2026-10-05: "if full split alignment of those 10 samples runs ok then send the pilot alignments." The pilot
reproduces the two mexicana donors of zealgt-old (Zx.0540_P3, Zx.0570_P2) with GENOTYPE; every sample it needs is
aligned once, whole genome, with the split alignment of Milestone 2a.

## Inputs and outputs

- Input: `docs/runs/alignment_pilot/samplesheet.csv`, 107 rows, from the production demultiplexing sheets
  (`ZEAL/demultiplex/samplesheets/demultiplex_0*.csv`) and `meta/samples.csv` (`exclude` = FALSE):
  - Zx.0540_P3: 5 BC1 pools, 40 lines; Zx.0570_P2: 5 BC1 pools, 44 lines (`bc2s3_batch1`);
  - the 12 batch-1 B73 checks (`role` = check, pedigree `B73-bulk`);
  - `B73_ERR3288215` (NCBI B73, 15.5x; `ZEAL/raw/B73_control/ERR3288215/`).
- Outputs, `--outdir /rsstu/users/r/rrellan/BZea/ZEAL/alignment`: `cram/<sample_id>.cram` + `.crai` and the CRAM QC
  next to them (copied, `hpc_prod`); `multiqc/`, `pipeline_info/`.

## Settings

- `hpc_prod`, one Nextflow run, `cleanup = true`; launch directory `nf_work/zealgt_prod`, nothing else runs there.
- Code: the merged commit of Milestone 2a (user: merge once the 10-sample run passes), frozen as a worktree at tag
  `align-pilot-<date>` (`ZEALGT_REPO`), as in `demultiplex_production.md`.
- Every task on `compute_partners` / short (Milestone 2a); only the 1-CPU head job on `compute` / normal
  (`--time=1-00:00:00`, `--mem=32G`: the 10-sample run's head job peaked at its 8 GB, `docs/RESOURCES.md`).
- Wall time, from the 10-sample run (2 h 39 min, deepest BC1 4.97x): about 3-4 h if all chunks start at once;
  the 10 BC1 pools give about 30 chunks of 16 cpus each.
- First attempt without `-resume`; recovery with `-resume <session id>`.

## Size (estimates; `docs/RESOURCES.md` after the 10-sample run)

- `/share` `work/` peak: about 1.5 TB at most (chunks, per-chunk BAMs and merges of 10 BC1 pools at 8-11 GB of gzipped
  reads each, 96 small samples, ERR3288215 at 28 GB), freed by `cleanup` after success. Group quota 20 TB, 0.66 TB used
  on 2026-10-05.
- `/rsstu`: about 0.1 TB of CRAMs (12 TB free).

## Before the run

1. Milestone 2a: equivalence on S_2A_3 (4 M pairs) and the 10-sample full run pass; CodeRabbit done (0 findings).
2. PR of `m2a-split-alignment` merged into `dev`; tag `align-pilot-<date>`; worktree `ZEAL/zealgt_prod` moved to it.
3. The user's OK: given 2026-10-05 ("then send the pilot alignments"), on condition 1.

## Done when

- The run succeeded and `cleanup` emptied its `work/`.
- 107 CRAMs with `.crai` and CollectWgsMetrics in `ZEAL/alignment/cram/`; MEAN_COVERAGE per sample recorded in the run's
  report.

## Attempts

- 2026-10-05 05:20, head job 1102015 (tag `align-pilot-20261005`, `--mem=32G`): **succeeded** at 08:51 (3 h 31 min).
  107 CRAMs with CollectWgsMetrics in `ZEAL/alignment/cram/` (62 GB); no retry. The head job's sacct MaxRSS was
  33.5 GB, at its limit as in the 10-sample run at 8 GB: the Nextflow JVM grows into what it is given, so the peak is
  not a need (V21 runs with 16 GB).
- MEAN_COVERAGE (median, range): BC1 pools Zx.0540_P3 3.48x (2.07-5.07), Zx.0570_P2 3.33x (2.81-4.94); lines
  Zx.0540_P3 0.29x (0.003-0.40), Zx.0570_P2 0.36x (0.011-0.48); B73 checks 0.35x (0.22-0.53); ERR3288215 13.3x.
  Under the 0.05x cut of GENOTYPE: PN6_SID484 (0.003x), PN8_SID736 (0.011x). Per sample: `agent/pilot_align/pilot_coverage.tsv`
  (laptop).
