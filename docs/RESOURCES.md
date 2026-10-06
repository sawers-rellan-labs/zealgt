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

| process   | measured                                                                                                                       | `hpc_prod`                           | `hpc_dev`         |
| --------- | ------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------ | ----------------- |
| `SEQUALI` | 236 M-pair 1C sample (S_1C_6, job 1068396): 12 min, 1.3 of 2 cpus, 0.6 GB; 35-42 k pairs: 0.4-0.5 GB, < 10 s                   | 1 cpu, 2 GB, 1 h                     | 2 cpus, 2 GB, 1 h |
| `MULTIQC` | read QC, peak by samples: 4: 0.7 GB; 48: 1.0; 72: 1.1; 108: 1.3; 384: 2.9 (3.4 min); 747: 5.5 (4.5 min); 768: 5.7 GB (5.4 min) | 1 cpu, 7 GB x attempt, 1 h x attempt | 1 cpu, 2 GB, 1 h  |

`SEQUALI` 1 cpu in production: wave 07 failed twice on PN7_SID583 with `UnicodeDecodeError` in the R1/R2 name check
(garbage bytes, different each time) although its FASTQs are intact (gzip ok, 6,256,639 records each, all names ASCII).
Under Nextflow's task wrapper on the same node, `-t 2` failed 9 of 9 and `-t 1` passed 3 of 3 (jobs 1078114, 1078222,
1078347); outside the wrapper `-t 2` passed 29 of 29. Waves 01-06 ran with `-t 2`; their Sequali reports are QC only.

Wave 08 then failed on PN11_SID979 with a segmentation fault (exit 139) at `-t 1`: FASTQs intact (gzip ok, 466,108
records each, names and quality lengths clean); outside the wrapper `-t 1` and `-t 2` passed 4 of 4, the wrapper replay
failed (jobs 1080540, 1080545). One thread is not the fix; `SEQUALI` is `errorStrategy 'ignore'` in production.

`MULTIQC` 7 GB: measured 5.7 GB at 768 samples (wave 08) plus ~20 %. At 4 GB waves 07 and 08 ran out of memory (exit 137) and passed on the 8 GB retry, ~3 min lost each. Rule: a base is the measured trend plus ~20 %; the doubling retry
covers scales never measured (user, 2026-10-04).

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

Estimates for full samples (BC1 166-311 M pairs; S_1A_6 ~259 M, the deepest; PN2_SID151 ~14.3 M; job 1054578). Since
Milestone 2a `MINIBWA_MAP` to `SAMTOOLS_SORT` run per chunk of 50 M pairs (S_1A_6: 6 chunks), from the per-pair rates:
map ~39 min at 12 cpus, clip ~10 min, fixmate ~14 min, sort ~4 min per chunk; the table's other times are per whole
sample (whole-sample map ~3.4 h; 9.8 GB = index 4.9 GB + batches). Picard measured in
`docs/later/picard_fast_algorithm.md` (zealgt-old: 2 h 18 min at 310 M pairs).

| process                    | estimate at S_1A_6                               | `hpc_prod`                      |
| -------------------------- | ------------------------------------------------ | ------------------------------- |
| `SEQKIT_SPLIT2`            | not measured                                     | 4 cpus, 2 GB, 2 h (placeholder) |
| `MINIBWA_MAP`              | ~39 min per chunk at 12 cpus; 9.8 GB             | 16 cpus, 16 GB, 2 h per chunk   |
| `FGUMI_CLIP`               | ~51 min, streams                                 | 2 cpus, 4 GB, 2 h               |
| `SAMTOOLS_FIXMATE`         | ~71 min, streams                                 | 4 cpus, 1 GB, 2 h               |
| `SAMTOOLS_SORT`            | ~20 min; 768 MB per thread x 6                   | 6 cpus, 6 GB, 1 h               |
| `SAMTOOLS_MERGE`           | not measured                                     | 4 cpus, 2 GB, 2 h (placeholder) |
| `SAMTOOLS_MARKDUP`         | ~13 min; no growth with pairs seen (provisional) | 4 cpus, 8 GB, 1 h               |
| `SAMTOOLS_INDEX`           | seconds                                          | 1 cpu, 1 GB, 1 h                |
| `SAMTOOLS_STATS`           | 50 min at 310 M pairs (zealgt-old)               | 2 cpus, 2 GB, 2 h               |
| `PICARD_COLLECTWGSMETRICS` | 42 min, 4.2 GB (measured, deepest BC1)           | 1 cpu, 5 GB, 2 h                |
| `MOSDEPTH`                 | threads help only CRAM decoding at full size     | 4 cpus, 4 GB, 2 h               |

