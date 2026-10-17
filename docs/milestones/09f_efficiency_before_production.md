# Milestone 9f: efficiency before production

Six changes to `variant_calling` before the whole-population run (`docs/runs/variant_calling_production.md`): stages
move on per donor and region instead of waiting for the slowest task anywhere, CRISP asks for the memory it uses, line
counts run as few tasks, and Slurm names and CRISP's log can be read while a run goes.

## Why (user, 2026-10-16)

"I think we need to do all fixes before sending the whole genome variant discovery." From the huehuetenangensis genome
run (job 1343856, 1 h 41 min): chr2-chr10 waited ~30 min for chr1's last CRISP task; ~610 line-count tasks of seconds
each made the end of the run. Job names in `squeue`: "hideous". CRISP's progress lines: "that log need a timestamp".

## Changes

1. **Discovery barrier** (`subworkflows/local/cram_variant_discovery_crisp/main.nf:90`): the B73 control counts are
   grouped by `[donor, region]` with `groupTuple` without a size, so `POOLED_LIKELIHOOD_TIERS` waits for every CRISP
   task. Each key carries its size with `groupKey(key, n)`, n = the control pools (the kept-checks pool, if any, plus
   the controls), combined in from their channel.
2. **Union-stage barriers** (`subworkflows/local/sites_union_gapfill/main.nf`), the same fix at the five sizeless
   `groupTuple` calls: line 21 (tier-A sites per region, n = donors), 44 (BC1 counts per region and donor, n = the
   donor's BC1 pools), 45 (control counts per region, n = control pools), 59 (donor tables per region, n = donors), 74
   (donor alleles per region, n = donors). Counts from the samplesheet channels.
3. **CRISP memory**: `hpc_dev` and `hpc_prod` from job 1343856's trace (peak per task; it asks 16 GB, run A's chr10 peak
   was 0.46 GB), with `docs/RESOURCES.md`.
4. **Line counts batched**: `COUNT_LINES` (nf-core `bcftools/mpileup`) counts all of a donor's lines in one task per
   region (one multi-sample VCF), then nf-core `bcftools/pluginsplit` (`bcftools +split`) writes one count VCF per line, so the counts sheet and `ancestry` stay as they are. Production: 17,670 tasks
   -> ~1,900 (95 donors x 10 regions, twice).
5. **Short Slurm job names**: `executor.jobName` in `hpc_dev` and `hpc_prod` = the process's last name and its tag,
   e.g. `CRISP_Zh.0030_P4_chr3`; `tag "${meta.id}_${meta.region}"` for per-region processes in `conf/modules.config`.
   A job array keeps one name for all its tasks (`docs/running.md` says where to find each task).
6. **Timestamps on CRISP's log**: the module puts `YYYY-MM-DD HH:MM:SS` before each line of CRISP's stderr,
   line-buffered, by `gawk` (`strftime`, `fflush`), added to the CRISP image with a pinned version (CLAUDE.md
   "Containers"); image rebuilt by `build_images.yml`. CRISP itself unchanged; the upstream PR is a separate todo.

## Choices this spec settles (yours to confirm)

- **`groupKey` with counts from the data**, not a fixed `size:` (the pool and donor numbers change per run). Rejected:
  `size:` from params (one more parameter to keep right by hand).
- **Split after a multi-sample mpileup** so the counts sheet keeps one file per line. Rejected: the multi-sample VCF as
  the published counts (changes the sheet and `call_ancestry.R`); Nextflow job arrays alone (already on; the cost is
  Slurm's ~1 min per scheduling round, not the submission).
- **Job name from config** (`executor.jobName`, built in). Rejected: renaming `CRAM_VARIANT_DISCOVERY_CRISP` (touches
  selectors and paths; can follow if the names still read badly).
- **`gawk` in the CRISP image** for the timestamps. Rejected: `ts` (moreutils, a larger package for one command);
  `mawk`'s `strftime` (not in every build).

## Not in this milestone

- Union design, luxurians, profile for production (the run plan's decisions); the CRISP upstream PR.

## Tests

1. **Tools** (laptop): `gawk` timestamps on a CRISP log from the image; mpileup of two lines then the split equals the
   two single-line mpileups (records and `AD`).
2. **Wiring** (laptop, stubs): two donors, two regions: tiers of one region start before the other region's CRISP ends
   (trace start times, a stub with a sleep); one count file per line in the sheet; job names in the stub's `.command.run`.
3. **Hazel setup**: `nextflow config`, `inspect`, the new and changed processes' stubs; `squeue` shows the short names.
4. **Review**: CodeRabbit on the commit range.
5. **Slice** (laptop, <= 15 min): the pilot slice through `variant_calling`; union, donor alleles and every line's
   counts equal those of `dev`.
6. **Profile** (hazel): huehuetenangensis chr1-chr10 again, cold (~1-1.5 h); wall time against job 1343856 (1 h 41
   min), task count, CRISP peak memory; its counts equal job 1343856's.

## Done when

- Tests 1-6 pass; outputs equal `dev`'s on the slice; `nf-core pipelines lint` has no failures.
- `docs/running.md` (job names, arrays), `docs/RESOURCES.md`, both metro maps (the split step) updated.
