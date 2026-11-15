# Run plan: union markers within each taxon, then ancestry, whole genome

DRAFT, 2026-11-15. Submitted after Milestone 10 (`docs/milestones/10_union_markers.md`) merges.

## Why

User, 2026-11-15: "I think I'll do the unipon for now"; "what I do not like is that thatr does not seem to be a nextflow
run". Row 2 (huehuetenangensis, sbatch scripts) as one pipeline method for every taxon.

## Scope

`--step markers` on run 1367152's counts sheet, then `--step ancestry` on each output sheet; chr1-chr10, all 95 donors;
`hpc_prod`. Run 1367152's outputs (`ZEAL/variant_calling/`) are read, not changed.

## Inputs

- `--input /rsstu/users/r/rrellan/BZea/ZEAL/variant_calling/samplesheets/samplesheet.counts.csv` (run 1367152, 950 rows),
  split by taxon into `docs/runs/union_markers_genome/counts_<group>.csv`.
- `--crams`: run 1367152's CRAM sheet (`docs/runs/variant_calling_production/samplesheet.csv`, on branch `runs-variant-calling-production`, not yet on
  `dev`), split the same way.
- `--known_sites /rsstu/users/r/rrellan/BZea/ZEAL/reference/wideseq_sites_biallelic_snps.vcf.gz`.

| run group | taxa                                        | donors | lines |
| --------- | ------------------------------------------- | ------ | ----- |
| A         | mexicana                                    | 42     | 722   |
| B         | parviglumis                                 | 40     | 606   |
| C         | diploperennis, luxurians, huehuetenangensis | 13     | 438   |

## Why three runs: the file quota

`/share/maize` group, 2026-11-15: 922,245 of 1,000,000 files (frodrig4 42,425). ~78k free.

- Tasks (mine, from the spec's processes): ~40 per donor (4 per donor x chromosome) + ~30 per taxon; ancestry ~20 per
  donor. ~23 files per task (run 1367152).
- Group A: ~1,710 tasks, ~39k files; B ~1,630, ~37k; C ~610, ~14k. Ancestry A ~840 tasks, ~19k files.
- `hpc_prod` has `cleanup = true`: each successful run deletes its `work/`, outputs copied to `/rsstu` first. Run one
  at a time, the peak stays ~40k files. One run for all taxa (~90k files) does not fit.
- The union is within each taxon, so splitting by taxon changes no result.

## Runs

Checkout `ZEAL/zealgt_prod` at a tag of `dev` after the merge. Head jobs `hpc_prod`, normal QOS, 16 GB. One chain, each
head job after the one before (`afterok`), so only one run's `work/` exists at a time:

1. Setup checks at the tag (`scripts/run_hazel_tests.sbatch`, this run's parameters).
2. markers A -> ancestry A -> markers B -> ancestry B -> markers C -> ancestry C.

## Estimates (mine)

- From row 2: recount 1-4 min, union count 1-2.5 min per donor x chromosome, <= 3 GB; mexicana's union is larger
  (42 donors), so its union counts take longer.
- CPU-h: ~950 x 2 counting tasks x ~3 min = ~95, plus small tasks.
- Wall: ~1 h per markers run, ~0.5-1 h per ancestry run (`CALL_ANCESTRY` has no arrays: 1,910 jobs at 20/min is ~1.6 h
  of submitting over all three). Chain ~4-6 h.
- Outputs on `/rsstu`: small (VCFs at markers only).

## Checks after the runs

1. Bugs: 950 rows in the three markers sheets together; every donor x chromosome with markers > 0 (`marker_counts.tsv`).
2. Group C's huehuetenangensis equals row 2 (markers, union size, CO and INT blocks per line: 63.2 and 22.3).
3. Time and memory into `docs/RESOURCES.md`.

## Judging (the user's criteria, against SNP50K)

Per taxon: segments (CO, INT blocks) per line, genotype classes against BC2S2, DTA and PH (diploperennis), the mexicana
traits; family covariate.

## Attempts

None yet.
