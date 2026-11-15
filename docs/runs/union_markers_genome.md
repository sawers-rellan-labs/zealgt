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

None yet.
