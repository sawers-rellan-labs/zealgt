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

## Estimates

Measured on chr10 with 88 donors (diploperennis, parviglumis, mexicana; `genotype_diplo_parviglumis_mexicana_chr10`,
2026-10-16, trace `execution_trace_2026-10-16_12-30-36.txt`; 727,756 union sites, 3,199 tasks, 28.2 CPU-h with
ancestry), scaled to 95 donors and chr1-chr10. Genome / chr10 is 14.1 by low-copy Mb and 17.1 by union sites (the
huehuetenangensis genome run, job 1343856: 1,168,623 vs 68,177); ~15 below.

| process (chr10, 88 donors)                 | tasks  | longest      | CPU-h | peak RSS | production (95 donors, genome)            |
| ------------------------------------------ | ------ | ------------ | ----- | -------- | ----------------------------------------- |
| `CRISP`                                    | 82     | 16.1 min     | 12.2  | 0.55 GB  | ~200 CPU-h; chr1 tasks ~35-45 min         |
| `COUNT_UNION`                              | 358    | 3.1 min      | 4.7   | 0.26 GB  | ~75 CPU-h                                 |
| `UNION_TIERS`                              | 88     | 2.5 min      | 2.6   | 1.80 GB  | chr1 ~4 GB (2.2 x chr10's sites): 8 GB    |
| `SAMTOOLS_MERGE`, `_ADDREPLACERG`          | 164    | 3.7 min      | 4.3   | 0.90 GB  | ~70 CPU-h                                 |
| `COUNT_LINES` (per line, pre-9f)           | 1,569  | 0.2 min      | 1.1   | 0.25 GB  | 950 tasks after 9f; memory from 9f test 6 |
| `FILL_DONOR_ALLELES`                       | 88     | 0.6 min      | 0.6   | 0.75 GB  | chr1 ~1.7 GB                              |
| `UNION_SITE_COUNTS`, `DONOR_ALLELES_MERGE` | 1 each | 3.1, 3.6 min | 0.1   | 0.72 GB  | chr1 ~1.6 GB, ~8 min                      |

- CPU: ~400-500 CPU-h; tasks ~18,000 (Milestone 9f: one `COUNT_LINES` per donor and region; ~41,000 without).
- Wall: ~4-6 h on `hpc_prod` (`queueSize` 80), ~8-10 h on `hpc_dev` (40); the longest task CRISP on chr1. Milestone 9f
  lets chr2-chr10 go on while chr1's CRISP runs (huehuetenangensis genome: 1 h 41 min before, ~58 min after).
- Memory: `UNION_TIERS` to 8 GB before the run (4 GB now; chr1 ~4 GB). `COUNT_LINES` in its 9f form (a donor's lines
  in one task, up to 64 lines) from 9f test 6 (35 lines) before the run.
- `/share`: `work/` of 9f test 6 to measure; with `cleanup = true` (`hpc_prod`) a run keeps only what is in flight.
- Published counts: ~77 GB plain, ~8 GB compressed (`-Oz`) for the whole population, on `/rsstu`.

## Order

1. Limits from the estimates above: `UNION_TIERS` 8 GB; `COUNT_LINES` from 9f test 6, scaled to 64 lines.
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
