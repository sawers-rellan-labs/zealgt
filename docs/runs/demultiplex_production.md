# Run plan: production demultiplexing

## Why

User, 2026-10-03, once the split passed its tests: plan the production run of the demultiplex step. Every library is
demultiplexed once; its per-sample FASTQs, read QC and samplesheets are kept, and `ALIGNMENT` batches are chosen from
them (Milestone 5).

The `/share` quota (20 TB) is the whole group's, and others work there or may (user, 2026-10-03), so the run is split
into waves that each hold a bounded amount of `work/`.

## Inputs and outputs

- Input: `meta/samples.csv`: 80 libraries, 2,304 rows, 2,283 kept. Every library has a kept well.
- Wave sheets: `meta/waves/demultiplex_<NN>.csv`, the rows of `meta/samples.csv` for that wave's libraries, unchanged.
  A library is never split across waves (fqtk needs all its barcodes and lanes); a wave never mixes sequencing
  batches (`source`).
- Outputs, `--outdir /rsstu/users/r/rrellan/BZea/ZEAL/demultiplex` (user):
  - `<source>/<sample_id>_R{1,2}.fastq.gz`, flat per sequencing batch (`bc1`, `bc2s3_batch1`, `bc2s3_batch2`; user).
  - `<source>/demultiplex_<NN>.csv`: the wave's FASTQ samplesheet (`sample_id,fastq_1,fastq_2,library,lanes,kit`).
  - `reports/demux/<library>.<lane>.demux_metrics.txt` (fqtk), `reports/sequali/<sample_id>.{html,json}`.
  - `multiqc/reads/demultiplex_<NN>/multiqc_report.html`, one read-QC report per wave; `pipeline_info/` (timestamped).
- The multiplexed originals stay where they are.

## Waves (cap: 2 TB of `work/` per wave, user)

From `agent/demux_split/plan_waves.py 2.0` on real per-library sizes (lane files on hazel; batch 1 from the tar
listing). Peak factors per GB of raw: bc1 1.7 (measured on 1C), batch 2 0.85 (one lane, no join), batch 1 2.7 (tar
members extracted, then lanes and joins).

| wave | source       | libraries         | kept samples | raw TB | `work/` peak TB | final TB |
| ---- | ------------ | ----------------- | ------------ | ------ | --------------- | -------- |
| 01   | bc1          | 1A-1D (4)         | 48           | 1.07   | 1.82            | 0.91     |
| 02   | bc1          | 1E-2B (6)         | 72           | 1.07   | 1.81            | 0.91     |
| 03   | bc1          | 2C-3C (9)         | 108          | 1.10   | 1.88            | 0.94     |
| 04   | bc1          | 3D-4D (9)         | 108          | 0.97   | 1.66            | 0.83     |
| 05   | bc1          | 4E-4H (4)         | 48           | 0.75   | 1.28            | 0.64     |
| 06   | bc2s3_batch2 | V21A-V24H (32)    | 384          | 0.51   | 0.43            | 0.43     |
| 07   | bc2s3_batch1 | BZea2-BZea9 (8)   | 747          | 0.73   | 1.97            | 0.62     |
| 08   | bc2s3_batch1 | BZea10-BZea17 (8) | 768          | 0.73   | 1.96            | 0.62     |
| all  |              | 80                | 2,283        | 6.94   | max 1.97        | 5.90     |

