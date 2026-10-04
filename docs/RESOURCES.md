# Resources: measurements and estimates

The central record of what each process used on hazel and what the profiles request. `conf/hpc_dev.config` and
`conf/hpc_prod.config` hold only the values; run plans copy the numbers they rest on and point here.

A new measurement adds a row (job id, input, numbers) and changes the value in the config; peak from the Nextflow trace
(`peak_rss`, `realtime`, `%cpu`) or `sacct`. A limit that may be short at a scale never measured is the measured value
times `task.attempt`, not a padded guess: `base.config` retries once on exit 130-145, so only the failed task reruns,
with double the limit (user, 2026-10-03).

## Demultiplex

Measured on full libraries in `hpc_prod`: 1C (bc1, 3 lanes) and BZea5 (batch 1, 2 tar lanes), jobs 1067152 / 1067407.

| process        | measured                                                                                   | `hpc_prod`                          | `hpc_dev`         |
| -------------- | ------------------------------------------------------------------------------------------ | ----------------------------------- | ----------------- |
| `EXTRACT_LANE` | one BZea5 tar member (35 GB): 1.5-2 min, 6 MB                                              | 1 cpu, 1 GB, 30 min x attempt       | 1 cpu, 1 GB, 1 h  |
| `FQTK`         | 1C lanes (713 M pairs): 43-48 min; BZea5 lanes (224-230 M): 19 min; 1.6 GB; ~3.5 of 5 cpus | 5 cpus, 3 GB, 2 h (GPFS contention) | 5 cpus, 2 GB, 1 h |
| `CAT_FASTQ`    | <= 1 min 46 s per 1C sample (28 GB); BZea5 samples seconds, 21 MB                          | 1 cpu, 1 GB, 1 h, arrays of 20      | 1 cpu, 1 GB, 1 h  |

- `FQTK` refuses fewer than 5 threads. On heads of 3-5 M pairs per lane: 1.4-1.6 GB; on BZea5 L001 heads to 50 M
  (job 1065139): ~4.5 s per M pairs, flat 1.6 GB.
- `CAT_FASTQ` arrays: Nextflow rejects an array larger than `queueSize` (40; 50 failed job 1067152); an array as large as
  the queue waits for it to drain, so 20. A wave's last partial array waits for its last fqtk lane.
- `EXTRACT_LANE` time doubles on the retry: a batch-1 wave runs its 16 tar extractions at once (up to 77 GB each),
  ~405 MB/s from `/rsstu` to fit 30 min, about what wave 01's fqtk read alone (adversarial review, 2026-10-03).
- Unmatched reads: 1C 2.1 %, BZea5 6.0 %.
- Copy of published FASTQs to `/rsstu`: 307 GB in 15.5 min (~330 MB/s).

## Read QC

| process   | measured                                                                                                     | `hpc_prod`                           | `hpc_dev`         |
| --------- | ------------------------------------------------------------------------------------------------------------ | ------------------------------------ | ----------------- |
| `SEQUALI` | 236 M-pair 1C sample (S_1C_6, job 1068396): 12 min, 1.3 of 2 cpus, 0.6 GB; 35-42 k pairs: 0.4-0.5 GB, < 10 s | 2 cpus, 2 GB, 1 h                    | 2 cpus, 2 GB, 1 h |
| `MULTIQC` | 4 samples: 0.15 cpu, 0.7 GB, 1.5 min; grows with samples, unmeasured on a whole library                      | 1 cpu, 4 GB x attempt, 1 h x attempt | 1 cpu, 2 GB, 1 h  |

`MULTIQC` memory and time double on the retry: waves 07/08 summarise ~750 Sequali reports, never measured above 4
samples; measure wave 01's (48) and 07's before setting a fixed value.

## Alignment

Measured in `hpc_dev` on `--head 4000000` (job 1054576, commit ba7db36): BC1 S_1A_6 (572,525 pairs) and S_1A_12
(64,356), batch 1 PN2_SID151 (59,364) and PN2_SID141 (20,792). Per-pair rate = slope between S_1A_12 and S_1A_6.

| process            | cpus alloc / used | peak RSS 64 k / 573 k | time 64 k / 573 k | per pair |
| ------------------ | ----------------- | --------------------- | ----------------- | -------- |
| `MINIBWA_MAP`      | 12 / 10.3         | 5.6 / 9.8 GB          | 5.3 / 29.1 s      | 46.8 us  |
| `FGUMI_CLIP`       | 2 / 1.2           | 2.0 / 2.6 GB          | 5.3 / 11.3 s      | 11.8 us  |
| `SAMTOOLS_FIXMATE` | 2 / 1.0           | 18 / 17 MB            | 1.4 / 9.8 s       | 16.5 us  |
| `SAMTOOLS_SORT`    | 6 / 3.2           | 43 / 524 MB           | 0.8 / 3.1 s       | 4.5 us   |
| `SAMTOOLS_MARKDUP` | 6 / 2.1           | 1.3 / 0.9 GB          | 7.6 / 9.1 s       | 3.0 us   |
| `SAMTOOLS_INDEX`   | 2 / 0.5           | 6 / 7 MB              | 0.2 / 0.3 s       | 0.1 us   |

On the same heads: `SAMTOOLS_STATS` 1.7 cpus, 0.8 GB, seconds; `PICARD_COLLECTWGSMETRICS` 1 cpu, heap-bound 4.0 GB,
5-7 min (genome walk); `MOSDEPTH` 1 cpu, 3.1 GB, under 1 min.

Estimates for full samples (BC1 166-311 M pairs; S_1A_6 ~259 M, the deepest; PN2_SID151 ~14.3 M; job 1054578):

| process                    | estimate at S_1A_6                                 | `hpc_prod`                                  |
| -------------------------- | -------------------------------------------------- | ------------------------------------------- |
| `MINIBWA_MAP`              | ~3.4 h at 12 cpus; 9.8 GB (index 4.9 GB + batches) | 16 cpus, 16 GB, 6 h, `compute` / normal QOS |
| `FGUMI_CLIP`               | ~51 min, streams                                   | 2 cpus, 4 GB, 2 h                           |
| `SAMTOOLS_FIXMATE`         | ~71 min, streams                                   | 4 cpus, 1 GB, 2 h                           |
| `SAMTOOLS_SORT`            | ~20 min; 768 MB per thread x 6                     | 6 cpus, 6 GB, 1 h                           |
| `SAMTOOLS_MARKDUP`         | ~13 min; no growth with pairs seen (provisional)   | 4 cpus, 8 GB, 1 h                           |
| `SAMTOOLS_INDEX`           | seconds                                            | 1 cpu, 1 GB, 1 h                            |
| `SAMTOOLS_STATS`           | 50 min at 310 M pairs (zealgt-old)                 | 2 cpus, 2 GB, 2 h                           |
| `PICARD_COLLECTWGSMETRICS` | 2 h 18 min at 310 M pairs (zealgt-old)             | 1 cpu, 5 GB, 4 h, `compute` / normal QOS    |
| `MOSDEPTH`                 | threads help only CRAM decoding at full size       | 4 cpus, 4 GB, 2 h                           |

`hpc_dev` runs heads of up to ~6 M pairs per sample: minutes per task, 1 h each.

## Disk: production demultiplexing waves

`work/` peak per GB of raw reads: bc1 1.7 (measured on 1C), batch 2 0.85 (one lane, no join), batch 1 2.7 (tar members
extracted, then lanes and joins). Raw sizes from the lane files on hazel and the batch-1 tar listing
(`meta/write_wave_sheets.py`); final FASTQs ~0.85 x raw.

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
