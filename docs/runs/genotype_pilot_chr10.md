# Run plan: GENOTYPE variant discovery, pilot donors, whole chr10

## Why

User, 2026-10-04: zealbc1 is a comparison, not a target; GENOTYPE's outputs should be close to zealbc1's, not
identical (`docs/decisions.md`). The 20 Mb runs of Milestone 7 checked for bugs only; this run checks accuracy, on the
whole chromosome zealbc1 ran (handover 2026-10-05).

## Inputs and outputs

- Input: `docs/runs/genotype_pilot_chr10/samplesheet.csv`, 106 rows, the pilot alignment's CRAMs
  (`ZEAL/alignment/cram/`, `docs/runs/alignment_pilot.md`), roles from `meta/samples.csv`, no row excluded:
  - Zx.0540_P3: 5 BC1 pools, 40 lines; Zx.0570_P2: 5 BC1 pools, 44 lines;
  - the 12 batch-1 B73 checks.
  - Written by `agent/genotype_pilot/write_sheets.py`.
- `--b73_controls docs/runs/genotype_pilot_chr10/b73_controls.csv`: `B73_ERR3288215`.
- `--lowcopy_bed ZEAL/reference/lowcopy_chr10.bed` (8,084 ranges, sha256 `25b5a8e9…` in the `.sha256` next to it;
  recipe `agent/panel_test/compare_lowcopy_bed.sbatch`, decision 2026-10-04).
- `--check_sites /rsstu/users/r/rrellan/BZea/bzeaseq/nilhmm/vcf/HQ_BZEA.vcf.gz`, `--region chr10`; the other
  parameters at their defaults (`--max_check_alt_rate 0.01`, `--min_mean_coverage 0.05`).
- Outputs, `--outdir /share/maize/frodrig4/nf_work/zealgt_dev/genotype_pilot_chr10/results`:
  `genotype/discovery/` with per donor `<donor>.chr10.vcf.gz` + `.tbi` and `<donor>.chr10.sites.tsv.gz`, and
  `b73_checks.tsv`; `pipeline_info/`.

## Settings

- `hpc_dev` (genotyping is development): launch directory `nf_work/zealgt_dev`, `work/` kept, outputs hard-linked on
  `/share`. The next milestones (union, ancestry) read these outputs within the 30-day purge, and the run can be repeated.
- Code: `dev` at the merge of this plan, checkout `ZEAL/zealgt` (pulled after the merge).
- Head job: default of `scripts/submit_head_job.sbatch` (short QOS, 2 h, 8 GB); tasks with the `hpc_dev`
  placeholders (CRISP 1 cpu, 16 GB, 2 h).
- First attempt without `-resume`; recovery with `-resume <session id>`.
- Command (from `ZEAL/zealgt`):

```
sbatch scripts/submit_head_job.sbatch hpc_dev --step genotype \
  --input docs/runs/genotype_pilot_chr10/samplesheet.csv \
  --b73_controls docs/runs/genotype_pilot_chr10/b73_controls.csv \
  --lowcopy_bed /rsstu/users/r/rrellan/BZea/ZEAL/reference/lowcopy_chr10.bed \
  --check_sites /rsstu/users/r/rrellan/BZea/bzeaseq/nilhmm/vcf/HQ_BZEA.vcf.gz \
  --region chr10 --outdir /share/maize/frodrig4/nf_work/zealgt_dev/genotype_pilot_chr10/results
```

## Size (estimates from the 20 Mb run, `docs/RESOURCES.md`, job 1101952)

- chr10 is 152 Mb, 7.6x the 20 Mb window. CRISP there took 45 s for 2 pools and the witness; for 5 pools and the
  witness, about 45 s x 7.6 x 2 = 12 min per donor, 1 cpu (CRISP is single-threaded), under 1 GB. Within the 2 h limit
  and the 30 min per process budget.
- `SAMTOOLS_MERGE` of 40-44 line CRAMs at about 0.3x on chr10, and ERR3288215 (13.3x) on chr10: minutes each.
- `CHECK_COUNTS`: 12 checks genome-wide at the SNP50K sites, about 30 s each.
- Wall time about 30-45 min; `/share` under 10 GB.

## Expected

- Coverage filter drops PN6_SID484 (Zx.0540_P3, 0.003x) and PN8_SID736 (Zx.0570_P2, 0.011x).
- B73 check filter drops PN5_SID468 and PN3_SID236 (2.65 % and 1.87 % ALT in job 1101952) and keeps the other 10.
- Two discovery tasks, one per donor.

## Comparison with zealbc1 (after the run)

- Reference: `ZEAL/results/bench_zx0540_chr10/step4/Zx.0540_P3.sites.tsv.gz`, the same 5 BC1 pools, 56,665 rows:
  tier A 40,941, B 10,818, C 3,002, ref 213, none 1,691.
- Join on `chrom, pos, ref, alt`; report:
  - per tier, the sites in both, in ours only and in zealbc1's only; tier A first;
  - on the sites in both, the tier cross-table and the LLR correlation;
  - per BC1 pool, the ratio of our depth to zealbc1's on shared sites (aligner and `--mbq 20` vs 10).
- Known reasons for differences: the alignment (zealgt's own split alignment), `--mbq 20`, the low-copy BED (8,084 vs
  8,095 ranges), the witness lines, the automatic B73 check filter.
- Script in `agent/genotype_pilot/`; numbers in this file's report. Whether they are close is the user's call.

## Before the run

1. This plan with the two sheets merged into `dev`; `ZEAL/zealgt` pulled.
2. The user's OK on this plan.

## Done when

- The run succeeded and wrote both donors' VCF and site table and `b73_checks.tsv`.
- Measured resources in `docs/RESOURCES.md`, whole-chromosome values in `conf/hpc_dev.config`.
- The comparison is in this file; the user has judged it.
- Then on the user's removal list: the `/share` copy of the low-copy BED and, once judged, zealbc1's
  `bench_zx0540_chr10`.

## Attempts