`hpc_dev` runs heads of up to ~6 M pairs per sample: minutes per task, 1 h each; `SEQKIT_SPLIT2` and `SAMTOOLS_MERGE`
4 cpus, 2 GB. All `hpc_prod` alignment and CRAM QC tasks now run on the default `compute_partners` / short QOS (2 h
limit; Milestone 2a); Picard retries once on `compute` / normal with 4 h if it outlives that.

## Split alignment, measured (2026-10-05, Milestone 2a, job 1100086)

10 full samples, `hpc_dev` with the `hpc_prod` alignment lines (`agent/m2a_full/`): BC1 S_2A_3 (4.97x, 2 chunks) and
S_2F_1 (3.48x, 2), ERR3288215 (13.3x, 3), 7 batch-1 lines and checks (0.22-0.53x, 1 each). 2 h 39 min wall, no
failure or retry; every task started at once on `compute_partners` (ERR3288215's Picard on `compute` / normal by
request, 1 h 01 min).

| process                    | tasks | max realtime                                     | max peak RSS | requested           |
| -------------------------- | ----- | ------------------------------------------------ | ------------ | ------------------- |
| `SEQKIT_SPLIT2`            | 10    | 9 min 19 s                                       | 202 MB       | 4 cpus, 2 GB, 2 h   |
| `MINIBWA_MAP`              | 14    | 33 min 35 s per 50 M-pair chunk (24-34 min full) | 10.4 GB      | 16 cpus, 16 GB, 2 h |
| `FGUMI_CLIP`               | 14    | 5 min 34 s                                       | 2.8 GB       | 2 cpus, 4 GB, 2 h   |
| `SAMTOOLS_FIXMATE`         | 14    | 8 min 01 s                                       | 25 MB        | 4 cpus, 1 GB, 2 h   |
| `SAMTOOLS_SORT`            | 14    | 7 min 15 s                                       | 5.0 GB       | 6 cpus, 6 GB, 1 h   |
| `SAMTOOLS_MERGE`           | 10    | 20 min 13 s (ERR3288215)                         | 18 MB        | 4 cpus, 2 GB, 2 h   |
| `SAMTOOLS_MARKDUP`         | 10    | 8 min 33 s                                       | 1.2 GB       | 4 cpus, 8 GB, 1 h   |
| `SAMTOOLS_INDEX`           | 10    | 10 s                                             | 15 MB        | 1 cpu, 1 GB, 1 h    |
| `SAMTOOLS_STATS`           | 10    | 13 min 31 s                                      | 416 MB       | 2 cpus, 2 GB, 2 h   |
| `PICARD_COLLECTWGSMETRICS` | 10    | 1 h 01 min (ERR3288215, 13.3x); BC1 <= 37 min    | 4.1 GB       | 1 cpu, 5 GB, 2 h    |
| `MOSDEPTH`                 | 10    | 1 min 36 s                                       | 3.1 GB       | 4 cpus, 4 GB, 2 h   |
| `MULTIQC`                  | 1     | 1 min 27 s                                       | 733 MB       | 1 cpu, 7 GB, 1 h    |

- The head job (1 cpu, 8 GB, `scripts/submit_head_job.sbatch`) peaked at its 8 GB (sacct MaxRSS 8.0 GB): larger runs
  give it more with `sbatch --mem=...`.
- `SAMTOOLS_SORT` peaked at 5.0 of 6 GB per chunk.

## Production demultiplexing, measured (2026-10-03/04, `hpc_prod`)

| wave | source       | samples | head job | run time                             |
| ---- | ------------ | ------- | -------- | ------------------------------------ |
| 01   | bc1          | 48      | 1071107  | 1 h 32 min                           |
| 02   | bc1          | 72      | 1071108  | 1 h 17 min                           |
| 03   | bc1          | 108     | 1071109  | 1 h 14 min                           |
| 04   | bc1          | 108     | 1071110  | 1 h 03 min                           |
| 05   | bc1          | 48      | 1071111  | 1 h 14 min                           |
| 06   | bc2s3_batch2 | 384     | 1071112  | 50 min                               |
| 07   | bc2s3_batch1 | 747     | 1078372  | 1 h 27 min (third attempt, resumed)  |
| 08   | bc2s3_batch1 | 768     | 1084546  | 1 h 32 min (second attempt, resumed) |

- 2,283 samples, 5.6 TB of FASTQs (estimate 5.9 TB). `/share` stayed under 2 TB per wave plus failed attempts' leftovers
  (peak ~3.3 TB).
