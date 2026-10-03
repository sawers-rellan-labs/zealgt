# Run plan: production demultiplexing

## Why

User, 2026-10-03, once the split passed its tests: plan the production run of the demultiplex step. Every library is
demultiplexed once. Its per-sample FASTQs and samplesheet are then kept, and `ALIGNMENT` batches are chosen from the
samplesheet (Milestone 5).

## Inputs and outputs

- Input: `meta/samples.csv` as it is: 80 libraries, 2,304 rows, 2,283 kept. Every library has a kept well, so none is
  left out.
- Output, `--outdir /rsstu/users/r/rrellan/BZea/ZEAL/demultiplex` (user, 2026-10-03):
  - `fastq/<sample_id>/<sample_id>_R{1,2}.fastq.gz` (~5.8 TB) and `fastq/samplesheet.csv` (2,283 rows).
  - `reports/demux/<library>.<lane>.demux_metrics.txt` and `pipeline_info/`.
- The multiplexed originals stay where they are.

## Disk

All numbers below are from `agent/plan/facts_report.md`; they are estimates.

- `/share` holds `work/`. The quota is 20 TB, of which 0.6 TB is used.
  - Peak without early deletion ≈ 13.5 TB:
    - lane FASTQs from fqtk, 6.2 TB;
    - joined per-sample FASTQs, 5.8 TB;
    - extracted batch-1 tar members, 1.5 TB.
  - `cleanup = true` removes all of it after the run succeeds.
- `/rsstu` gets the published copy, 5.8 TB of 18 TB free. CRAMs need ~2.4 TB later.

## Choices this spec settles

- **One submission for all 80 libraries**, with `hpc_prod`. The peak of ~13.5 TB fits the quota.
  - It gives one samplesheet for the whole dataset.
  - Rejected: library batches. They are needed for `ALIGNMENT`'s ~53 TB peak, not here.
- **Outputs are copied to `/rsstu`.** This is the global `hpc_prod` mode, since `/rsstu` is another filesystem than
  `work/`. Rejected: links, which `/rsstu` (NFS) cannot hold to `/share` files.
- **The head job runs on the normal QOS** (4-day limit), as `hpc_prod` requires.

## Before the run

1. **CodeRabbit review** of the Milestone 5 code. This is the first real-data run of it over 15 minutes.
2. **Full-size measurement (needs your OK: full libraries).**
   - `hpc_dev`, `--step demultiplex`, no `--head`, on two full libraries:
     - 1C (FlexPrep): the largest FlexPrep lane, 48.8 GB R1 of 3 lanes, estimated ~28 min of fqtk. 4E's joins (4 lanes,
       181 GB R1, the most per library) are scaled from it (x 1.24); BC2S3 batch-2 lanes are small (one lane of ~5 GB).
     - BZea5 (batch 1): 2 lanes of 224 M pairs, estimated ~17 min per lane.
   - Both stay under the 30-minute limit per process. BZea2, the largest batch-1 library (~35 min of fqtk, over the
     limit), is scaled from BZea5.
   - Measured per process: wall time, peak memory and task disk for `EXTRACT_LANE`, `FQTK` and `CAT_FASTQ`. Also how
     long the copy to `/rsstu` takes.
   - The results go into `conf/hpc_prod.config`, one line per process; the output goes to `/share` scratch.
3. **`hpc_prod` stub run** of the whole `meta/samples.csv` (`-stub-run`, the production command otherwise). The
   `hpc_dev` stubs never used `hpc_prod` settings: its `CAT_FASTQ` job arrays (50, above `queueSize` 40) failed the
   full-size run (job 1067152).
4. **Your OK on the production submission.** After that the run is unattended.

## The run

- `sbatch --partition=compute --qos=normal --time=3-00:00:00 scripts/submit_head_job.sbatch hpc_prod --step demultiplex --input meta/samples.csv --outdir /rsstu/users/r/rrellan/BZea/ZEAL/demultiplex`.
  - The input path is taken from the hazel checkout.
- Expected wall time: hours.
  - ~250 lane tasks, at most 40 Slurm jobs at once (`queueSize`).
  - Then 2,283 `CAT_FASTQ` tasks, as Slurm job arrays.
  - The copy to `/rsstu` may set the pace; step 2 measures it.

## Done when

- The run succeeded and `cleanup` emptied its `work/`.
- `fastq/samplesheet.csv` has 2,283 rows, each with both files present.
- Per lane, assigned + unmatched pairs in the fqtk metrics equal the lane's pairs. Unmatched rates per lane go into
  one table in the report.
- `decisions.md` has the outdir and the one-submission choice; the measured resources are in `conf/hpc_prod.config`.

## Not here

`ALIGNMENT` production batches: their own run plan, which reads `fastq/samplesheet.csv`.
