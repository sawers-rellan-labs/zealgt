# Run plan: union markers within each taxon, then ancestry, whole genome

DRAFT, 2026-11-15. Submitted after Milestone 10 (`docs/milestones/10_union_markers.md`) merges.

## Why

User, 2026-11-15: "I think I'll do the unipon for now"; "what I do not like is that thatr does not seem to be a nextflow
run". Row 2's method (huehuetenangensis) for every taxon, as a pipeline run.

## Scope

Two runs, nothing else rerun or resumed: `--step markers` on run 1367152's outputs (`ZEAL/variant_calling/`, read only),
then `--step ancestry` on its sheet. chr1-chr10, 95 donors, `hpc_prod`.

## Inputs

- `--input /rsstu/users/r/rrellan/BZea/ZEAL/variant_calling/samplesheets/samplesheet.counts.csv` (run 1367152, 950 rows).
- `--crams`: run 1367152's CRAM sheet (`docs/runs/variant_calling_production/samplesheet.csv`, PR #68).
- `--known_sites /rsstu/users/r/rrellan/BZea/ZEAL/reference/wideseq_sites_biallelic_snps.vcf.gz`.

## File quota

`/share/maize` group, 2026-11-15: 922,245 of 1,000,000 files; ~78k free.

- Markers run (mine): 2 tasks per donor x chromosome + 1 per taxon x chromosome = 1,950 tasks, ~45k files at ~23 per
  task (run 1367152).
- Ancestry run: ~1,900 tasks, ~44k files.
- `hpc_prod` has `cleanup = true`: the markers run's `work/` is deleted on success, before ancestry starts. Peak ~45k.
- If the group has under ~50k free at submission, the markers run is split by taxon (the union is per taxon, so the
  results are the same).

## Runs

Checkout `ZEAL/zealgt_prod` at a tag of `dev` after the merge; head jobs `hpc_prod`, 16 GB.

1. Setup check at the tag (`scripts/run_hazel_tests.sbatch`).
2. One submission: markers, then ancestry `afterok`.

## Estimates (mine)

- From row 2: recount 1-4 min, union count 1-2.5 min per donor x chromosome, <= 3 GB; mexicana's union is larger.
- CPU-h ~100. Wall ~1 h markers, ~1-2 h ancestry (`CALL_ANCESTRY` has no arrays: 950 jobs at 20/min is ~50 min of
  submitting). ~2-3 h in all.

## Checks after the runs

1. 950 rows in the markers sheet; every donor x chromosome with markers > 0.
2. Huehuetenangensis equals row 2: markers, union size, CO and INT blocks per line (63.2, 22.3).
3. Time and memory into `docs/RESOURCES.md`.

## Judging (the user's criteria, against SNP50K)

Per taxon: CO and INT blocks per line, genotype classes against BC2S2, the QTL scans (family covariate).

## Attempts

1. 2026-11-15 19:12, commit `67bf153` (tag `markers-genome-20261115` plus this run's params), checkout
   `ZEAL/zealgt_prod`. Group files 922,286 of 1,000,000: one markers run. Counts sheet check: 950 rows, 95 donors, 10
   regions, every path present. Setup check job 1915167 passed (config, inspect, 5 process stubs). Head jobs: markers
   1915482 (launch `nf_work/union_markers_genome`), ancestry 1915483 afterok (launch `nf_work/union_markers_ancestry`);
   params `docs/runs/union_markers_genome/params_{markers,ancestry}.yaml`, `run.config`.
   **Stopped** at 19:34 (`scancel --signal=INT --batch 1915482`; ancestry 1915483 cancelled; 15 leftover task arrays
   cancelled by the IDs in `.nextflow.log`): the group passed the 950k stop line (958,441 at 19:33, 966,370 after the
   stop; frodrig4 43,390 -> 86,802). 830 of 950 `RECOUNT_LINES` submitted, 433 completed; `work/` held 39,269 files at
   ~769 tasks: ~51 files per task, not the ~23 of run 1367152 (job arrays). At that rate the markers run is ~100k files
   and ancestry another ~100k: neither fits the ~34k now free. Not resumed (user's decision).
2. 2026-11-15 20:10, commit `d34c08c` (`process.scratch = true`; user, after deleting attempt 1's `work/`), fresh. Setup
   check 1917230 passed. Markers 1917377, ancestry 1917378 afterok. Early check at 79 finished tasks: 11.4 files per task
   (60 task dirs). **Failed** at 20:40 after 1,322 of ~1,950 markers tasks succeeded (0 failed): Nextflow threw
   `java.util.ConcurrentModificationException` in `TaskArrayCollector.createTaskArray` ->
   `BashWrapperBuilder.createContainerBuilder` while submitting a `COUNT_TAXON_UNION` array (Nextflow internals, no task
   error); Slurm cancelled ancestry. 13 orphaned task arrays cancelled by the IDs in `.nextflow.log`. Group 943,629 files
   after the failure; `work/` kept for `-resume`. Not resumed: the ~628 tasks left at ~11.4 files each end near 950.8k,
   over the 950,000 stop line.
3. 2026-11-15 21:05, commit `d34c08c`, markers `-resume` from attempt 2's launch directory (`work/` 21,002 files kept),
   after the user's cleanup (group 936,227 files) and new stop line (user, 2026-11-15: "change ethe limit to 975k").
   Markers 1920150, ancestry 1920151 afterok.