- `/share` holds at most one wave (<= 2 TB), plus the leftovers of a failed attempt until they are removed (below).
  Group use was 0.97 TB of 20 TB on 2026-10-03 (0.8 TB of it this project's measurement `work/`, to remove).
- `/rsstu` gets 5.9 TB of FASTQs (18 TB free; CRAMs need ~2.4 TB later).

## Measured (full libraries 1C and BZea5, `hpc_prod`, jobs 1067152 / 1067407)

| step             | measured                                                                                  | in production         |
| ---------------- | ----------------------------------------------------------------------------------------- | --------------------- |
| untar (batch 1)  | <= 2 min per lane, 35 GB per BZea5 lane                                                   | BZea2 ~4 min          |
| fqtk             | 1C lanes (713 M pairs) 43-48 min, BZea5 lanes (224-230 M) 19 min; 1.6 GB; ~3.5 of 5 cores | bc1 waves ~50 min     |
| lane joins       | <= 1 min 46 s per 1C sample (28 GB)                                                       | 4E's largest ~2.5 min |
| Sequali          | 12 min, 1.3 cores, 0.6 GB on a 236 M-pair 1C sample (job 1068396)                         | <= ~16 min            |
| copy to `/rsstu` | 307 GB in 15.5 min (~330 MB/s)                                                            | ~5 h over all waves   |
| unmatched        | 1C 2.1 %, BZea5 6.0 %                                                                     |                       |

Per wave about 1.5-3 h; 8 waves about 12-24 h plus queue waits.

## Choices this plan settles

- **One Nextflow run per wave, waves one after another**, each with `cleanup = true` (`hpc_prod`): Nextflow deletes a
  run's `work/` only after it succeeded and published every output (publishing finishes before cleanup; a failed copy
  fails the run). Rejected: one run (~13.8 TB peak in the group's quota); `buffer`/barriers inside one run (nothing
  deletes a finished batch's files before the run ends); nf-boost (experimental); deleting `work/` by hand or script.
- **The chain is Slurm dependencies**: `scripts/submit_demultiplex_waves.sh <first wave>` submits one head job per wave
  from `<first wave>` on, each `--dependency=afterok:<previous>`, on the normal QOS with `--time=1-00:00:00`. Rejected:
  a loop inside one long head job (one time limit for all waves); a Slurm array `%1` (failed waves would pile up
  `work/`).
- **First attempts run without `-resume`** (a fresh session each); recovery uses `-resume <session id>` (`nextflow log`
  in `nf_work/zealgt_prod`). A bare `-resume` takes the last session in the launch directory, whichever run it was.
- **One launch directory, `nf_work/zealgt_prod`, and nothing else runs there during the chain** (two runs there at once
  fail on the cache lock).
- **A frozen checkout runs production**: a git worktree of the merged commit, e.g. `/rsstu/.../ZEAL/zealgt_prod` at tag
  `demux-prod-<date>`, with `scripts/submit_head_job.sbatch` taking `REPO` from the environment (default unchanged).
  Development can then pull into the usual checkout during the chain.
- **`CAT_FASTQ` arrays of 20**, half of `queueSize` (40). An array equal to the queue waits for the queue to drain; 50
  was rejected by Nextflow and failed job 1067152.
- **Waves cut along sequencing batches and filled to 2 TB** (user). Rejected: waves by library count.

## When a wave fails

1. `afterok` never releases the later waves: they stay pending (`DependencyNeverSatisfied`); `scancel` them.
2. Read the failed task's `.command.err` (`docs/running.md`); fix on the laptop; merge; move the production tag.
3. Resubmit from the failed wave: `scripts/submit_demultiplex_waves.sh <NN>` with `-resume <session id>` for that wave.
4. **The failed attempt's task folders stay in `work/` after the recovery succeeds** (`cleanup` deletes only what the
   successful run made; shown on Nextflow 26.04.6 by the adversarial review). They go on the user's removal list
   (`nextflow clean -f <failed run name>`, run by the user) before the next wave can add another 2 TB.

## Code still to change before the run (next session)

1. `--outdir` layout: FASTQs to `<source>/<sample_id>_R{1,2}.fastq.gz` (add `source` to `assets/schema_input.json` meta
   and to the FASTQ record); the samplesheet index to `<source>/<input basename>.csv`; the read-QC MultiQC to
   `multiqc/reads/<input basename>/`, so waves never overwrite each other's sheet or report.
2. `conf/hpc_prod.config`: `CAT_FASTQ` array 20; `FQTK` time 2 h kept (48 min measured; GPFS contention), the comments
   with the measured numbers; `EXTRACT_LANE` 30 min.
3. `scripts/submit_head_job.sbatch`: `REPO=${ZEALGT_REPO:-/rsstu/users/r/rrellan/BZea/ZEAL/zealgt}`.
4. `scripts/submit_demultiplex_waves.sh` (the chain) and `meta/waves/demultiplex_<NN>.csv` (from
   `agent/demux_split/plan_waves.py`, moved to `meta/` as `write_wave_sheets.py`).
5. Check on the laptop why no lane join started before every fqtk lane had finished (1067407: BZea5's joins waited 50
   min for 1C's lanes): job-array batching or the channel wiring. Arrays of 20 may be enough; test with arrays off.

## Before the run

1. The code changes above, laptop tests (<= 5 min), CodeRabbit on the new code, PR merged.
2. **`hpc_prod` stub of all 8 waves**, chained by the same script, `--outdir .../ZEAL/demultiplex_stub` (never the real
   outdir: stub files would land among the real FASTQs). The `hpc_dev` stubs never used `hpc_prod` settings; that is how
   the array bug reached a full-size run.
3. The measurement's scratch removed by the user: `/rsstu/.../ZEAL/demultiplex_measure` (307 GB),
   `nf_work/zealgt_prod/work` (0.8 TB), `nf_work/prod_measure/`.
4. **The user's OK on the submission.** After that the waves run unattended.

## Done when

- Every wave succeeded and `cleanup` emptied its `work/`.
- The wave samplesheets together have 2,283 rows, each with both files present.
- Per lane, assigned + unmatched pairs in the fqtk metrics equal the lane's pairs; the unmatched rates per lane in one
  table in the report.
- `decisions.md` has the outdir, the folders by `source`, the 2 TB waves and the chain; the measured resources are in
  `conf/hpc_prod.config`.

## Not here

`ALIGNMENT` production waves: their own run plan, reading these samplesheets.
