# Run plan: alignment of the diploperennis donors, beside the mexicana waves

Draft, 2026-10-12; nothing submitted yet.

## Why

User, 2026-10-12: all diploperennis samples aligned by Wednesday 2026-10-14, in a second chain in parallel with the
mexicana waves (`alignment_mexicana35.md`), and before parviglumis.

## Inputs and outputs

- Samples: every `meta/samples.csv` row with taxon diploperennis, role `bc1_sample` or `nil`, not excluded: 281 samples
  (25 BC1 pools, 256 lines) of 6 donors, 16 libraries, none aligned yet; rows from the production demultiplexing sheets,
  unchanged.
- Raw FASTQ: 496 GB (bc1 320, bc2s3_batch1 177); largest sample 30 GB; two lines with 1.2 and 14 MB.
- Outputs: `--outdir /rsstu/users/r/rrellan/BZea/ZEAL/alignment`, as the mexicana waves: `cram/<sample_id>.cram`, `.crai`
  and CRAM QC; ~160 GB of CRAMs.

## Waves

`work/` peak measured on mexicana waves 01-06: 7.85-8.01 x raw (`/share` sampled every 10 min). Samples filled in sheet
order up to 2 TB of `work/` peak at 8.0 x raw; numbered from 10, so the per-sheet MultiQC folders
(`multiqc/alignment/<sheet>/`) do not collide with mexicana's 01-09:

| wave | samples | raw    | `work/` peak | estimate alone |
| ---- | ------- | ------ | ------------ | -------------- |
| 10   | 15      | 242 GB | ~1.9 TB      | ~3 h           |
| 11   | 255     | 249 GB | ~2.0 TB      | ~4 h           |
| 12   | 11      | 5 GB   | ~0.04 TB     | ~0.5 h         |

Estimates: mexicana waves 03-05 ran at 85-94 GB raw/h; wave 11's 255 samples add per-sample steps (CollectWgsMetrics
walks the whole genome whatever the depth). Alone ~7.5 h; beside the mexicana chain (until ~midnight 10-12) maybe slower,
see below.

## Settings

- As `alignment_mexicana35.md` (`hpc_prod`, `cleanup = true`, chain with `afterok`, normal QOS, `--no-requeue`, head job
  16 GB, `NXF_OPTS="-Xms1g -Xmx12g"`), except:
- Own checkout `ZEAL/zealgt_prod_dip` at tag `align-dip-20261012`; the mexicana chain's pending waves read
  `ZEAL/zealgt_prod`, which stays at its tag.
- Own launch folder `nf_work/zealgt_prod_dip` (`ZEALGT_LAUNCH`) with its `work/` inside (user, 2026-10-12): its own
  `.nextflow.log`, cache and `work/`; nothing of the mexicana run's `nf_work/zealgt_prod` is shared.
- Both runs write `pipeline_info/zealgt_software_mqc_versions.yml` in the same outdir (same tools, same content);
  traces and reports carry a start timestamp.
- Sheets `docs/runs/alignment_diploperennis/alignment_10.csv` to `_12.csv` (`agent/aligndip/write_wave_sheets.py`),
  submitted from `ZEAL/zealgt_prod_dip`:
  ```
  ZEALGT_LAUNCH=/share/maize/frodrig4/nf_work/zealgt_prod_dip MEM=16G NXF_OPTS="-Xms1g -Xmx12g" WAVES=docs/runs/alignment_diploperennis bash scripts/submit_waves.sh alignment 10
  ```
- Stub: `docs/runs/alignment_diploperennis_stub/alignment_10.csv` (one line), the same command with
  `WAVES=docs/runs/alignment_diploperennis_stub OUTDIR=/rsstu/users/r/rrellan/BZea/ZEAL/alignment_stub` and `-stub`.

## Two chains at once

- Both run as frodrig4 on QOS `normal`: 1,024 running CPUs and 1,000 submitted jobs per user. `executor.queueSize = 40`
  per run, so 80 jobs at most; at 16 CPUs per `MINIBWA_MAP` two runs mapping at once can pass 1,024 CPUs, and tasks
  past it queue (slower), they do not fail.
- `/share`: both chains' waves together peak at ~4 TB. The session stops and asks if `frodrig4`'s `/share` usage passes
  6 TB, or if the group's headroom falls below 2 TB.

## Supervision

- As `alignment_mexicana35.md`: a background poller per chain (`sacct`, `/share` usage, ssh and stat timings), plus
  running CPUs per user while both chains overlap. Failed wave: `scancel` the pending ones, read `.command.err`,
  resubmit from that wave with `RESUME=<session id>` and the same `ZEALGT_LAUNCH`.
- Known: the 1.2 and 14 MB lines are the smallest yet (the pilot aligned 9.3 MB; mexicana's 1.5-19 MB lines are in its
  wave 08).

## Done when

- Every wave succeeded and `cleanup` emptied its `work/`; 281 CRAMs with index and CollectWgsMetrics in
  `ZEAL/alignment/cram/`; time, `work/` peak factor and CPU peak per wave here and in `docs/RESOURCES.md`.
- `ZEAL/zealgt_prod_dip` and `nf_work/zealgt_prod_dip` on the user's cleanup list.
