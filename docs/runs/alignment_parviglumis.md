# Run plan: alignment of the parviglumis donors, after the mexicana waves

Draft, 2026-10-12; nothing submitted yet.

## Why

User, 2026-10-12: align parviglumis after diploperennis (`alignment_diploperennis.md`), as a chain that starts when the
mexicana chain (`alignment_mexicana35.md`) ends, in its launch folder.

## Inputs and outputs

- Samples: every `meta/samples.csv` row with taxon parviglumis, role `bc1_sample` or `nil`, not excluded, without a CRAM
  in `ZEAL/alignment/cram/`: 685 samples (168 BC1 pools, 517 lines) of 40 donors (89 more have CRAMs); rows from the
  production demultiplexing sheets, unchanged.
- Raw FASTQ: 2,302 GB; largest sample 37 GB (`S_4E_6`; mexicana's largest was 34 GB); four lines with 2.4-9.2 MB.
- Outputs: `--outdir /rsstu/users/r/rrellan/BZea/ZEAL/alignment`, as the other chains: `cram/<sample_id>.cram`, `.crai`
  and CRAM QC; ~740 GB of CRAMs.

## Waves

Samples filled in sheet order up to 2 TB of `work/` peak at 8.0 x raw (measured on mexicana waves 01-06); numbered from
13, so the per-sheet MultiQC folders (`multiqc/alignment/<sheet>/`) do not collide with mexicana's 01-09 and
diploperennis's 10-12:

| wave | samples | BC1 pools | lines | raw    | `work/` peak | estimate |
| ---- | ------- | --------- | ----- | ------ | ------------ | -------- |
| 13   | 12      | 12        | 0     | 249 GB | ~2.0 TB      | ~3 h     |
| 14   | 12      | 12        | 0     | 236 GB | ~1.9 TB      | ~2.5 h   |
| 15   | 26      | 26        | 0     | 249 GB | ~2.0 TB      | ~3 h     |
| 16   | 33      | 33        | 0     | 243 GB | ~1.9 TB      | ~3 h     |
| 17   | 35      | 35        | 0     | 243 GB | ~1.9 TB      | ~3 h     |
| 18   | 24      | 24        | 0     | 243 GB | ~1.9 TB      | ~3 h     |
| 19   | 13      | 13        | 0     | 245 GB | ~2.0 TB      | ~3 h     |
| 20   | 118     | 13        | 105   | 249 GB | ~2.0 TB      | ~3.5 h   |
| 21   | 260     | 0         | 260   | 250 GB | ~2.0 TB      | ~4 h     |
| 22   | 152     | 0         | 152   | 95 GB  | ~0.8 TB      | ~2 h     |

Estimates: mexicana waves 03-05 ran at 85-94 GB raw/h; waves of many lines add per-sample steps (CollectWgsMetrics walks
the whole genome whatever the depth). All waves ~30 h; starting when mexicana ends (~23:30 10-12, range 23:00-01:30),
the chain ends ~05:30 Wednesday 10-14 (range ~03:00-10:00).

## Settings

- As `alignment_mexicana35.md` (`hpc_prod`, `cleanup = true`, chain with `afterok`, normal QOS, `--no-requeue`, head job
  16 GB, `NXF_OPTS="-Xms1g -Xmx12g"`), except:
- The first wave waits for mexicana's last wave (`AFTER=1200748`, `afterok`); if a mexicana wave fails, this chain stays
  pending and is resubmitted with it.
- Own checkout `ZEAL/zealgt_prod_parv` at its tag: the pending waves of the other chains read `ZEAL/zealgt_prod` and
  `ZEAL/zealgt_prod_dip`, which stay at their tags.
- Launch folder `nf_work/zealgt_prod`, as mexicana (default, no `ZEALGT_LAUNCH`): the runs follow each other, so the
  shared `.nextflow.log` rotation and cache are as between mexicana's own waves.
- Sheets `docs/runs/alignment_parviglumis/alignment_13.csv` to `_22.csv` (`agent/alignparv/write_wave_sheets.py`),
  submitted from `ZEAL/zealgt_prod_parv`:
  ```
  AFTER=1200748 MEM=16G NXF_OPTS="-Xms1g -Xmx12g" WAVES=docs/runs/alignment_parviglumis bash scripts/submit_waves.sh alignment 13
  ```
- Stub: `docs/runs/alignment_parviglumis_stub/alignment_13.csv` (one line), from the same checkout with
  `WAVES=docs/runs/alignment_parviglumis_stub OUTDIR=/rsstu/users/r/rrellan/BZea/ZEAL/alignment_stub`, `-stub`, no
  `AFTER`, and its own launch folder `ZEALGT_LAUNCH=/share/maize/frodrig4/nf_work/zealgt_prod_parv_stub` (mexicana runs in
  `nf_work/zealgt_prod` now).

## Supervision

- As `alignment_mexicana35.md`: a background poller (`sacct`, `/share` usage, running CPUs, ssh and stat timings). Failed
  wave: `scancel` the pending ones, read `.command.err`, resubmit from that wave with `RESUME=<session id>`.
- `/share`: the session stops and asks if `frodrig4`'s usage passes 6 TB (all chains together), or if the group's
  headroom falls below 2 TB. Beside diploperennis's last waves (until ~00:30) both chains peak at ~4 TB.
- Known: `MINIBWA_MAP` memory, 12.9 of 16 GB scaled to mexicana's 34 GB sample, is ~14 GB scaled to `S_4E_6` (37 GB,
  wave 19), under the 95 % kill line (15.2 GB). Lines of 2.4-9.2 MB (waves 21-22) are the smallest yet.

## Done when

- Every wave succeeded and `cleanup` emptied its `work/`; 685 CRAMs with index and CollectWgsMetrics in
  `ZEAL/alignment/cram/`; time and `work/` peak per wave here and in `docs/RESOURCES.md`.
- `ZEAL/zealgt_prod_parv` and `nf_work/zealgt_prod_parv_stub` on the user's cleanup list.