- Read pairs and unmatched fraction per lane (fqtk metrics, 175 lanes): bc1 111 lanes, 36.4 G pairs, unmatched 2.3 %
  (lanes 2.1-2.9 %); batch 2 32 lanes, 3.7 G, 2.2 % (2.0-2.5 %); batch 1 32 lanes, 8.9 G, 5.8 % (5.1-6.4 %).

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

## GENOTYPE variant discovery, measured (2026-10-05, Milestone 7, job 1101952)

Donor Zx.0540_P3 on chr10:1-20 Mb: 2 BC1 pools (3.5-5.0x), 4 lines (witness), 3 B73 checks, ERR3288215 (13.3x), all
from the full split-alignment CRAMs (job 1100086). 3 min 52 s wall, 21 tasks, `hpc_dev` placeholders; too small to set
whole-chromosome resources (the pilot does).

| process                    | max realtime | max peak RSS | requested         |
| -------------------------- | ------------ | ------------ | ----------------- |
| `CHECK_COUNTS`             | 31 s         | 619 MB       | 1 cpu, 2 GB, 1 h  |
| `CHECK_ALT_RATE`           | < 1 s        | 3.4 MB       | 1 cpu, 1 GB, 1 h  |
| `SAMTOOLS_MERGE` (pools)   | 7 s          | 327 MB       | 4 cpus, 4 GB, 1 h |
| `SAMTOOLS_ADDREPLACERG`    | 19 s         | 403 MB       | 2 cpus, 2 GB, 1 h |
| `CRISP`                    | 45 s         | 196 MB       | 1 cpu, 16 GB, 2 h |
| `BED_CLIP`, `WITNESS_VETO` | < 1 s        | 3.5 MB       | 1 cpu, 1 GB, 1 h  |
| `BCFTOOLS_MPILEUP`         | 5 s          | 221 MB       | 1 cpu, 2 GB, 1 h  |
| `POOLED_LIKELIHOOD_TIERS`  | < 1 s        | 13 MB        | 1 cpu, 4 GB, 1 h  |

## GENOTYPE sites union and gap filling, measured (2026-10-05, Milestone 8, job 1111002)

Both pilot donors on chr10:1-20 Mb: 10 BC1 samples and 2 B73 controls counted at 8,053 union sites, from the pilot
alignment's CRAMs. 11 min 11 s wall for the whole `--step genotype` (discovery included), `hpc_dev`. Every union
process stays under 250 MB and 7 s, so `hpc_dev` gives each 1 cpu, 1 GB, 1 h; whole-chromosome values come with the
chr10 run plan.

| process               | tasks | max realtime | max peak RSS |
| --------------------- | ----- | ------------ | ------------ |
| `BCFTOOLS_MERGE`      | 1     | < 1 s        | 3.4 MB       |
| `BCFTOOLS_NORM`       | 1     | 6.8 s        | 10.8 MB      |
| `BIALLELIC_UNION`     | 1     | < 1 s        | 3.4 MB       |
| `COUNT_UNION`         | 12    | 6.0 s        | 233 MB       |
| `UNION_TIERS`         | 2     | 1.3 s        | 29.8 MB      |
| `FILL_DONOR_ALLELES`  | 1     | < 1 s        | 11.2 MB      |
| `DONOR_ALLELES_INDEX` | 1     | < 1 s        | 3.5 MB       |

`DONOR_ALLELES_INDEX` was folded into `FILL_DONOR_ALLELES` afterwards: pysam writes the `.vcf.gz` and its `.tbi`.

### Ancestry with RTIGER (Milestone 9), whole chr10

Both pilot donors on the whole chr10 (`hpc_dev`, jobs 1113306 and 1113622, resuming job 1111642): 82 lines counted at
their donor's tier-A sites (32,750 and 48,251), RTIGER on 39 and 43 lines, the grid from 70,210 union sites. Every
ancestry process stays under 400 MB and 1 min, so `hpc_dev` and `hpc_prod` give each 1 cpu, 1 GB, 1 h. RTIGER runs on
one thread (nilhmm#31).

| process              | tasks | max realtime | max peak RSS |
| -------------------- | ----- | ------------ | ------------ |
| `COUNT_LINES`        | 82    | 3.9 s        | 241 MB       |
| `CALL_ANCESTRY`      | 2     | 49 s         | 393 MB       |
| `ANCESTRY_GRID`      | 1     | 1.9 s        | 51.9 MB      |
| `ANCESTRY_VCF_INDEX` | 2     | < 1 s        | 4.2 MB       |
