# Milestone 9f: efficiency before production

Five changes to `variant_calling` (and `ancestry`'s input) before the whole-population run
(`docs/runs/variant_calling_production.md`): stages move on per donor and region instead of waiting for the slowest
task anywhere, CRISP asks for the memory it uses, each donor's lines are counted in one task per region, and Slurm job
names can be read.

## Why (user, 2026-10-16)

"I think we need to do all fixes before sending the whole genome variant discovery"; "we need to debug all this changes
before sending the whole genome run". From the huehuetenangensis genome run (job 1343856, 1 h 41 min): chr2-chr10 waited
~30 min for chr1's last CRISP task; ~610 line-count tasks of seconds each made the end of the run. Job names in
`squeue`: "hideous".

## Changes

1. **Discovery barrier** (`subworkflows/local/cram_variant_discovery_crisp/main.nf:90`): the B73 control counts are
   grouped by `[donor, region]` with `groupTuple` without a size, so `POOLED_LIKELIHOOD_TIERS` waits for every CRISP
   task. Each key carries its size with `groupKey(key, n)`, n = the control pools (the kept-checks pool, if any, plus
   the controls), combined in from their channel.
2. **Union-stage barriers** (`subworkflows/local/sites_union_gapfill/main.nf`), the same fix at the five sizeless
   `groupTuple` calls: line 21 (tier-A sites per region, n = donors), 44 (BC1 counts per region and donor, n = the
   donor's BC1 pools), 45 (control counts per region, n = control pools), 59 (donor tables per region, n = donors), 74
   (donor alleles per region, n = donors). Sizes from the samplesheet channels.
3. **CRISP memory**: `hpc_dev` and `hpc_prod` from job 1343856's trace (peak per task; it asks 16 GB, run A's chr10 peak
   was 0.46 GB), with `docs/RESOURCES.md`.
4. **One count VCF per donor and region**: `COUNT_LINES` (nf-core `bcftools/mpileup`) counts all of a donor's lines in
   one task per region at its markers; the multi-sample VCF (one sample per line, named by the line CRAM's `SM`) is the
   published counts, `variant_calling/counts/<donor>/<region>/`. The counts sheet becomes one row per donor and region
   (`donor, region, counts, markers, union`; `sample_id` leaves `assets/schema_counts.json`); `bin/call_ancestry.R`
   reads the lines from the VCF's samples. Production: 17,670 count tasks and files -> 950.
5. **Short Slurm job names**: `executor.jobName` in `hpc_dev` and `hpc_prod` = the process's last name and its tag,
   e.g. `CRISP_Zh.0030_P4_chr3`; `tag "${meta.id}_${meta.region}"` for per-region processes in `conf/modules.config`.
   A job array keeps one name for all its tasks (`docs/running.md` says where to find each task).

## Choices this spec settles

- **Group sizes from the data** (user, 2026-10-16): `groupKey` with counts read from the samplesheet channels. Rejected:
  `size:` from a parameter (to keep right by hand for every sheet).
- **Multi-sample count VCF per donor and region as the published counts** (user, 2026-10-16). Rejected: splitting it
  back to one file per line (`bcftools +split`; keeps the sheet, but ~1,900 tasks and 17,670 files). Counts sheets
  published before 9f (per line) are not read by the new `ancestry`.
- **Job name from config** (`executor.jobName`, built in; the subworkflow keeps nf-core's input_operation_tool name).
  Rejected: renaming `CRAM_VARIANT_DISCOVERY_CRISP`.
- **CRISP log timestamps left out** (user, 2026-10-16): a PR to `vibansal/crisp` instead (todo), then the image's pinned
  commit moves. Rejected: `gawk` in the CRISP image.

## Not in this milestone

- The production run's decisions (run plan); the CRISP upstream PR; ancestry settings.

## Tests

1. **Tools** (laptop): mpileup of two lines in one call gives each line's records and `AD` equal to its single-line
   mpileup, with sample names = `sample_id`; `call_ancestry.R` on a multi-sample fixture gives the segments of the
   per-line files.
2. **Wiring** (laptop, stubs): two donors, two regions: tiers and union of one region start before the other region's
   CRISP ends (trace start times, a stub with a sleep); one counts row per donor and region; `ancestry` from that sheet,
   `chromosome` and `genome`; job names in the stubs' `.command.run`.
3. **Hazel setup**: `nextflow config`, `inspect`, the changed processes' stubs; `squeue` shows the short names.
4. **Review**: CodeRabbit on the commit range.
5. **Slice** (laptop, <= 15 min): the pilot slice through `variant_calling` and `ancestry`; union, donor alleles, each
   line's counts and the segments equal those of `dev`.
6. **Profile** (hazel, `hpc_dev`): huehuetenangensis chr1-chr10 again, cold (~1-1.5 h), then `ancestry` per chromosome
   and per genome; wall time against job 1343856 (1 h 41 min), task count, CRISP and `COUNT_LINES` peak memory; counts
   and segments equal job 1343856's and jobs 1343857-1343858's.

## Done when

- Tests 1-6 pass; `nf-core pipelines lint` has no failures.
- `docs/running.md` (job names, arrays), `docs/structure.md` and `README.md` (counts per donor), `docs/RESOURCES.md`
  updated; the metro maps keep their processes (none added or removed).
