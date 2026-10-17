# Run plan: variant calling for every donor, whole genome (production)

DRAFT, 2026-10-16. Rescopes `agent/ancestry_production_draft_20261006.md` (on hold since 2026-10-06), which ran
discovery and ancestry as one step; that draft stays as the record.

## Why

User, 2026-10-16: "now that I have decoupled variant discovery from ancestry, that plan should scope to variant
discovery". Milestone 9e split the step (`decisions.md` 2026-10-16): "the only thing that I need genome-wide are the
counts; the variant discovery can be done once and then we can fiddle with the HMM".

## Scope

- `--step variant_calling` (discovery, union, gap filling, each line's counts at its donor's markers), chr1-chr10,
  ending at the published counts and the counts sheet `samplesheets/<input>.counts.csv`.
- Out of scope: `--step ancestry` (per chromosome or genome fit, rigidity); later runs read this plan's counts sheets.
- What changed since the old draft: every ZEAL sample is aligned (waves 1-24, last 2026-10-16), so the alignment stage
  and its waves leave the plan; `--regions` runs every chromosome in one run.

## Inputs

- Samples (`meta/samples.csv`, not excluded, landraces out), each with a CRAM in `ZEAL/alignment/cram/`:

  | taxon             | donors | BC1 | lines |
  | ----------------- | ------ | --- | ----- |
  | mexicana          | 42     | 163 | 723   |
  | parviglumis       | 40     | 168 | 606   |
  | diploperennis     | 6      | 25  | 256   |
  | luxurians         | 5      | 19  | 121   |
  | huehuetenangensis | 2      | 9   | 61    |
  | total             | 95     | 384 | 1,767 |

  Plus the 44 B73 checks and `b73_controls.csv` (`B73_ERR3288215`).

- `--lowcopy_bed ZEAL/reference/lowcopy_chr1-10.bed`, `--check_sites bzeaseq/nilhmm/vcf/HQ_BZEA.vcf.gz`,
  `--regions chr1,...,chr10`.
- One input sheet with every donor (the union pools every donor in the run's sheet); written from `meta/samples.csv` and
  the CRAM folder, checked as job 1323750 did (paths present, each donor keeps a pool and a line over 0.05x).

## Runs

One `variant_calling` run over every donor (decision 1); it publishes the counts and one counts sheet.
Head job on the normal QOS, 16 GB, `NXF_OPTS="-Xms1g -Xmx12g"`; profile per decision 3. Commands written once the
decisions are made.

## Estimates (to redo from job 1343856)

- Method: the huehuetenangensis genome trace (job 1343856, 2 donors, 93 rows, chr1-chr10) per process, scaled per donor
  (discovery, union) and per line (counts), as `agent/hue_genome/estimate_genome.py` scaled run A's chr10 trace. The
  union steps (`COUNT_UNION`, `UNION_TIERS`, `FILL_DONOR_ALLELES`) also grow with the union's sites, which 95 donors
  multiply; scaled by the union sizes of the per-taxon chr10 runs.
- Until then, from run A's chr10 scaling (`huehue_genome.md`, ~11 CPU-h for 2 donors genome-wide, CRISP 5.4 of them):
  ~250 CPU-h of CRISP and ~500 CPU-h in all for 95 donors; ~3-6 h of CRISP at 80-40 tasks at a time; ~26,000
  tasks (the huehuetenangensis genome estimate, ~1,100 for 93 rows, scaled to 2,195). The old draft's ~450 CPU-h, ~35,000 tasks and 12-30 h included ancestry.
- `/share`: run A 3.9 GB of `work/` for chr10, 2 donors; ~1-1.5 TB for the population with `work/` kept (`hpc_dev`),
  much less with `cleanup = true` (`hpc_prod`).
- Published counts: ~77 GB plain, ~8 GB compressed (`-Oz`) for the whole population, on `/rsstu`.

## Order

1. Job 1343856's trace into the estimates above; `CRISP` and `COUNT_LINES` limits checked against chr1.
2. Milestone 9f (`docs/milestones/09f_efficiency_before_production.md`) merged, all its changes debugged before the run
   (user, 2026-10-16: "we need to debug all this changes before sending the whole genome run"): group sizes for the
   discovery and union barriers, CRISP memory, one count VCF per donor and region, short Slurm job names; its test 6
   reruns huehuetenangensis genome-wide on `hpc_dev`.
3. The sheet written and checked (every donor, luxurians included).
4. Hazel setup checks at the production tag; a stub of the run.
5. The run, one submission, unattended.

## Checks after the runs (bugs, not accuracy)

1. Every region of every run succeeded; per donor and chromosome: tier-A sites, union sites, union-ALT markers, lines
   counted.
2. chr10 against the per-taxon chr10 runs (`genotype_*_chr10.md`): union and donor alleles, and per donor the
   union-ALT markers its taxon discovered, kept or lost; differences are CRISP run-to-run variation (Milestone 9d), the
   union's other donors, or a bug.
3. The counts sheet has a row for every donor and region, its count VCF holding every line of the donor.
4. Time and peak memory per process into `docs/RESOURCES.md`.

## Decisions (user, 2026-10-16)

1. **Union design: one union of all donors**, one run. Gap filling's prior already comes from all
   other donors (Milestone 8, Eq. `eb`); on chr10, huehuetenangensis alone fragmented 2 samples that + parviglumis or +
   mexicana cleaned (notebook 06). With 94 other donors the prior `pi = (2 mu_d + k) / (2 + m)` nears `k / m`, so
   alleles of one taxon get a smaller prior than in a per-taxon union: fewer of their gaps filled, some own sites
   re-scored to missing. Check: chr10 of the all-donor union against the per-taxon chr10 runs (check 2). If own-taxon
   markers are lost, a subset of each donor's markers to sites its taxon discovered (`SRC=own` in some donor of the
   taxon, bcftools on `donor_alleles.vcf.gz`) before `--step ancestry`; not built.
2. **Luxurians in**: 5 donors, 19 BC1 pools, 121 lines.
3. **`hpc_dev` until production**: the debugging runs (9f's tests, this plan's stub) on `hpc_dev`; the production run on
   `hpc_prod` (frozen tag, `cleanup = true`, outputs on `/rsstu`).
4. **Ancestry afterwards (not this plan): 1 Mb rigidity over the all-donor union's markers**, expected denser per Mb than
   a per-taxon union's (huehuetenangensis alone needed 5 Mb and the genome fit to reach SNP50K-level fragmentation: median
   7.5 and 7 donor segments per line, jobs 1346167-1346168).

## Done when

- Every run succeeds; checks 1-4 in an Attempts section here; the counts sheets' paths in this plan.
