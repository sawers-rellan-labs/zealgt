# Picard CollectWgsMetrics `--USE_FAST_ALGORITHM` on full-depth BC1

Test of 2026-10-03 on hazel: does `--USE_FAST_ALGORITHM true` give identical CollectWgsMetrics output, faster?

## The flag

`picard CollectWgsMetrics --help`, Picard 3.5.0 (the pipeline's image):

> `--USE_FAST_ALGORITHM <Boolean>If true, fast algorithm is used.  Default value: false. Possible values: {true, false}`

Picard 3.5.0 source, raw text:

- `src/main/java/picard/analysis/CollectWgsMetrics.java`: "The fast algorithm works better for regions of BAM file
  with coverage at least 10 reads per locus, for lower coverage the algorithms perform the same."
- `src/test/java/picard/analysis/CollectWgsMetricsTest.java`: "NOTA BENE: The fast and regular algorithms differ in how
  the cap coverage, so if one writes the same test for both algos, make sure that the coverage cap isn't hit in either
  case as that could lead to different results and concerns about bugs..."

## Setup

- CRAM: `/rsstu/users/r/rrellan/BZea/ZEAL/store/cram/S_3A_12.cram`, the deepest of the 48 BC1 CRAMs there:
  MEAN_COVERAGE 5.52x (top of the 0.9-5.5x range). Passed STRICT validation.
- Reference: `Zm-B73-REFERENCE-NAM-5.0.fa`; image: Picard 3.5.0 (`modules/nf-core/picard/collectwgsmetrics/main.nf`).
- Command: `picard -Xmx4096M CollectWgsMetrics --INPUT <cram> --OUTPUT <out> --REFERENCE_SEQUENCE <fa>`, with and
  without `--USE_FAST_ALGORITHM true`; under `/usr/bin/time -v`.
- Slurm: compute / normal, 1 CPU, 5 GB; both jobs at the same time on the same node (c207n02).
- Jobs: 1061789 (default), 1061790 (fast).

## Result

Not identical. Metrics table, the fields that differ (all others equal, PCT_EXC_CAPPED included):

| Field                | Default  | Fast     |
| -------------------- | -------- | -------- |
| MEAN_COVERAGE        | 5.523014 | 5.523023 |
| SD_COVERAGE          | 3.611918 | 3.611926 |
| PCT_EXC_TOTAL        | 0.557014 | 0.557013 |
| PCT_10X              | 0.135116 | 0.135117 |
| FOLD_80_BASE_PENALTY | 2.761507 | 2.761512 |

Histogram (`high_quality_coverage_count`, bins 0-250): 38 bins differ; 5,182 loci move between bins (net 0) out of
2,178,268,108; largest relative difference 0.86 % at bin 99. Bins 0 and 248-250 are equal.

| Run     | Wall time   | CPU time (user) | Peak RSS |
| ------- | ----------- | --------------- | -------- |
| Default | 42 min 11 s | 2,501 s         | 4.22 GB  |
| Fast    | 36 min 38 s | 2,169 s         | 4.13 GB  |

The fast algorithm saves 5.5 min (13 %) per sample at 5.5x; across 384 BC1 samples ~35 CPU-hours, little wall time.

## Recommendation

Keep the default algorithm: the output is not identical, and 13 % of one parallel task is not worth the change.
