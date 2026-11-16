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
   Markers 1920150, ancestry 1920151 afterok. **Succeeded**: markers 21:06-21:36 (628 tasks run, the rest cached), ancestry
   21:37-00:38; group peak 963,284 files, 936,864 after cleanup. Outputs `ZEAL/union_markers/` (`markers/`, `ancestry/`,
   `samplesheets/samplesheet.counts.markers.csv`).

## Results

Checks (`agent/` scripts, bugs not accuracy):

1. The markers sheet has 950 rows, one per donor x chromosome; no donor x chromosome has 0 kept markers.
2. Huehuetenangensis equals row 2 (jobs 1855319-1856527): all 20 marker-count rows at every filter, the 4,466 segments,
   CO 63.2 and INT blocks 22.3 per line on the same 61 lines (0 lines differ).
3. No line dropped by ancestry.

| taxon             | donors | markers per donor at start (median) | kept markers per donor (median) | lines | CO per line (mean) | INT blocks per line (mean) |
| ----------------- | ------ | ----------------------------------- | ------------------------------- | ----- | ------------------ | -------------------------- |
| mexicana          | 42     | 1,464,234                           | 87,965                          | 715   | 60.6               | 18.4                       |
| parviglumis       | 40     | 1,356,064                           | 58,693                          | 601   | 64.1               | 18.6                       |
| diploperennis     | 6      | 1,419,232                           | 24,829                          | 253   | 52.5               | 20.5                       |
| luxurians         | 5      | 1,333,147                           | 66,608                          | 119   | 62.2               | 24.6                       |
| huehuetenangensis | 2      | 1,852,254                           | 56,752                          | 61    | 63.2               | 22.3                       |

Markers per donor summed over chr1-chr10; CO = state changes along each chromosome (same state merged across missing
gaps), INT blocks = runs of HET or ALT, summed over chr1-chr10 per line (lines with all ten chromosomes). Time and
memory: `docs/RESOURCES.md`, "MARKERS and ANCESTRY genome-wide".

## Informative sites (mexicana, parviglumis)

### Why

User, 2026-11-16: "let's start with the informatibve as own in close taxa and add gapfilled in the divergent taxa";
"yes reuse the segments for the divergent taxa". Diploperennis, luxurians and huehuetenangensis are not rerun: their
informative set is the union, done above.

### Inputs

- Own markers per donor x chromosome (82 Zx/Zv donors, chr1-chr10, 820): the taxon union markers
  (`ZEAL/union_markers/markers/counts/<donor>/<chr>/<taxon>.<chr>.union_markers.vcf`) whose POS, REF and ALT are in
  the donor's `union_alt.vcf` of run 1367152 (`ZEAL/variant_calling/variant_calling/counts/<donor>/<chr>/`).
  Their number equals `depth_mq_wideseq_maf` of the union run's marker counts.
- Counts: the donor's union count VCF kept at those positions (its records carry ALT `.` where no line has an ALT
  read, so positions, not alleles).
- Written by a Slurm array outside the pipeline (bcftools 1.23.1, the nf-core `bcftools/view` image; no new pileup) to
  `ZEAL/informative_markers/counts/<donor>/<chr>/` (`<donor>.<chr>.own_markers.vcf`, `<donor>.<chr>.counts.vcf.gz`
  and `.tbi`).
- Sheet `ZEAL/informative_markers/samplesheets/samplesheet.counts.informative.csv`: the union sheet's 820 Zx/Zv rows,
  `counts` and `markers` pointing to the files above, `union` unchanged.

### Run

`--step ancestry`, `hpc_prod`, checkout `ZEAL/zealgt_prod` at `d34c08c` plus run-plan commits (docs only), params
`docs/runs/union_markers_genome/params_informative.yaml`, `run.config`; launch
`/share/maize/frodrig4/nf_work/informative_ancestry`; outputs `ZEAL/informative_markers/`. Expected 820 RTIGER fits
(one per donor x chromosome), 10 grids.

File quota: group stop line 975k (user, 2026-11-15).

### Attempts

Own sites: Slurm jobs 1929021 (task 1) and 1929022 (tasks 2-82), 2026-11-16 08:07-08:15, ~25 s per donor. Own markers
equal `depth_mq_wideseq_maf` on all 820 donor x chromosome pairs; 6,076,346 own markers, 5,998,782 of them with a
count record. Sheet: 820 rows, every path present.

1. 2026-11-16 08:16, commit `155e7ec`, checkout `ZEAL/zealgt_prod`. Setup check 1929156 passed (config, 31 containers,
   `CALL_ANCESTRY` and `ANCESTRY_GRID` stubs). Group files 914,737 at submission. Head job 1929182. **Succeeded**:
   workflow 08:16-10:19 (submission ~3 s per task), cleanup to 10:21, head job ended 10:35 (2 h 19 min); group peak seen
   933,254 files (polls every 5 min), 915,106 after cleanup.

### Results (informative sites)

- 820 RTIGER fits (`segments.bed`, `dropped_lines.tsv`, `line_checks.tsv`, `ancestry.vcf.gz`, `rqtl.csv`, 820 each),
  10 grids; outputs `ZEAL/informative_markers/ancestry/`.
- No line dropped by ancestry (0 rows in the 820 `dropped_lines.tsv`).
- Segments: mexicana 45,799 (union run 50,481), parviglumis 40,904 (union run 44,530).
