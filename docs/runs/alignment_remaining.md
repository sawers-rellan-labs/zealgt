# Run plan: alignment of the remaining ZEAL samples (luxurians, huehuetenangensis, checks), after the parviglumis waves

Draft, 2026-10-14.

## Why

User, 2026-10-14: align the samples left without a CRAM after parviglumis (`alignment_parviglumis.md`), as a chain that
starts when the parviglumis chain ends.

## Inputs and outputs

- Samples: every `meta/samples.csv` row, not excluded, without a CRAM in `ZEAL/alignment/cram/` (1,815 on 10-14 09:00),
  of taxon luxurians or huehuetenangensis with role `bc1_sample` or `nil`, or of role `check`: 231 samples; rows from
  the production demultiplexing sheets, unchanged.

  | group             | donors | BC1 | lines | raw    |
  | ----------------- | ------ | --- | ----- | ------ |
  | luxurians         | 5      | 19  | 121   | 288 GB |
  | huehuetenangensis | 2      | 9   | 61    | 148 GB |
  | checks            | -      | -   | 21    | 18 GB  |
  | total             | 7      | 28  | 203   | 453 GB |

  The other 23 checks have CRAMs. After this chain every ZEAL BC1 sample, line and check has a CRAM.

- Raw FASTQ: 453 GB; largest sample 20 GB.
- Outputs: `--outdir /rsstu/users/r/rrellan/BZea/ZEAL/alignment`, as the other chains: `cram/<sample_id>.cram`, `.crai`
  and CRAM QC; ~145 GB of CRAMs (parviglumis: 0.32 x raw).

## Waves

Samples filled in sheet order up to 2 TB of `work/` peak at 8.0 x raw (measured on mexicana waves 01-06); numbered from
23, so the per-sheet MultiQC folders (`multiqc/alignment/<sheet>/`) do not collide with mexicana's 01-09, diploperennis's
10-12 and parviglumis's 13-22:

| wave | samples | BC1 | lines + checks | raw    | `work/` peak | estimate |
| ---- | ------- | --- | -------------- | ------ | ------------ | -------- |
| 23   | 22      | 22  | 0              | 245 GB | ~2.0 TB      | ~2.5 h   |
| 24   | 209     | 6   | 182 + 21       | 208 GB | ~1.7 TB      | ~4.5 h   |

Estimates: parviglumis BC1 waves 14-19 (12-35 samples, ~245 GB) ran 1 h 52 to 3 h 27 at `queueSize = 80`; its wave 21
(260 lines, 250 GB) ran ~5 h, its time set by the per-sample steps of many samples, not by the raw size. Both waves
~7 h; starting when parviglumis ends (~11:30-12:00 10-14), the chain ends ~19:00 (range ~17:30-21:00).

## Settings

- As `alignment_parviglumis.md` (`hpc_prod` at `queueSize = 80` with `executor.retry`, `cleanup = true`, chain with
  `afterok`, normal QOS, `--no-requeue`, head job 16 GB, `NXF_OPTS="-Xms1g -Xmx12g"`), except:
- The first wave waits for parviglumis's last wave (`AFTER=1220671`, wave 22; `afterok`); if it fails, this chain stays
  pending and is resubmitted with it.
- Checkout `ZEAL/zealgt_prod` (idle since mexicana ended) at the tag of this plan's merge; `dev` has no code change
  since `align-q80-20261012`, which the parviglumis waves run. `ZEAL/zealgt_prod_parv` stays at its tag while
  parviglumis runs.
- Launch folder `nf_work/zealgt_prod`, as mexicana and parviglumis (default, no `ZEALGT_LAUNCH`): the runs follow each
  other.
- Sheets `docs/runs/alignment_remaining/alignment_23.csv` and `_24.csv` (`agent/alignrest/write_wave_sheets.py`),
  submitted from `ZEAL/zealgt_prod`:
  ```
  AFTER=1220671 MEM=16G NXF_OPTS="-Xms1g -Xmx12g" WAVES=docs/runs/alignment_remaining bash scripts/submit_waves.sh alignment 23
  ```
- Stub: `docs/runs/alignment_remaining_stub/alignment_23.csv` (one BC1 sample, one line, one check), from the same
  checkout with `WAVES=docs/runs/alignment_remaining_stub OUTDIR=/rsstu/users/r/rrellan/BZea/ZEAL/alignment_stub`,
  `-stub`, no `AFTER`, and its own launch folder `ZEALGT_LAUNCH=/share/maize/frodrig4/nf_work/zealgt_prod_rest_stub`
  (parviglumis runs in `nf_work/zealgt_prod` now).

## Supervision

- As `alignment_mexicana35.md`: a background poller (`sacct`, `/share` usage, running CPUs, ssh and stat timings).
  Failed wave: `scancel` the pending ones, read `.command.err`, resubmit from that wave with `RESUME=<session id>`.
- `/share`: the session stops and asks if `frodrig4`'s usage passes 6 TB, or if the group's headroom falls below 2 TB.
- Genotype debugging runs on the same short QOS beside it (768 running CPUs per user); its tasks queue, they do not fail.

## Results (2026-10-16)

Run from tag `align-rest-arrays-20261016` instead of `align-rest-20261014`: job arrays of 20 on `SAMTOOLS_FIXMATE`,
`SAMTOOLS_SORT`, the per-sample `SAMTOOLS_MERGE`, `SAMTOOLS_INDEX`, `SAMTOOLS_STATS` and `MOSDEPTH` (user, 2026-10-16;
#48). No `AFTER`: parviglumis had ended. Before the submission: the stub with arrays (job 1317206, 9 min) and the hazel
process stub tests (26 of 26, job 1317802).

| wave | job     | time (10-16)         | task jobs | cpu h | `/share` peak | `work/` peak | running cpus peak |
| ---- | ------- | -------------------- | --------- | ----- | ------------- | ------------ | ----------------- |
| 23   | 1317749 | 2 h 44 (01:14-03:58) | 419       | 512   | 2.61 TB       | 1.82 TB      | 754               |
| 24   | 1317750 | 2 h 23 (04:02-06:25) | 2,324     | 749   | 2.41 TB       | 1.62 TB      | 769               |

- `/share` is `frodrig4`'s usage (baseline 0.79 TB before and after: `cleanup` emptied both waves' `work/`); `work/`
  peak = peak minus baseline, 7.4 and 7.8 x raw, against the 8.0 x of the estimate.
- All 231 samples have CRAM, index and CollectWgsMetrics in `ZEAL/alignment/cram/`; MultiQC in
  `multiqc/alignment/alignment_23` and `_24`. No task failed.
- MEAN_COVERAGE, median (range): wave 23 BC1 4.27x (1.99-7.81); wave 24 BC1 2.97x (2.24-3.49), lines and checks 0.32x
  (0.001-0.84). Under GENOTYPE's 0.05x floor: PN10_SID907 (0.001x) and PN11_SID979 (0.031x).
- Wave 24 took 2 h 23 against the ~4.5 h estimate from parviglumis wave 21 (260 lines, ~5 h, no arrays on these
  steps); the arrays are a likely part of it, not measured apart.

## Done when

- Both waves succeeded and `cleanup` emptied its `work/`; 231 CRAMs with index and CollectWgsMetrics in
  `ZEAL/alignment/cram/`; time, `work/` peak and CPU peak per wave here and in `docs/RESOURCES.md`.
- `ZEAL/zealgt_prod`, `ZEAL/zealgt_prod_parv` and `nf_work/zealgt_prod_rest_stub` on the user's cleanup list.
