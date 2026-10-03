# Run plan: production demultiplexing

## Why

User, 2026-10-03, once the split passed its tests: plan the production run of the demultiplex step. Every library is
demultiplexed once. Its per-sample FASTQs and samplesheets are then kept, and `ALIGNMENT` batches are chosen from them
(Milestone 5).

The `/share` quota (20 TB) is the whole group's, and others work there or may (user, 2026-10-03), so the run is split
into waves that each hold a bounded amount of `work/`.

## Inputs and outputs

- Input: `meta/samples.csv`: 80 libraries, 2,304 rows, 2,283 kept. Every library has a kept well.
- Wave sheets: `meta/waves/demultiplex_<NN>.csv`, the rows of `meta/samples.csv` for that wave's libraries, unchanged.
  A library is never split across waves, because fqtk needs every barcode of a lane.
- Output per wave, `--outdir /rsstu/users/r/rrellan/BZea/ZEAL/demultiplex/wave_<NN>` (base folder: user, 2026-10-03):
  - `fastq/<sample_id>/<sample_id>_R{1,2}.fastq.gz` and `fastq/samplesheet.csv` (that wave's samples);
  - `reports/demux/<library>.<lane>.demux_metrics.txt` and `pipeline_info/`.
- The multiplexed originals stay where they are.

## Disk

Estimates from `agent/plan/facts_report.md`, to be replaced by the full-size measurement (1C, BZea5).

- Raw data: 6.9 TB in total. FlexPrep ~5.4 TB (BC1 libraries up to ~370 GB each, batch 2 small); batch 1 1.46 TB
  (16 libraries, ~90 GB each, in plate tars).
- `work/` held by a wave until it succeeds, per GB of raw:
  - FlexPrep: lane FASTQs from fqtk 0.85 + joined per-sample FASTQs 0.85 ≈ 1.7;
  - batch 1: extracted tar members 1.0 + 1.7 ≈ 2.7.
- A wave's peak = sum over its libraries of raw x factor. Waves are filled in `meta/samples.csv` order up to a cap
  **C** (open: the user's number, e.g. 2 or 3 TB of `/share`).
- Example at C = 3 TB: ~1.7 TB raw FlexPrep or ~1.1 TB raw batch 1 per wave, ~5 waves in all.
- `/rsstu` gets the published copies: ~5.8 TB of 18 TB free (CRAMs ~2.4 TB later).

## Choices this plan settles

- **One Nextflow run per wave, waves one after another.** Each run ends with `cleanup = true` (`hpc_prod`), which deletes
  that run's `work/` only after it succeeded and published every output. So at most one wave's `work/` exists at a time.
  - Rejected: one run for all libraries (~13.5 TB peak in the group's quota).
  - Rejected: `buffer` or a barrier inside one run. Nothing deletes a finished batch's files before the run ends, so the
    peak is the same.
  - Rejected: nf-boost's early cleanup (experimental, untested here).
  - Rejected: deleting a wave's `work/` by hand or by script (`rm -rf`). `cleanup` does it, only after success.
- **One launch directory, `nf_work/zealgt_prod`, for every wave.** Its cache serves `-resume` of any failed wave.
  Rejected: a `-work-dir` per wave, which only matters if waves run at the same time.
- **The chain is Slurm dependencies.** One submission (`scripts/submit_demultiplex_waves.sh`, to write) submits one head
  job per wave with `--dependency=afterok:<previous head job>`; each runs
  `submit_head_job.sbatch hpc_prod --step demultiplex --input meta/waves/demultiplex_<NN>.csv --outdir .../wave_<NN> -resume`.
  - If a wave fails, `afterok` never releases the later ones. Its `work/` stays for `-resume`; the failed wave is fixed,
    resubmitted, and the remaining waves are chained again.
  - Rejected: a loop of `nextflow run` inside one long head job. One job's time limit would cover every wave, and a
    failure would need the loop's restart logic.
- **Outputs are copied to `/rsstu` during each run.** A failed copy fails the run, so `cleanup` never runs before the
  outputs are safe.
- **One samplesheet per wave.** No overwrite between runs. The whole-dataset sheet is the wave sheets joined under one
  header; `ALIGNMENT` waves can reuse the same wave sheets.

## Before the run

1. **Full-size measurement** of 1C and BZea5 (running, `hpc_prod`, `ZEAL/demultiplex_measure`): per-process time, memory,
   task disk; the copy time to `/rsstu`. Sets `conf/hpc_prod.config` and the factors above.
2. **The cap C** from the user, then the wave sheets.
3. **`hpc_prod` stub run** of every wave sheet, chained as in production (`-stub-run`). The `hpc_dev` stubs never used
   `hpc_prod` settings: its `CAT_FASTQ` arrays (50, above `queueSize` 40) failed the first full-size run (job 1067152).
4. **The user's OK on the submission.** After that the waves run unattended.

## Done when

- Every wave succeeded and `cleanup` emptied its `work/`.
- The wave samplesheets together have 2,283 rows, each with both files present.
- Per lane, assigned + unmatched pairs in the fqtk metrics equal the lane's pairs. Unmatched rates per lane go into one
  table in the report.
- `decisions.md` has the outdir and the wave design; the measured resources are in `conf/hpc_prod.config`.

## Not here

`ALIGNMENT` production waves: their own run plan, reading these wave samplesheets.
