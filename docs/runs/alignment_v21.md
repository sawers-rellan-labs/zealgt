# Run plan: alignment of BC2S3 batch 2, plate V21

## Why

User, 2026-10-05: align about 100 batch-2 samples after the pilot "so I can have the coverage comparison at the pre
genotype state", a whole-genome estimate like the "WGS" dataset of the missing-data model (CollectWgsMetrics), now
for both BC2S3 batches through the same pipeline. Plate V21 (user).

## Inputs and outputs

- Input: `docs/runs/alignment_v21/samplesheet.csv`, 96 rows: the 8 libraries V21A-V21H (12 samples each) from the
  production demultiplexing sheet `ZEAL/demultiplex/samplesheets/demultiplex_06.csv`, unchanged.
- Reads (fqtk metrics): 4.0-16.6 M pairs per sample, median 9.4 M; one 50 M-pair chunk each. Expected MEAN_COVERAGE
  median about 0.68x (0.072x per M pairs, calibrated on 7 batch-1 samples of job 1100086).
- Outputs: `--outdir /rsstu/users/r/rrellan/BZea/ZEAL/alignment`, next to the pilot's: `cram/<sample_id>.cram` +
  `.crai` and CRAM QC (CollectWgsMetrics, samtools stats, mosdepth). Production CRAMs: same code as the pilot.

## Settings

- As `alignment_pilot.md`: `hpc_prod`, worktree `ZEAL/zealgt_prod` at tag `align-pilot-20261005`, launch directory
  `nf_work/zealgt_prod` after the pilot has ended, `cleanup = true`, first attempt without `-resume`.
- `queueSize` 40 unchanged (user). Estimate about 2 h (96 samples x ~35 min of tasks / 40 at once).
- Head job on `compute` / normal, `--time=1-00:00:00`, `--mem` from the pilot's sacct peak.
- The sheet is copied to `/share/maize/frodrig4/nf_work/alignment_v21/` for the run (the tag predates it).

## Done when

- The run succeeded and `cleanup` emptied its `work/`.
- 96 CRAMs with CollectWgsMetrics in `ZEAL/alignment/cram/`; MEAN_COVERAGE per sample in the run's report.
