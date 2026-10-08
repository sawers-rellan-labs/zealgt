# Milestone 8a: gap filling split into a per-site summary and one task per donor

Approved by the user, 2026-10-07 ("the 8a spec is approved").

## Why

User, 2026-10-06, on the union's size at all donors (projected 7-15 M sites genome-wide; four-donor test: chr10 union
170,729): "10 million sites remain too much yet"; "there is no way to just get the site list and then go over each donor
dataset to make the counts isn't it? at some point we'll need to load a 10M sites * 1800 samples"; "so we'll need
FILL_DONOR_ALLELES fixed after this test". User, 2026-10-07: "the only worthwhile modification is the breakup of the union
steps".

`FILL_DONOR_ALLELES` (Milestone 8) is one task per chromosome that reads every donor's union table and holds them all at
once. Measured on chr10 (union tests, `docs/runs/genotype_union_6donors_races_chr10.md`):

| Donors | Union sites | FILL_DONOR_ALLELES | UNION_TIERS (per donor) | COUNT_UNION (per pool, max) |
| ------ | ----------- | ------------------ | ----------------------- | --------------------------- |
| 2      | 70,210      | 5.2 s / 100 MB     | 16.6 s / 198 MB         | 37 s / 246 MB               |
| 4      | 170,729     | 15.5 s / 309 MB    | 33 s / 428 MB           | 42 s / 254 MB               |
| 6      | 178,300     | 24.4 s / 469 MB    | 41 s / 469 MB           | 45 s / 252 MB               |

`COUNT_UNION` and `UNION_TIERS` already run one task per pool or donor; only `FILL_DONOR_ALLELES` grows with donors x
sites. At 95 donors and 0.4-1 M chr10 sites (`docs/notebooks/03_union_rarefaction.qmd`) its one task would need tens of
GB per chromosome and run serially over all donors.

## What changes

Eq. 10 (math supplement Section 5.2) needs, for donor d at site s, only two counts over the _other_ donors and the donor's
own sharing rate:

- `k` = other donors with s among their own tier-A sites; `m` = `k` + other donors with s a gap scored tier `ref`;
- `mu_d` = the donor's tier-A over tier-A + ref among its own gaps (its whole chromosome).

Both counts are leave-one-out versions of two per-site totals over all donors, `K_s` (donors with s as an own tier-A
site) and `R_s` (donors with s a gap scored `ref`): `k = K_s - [s own in d]`, `m = k + R_s - [s a ref gap in d]`. So the
step splits into:

1. `UNION_SITE_COUNTS` (one task per chromosome): streams each donor's tier-A sites and union table, one donor at a time,
   and writes `K_s` and `R_s` per union site. Memory of order the union, not donors x union.
2. `FILL_DONOR_ALLELES` (one task per donor and chromosome): the donor's tier-A sites, its union table and the site
   counts in; `mu_d`, then Eq. 10 at every union site; out: a one-sample VCF (`GT`, `LLR`, `PRIOR`, `PALT`, `SRC`).
3. `BCFTOOLS_MERGE` (nf-core, as `DONOR_ALLELES_MERGE`): the per-donor VCFs into `<chr>.donor_alleles.vcf.gz` + `.tbi`,
   the same file Milestone 8 writes. Downstream (step 2, projection) unchanged.

`bin/fill_donor_alleles.py` gets two modes (site counts; one donor with the counts); the model code (prior, posterior,
calls, never-ALT flags, own sites never REF) is untouched. Values stay in `conf/modules.config`.

## Inputs and outputs

- Inputs: unchanged from Milestone 8 (`UNION_TIERS` tables, tier-A VCFs, the union VCF).
- New intermediate: `<chr>.site_counts.tsv.gz` (`chrom, pos, K, R`), per chromosome.
- Outputs: unchanged: `genotype/union/<chr>.union.vcf.gz`, `<chr>.donor_alleles.vcf.gz` (+ `.tbi`). Records, samples and
  FORMAT values identical to Milestone 8's.

## Choices this spec settles (yours to confirm)

- **Per-site totals with leave-one-out, not a donor x site matrix.** Rejected: keeping one task and streaming inside it
  (still serial over 95 donors); splitting by genomic chunk only (each chunk still holds all donors).
- **One task per donor, merged with nf-core `bcftools/merge`.** Rejected: one task per donor writing straight into a shared
  file (not possible in Nextflow); a custom merge script (bcftools does it).
- **`mu_d` stays per donor and whole chromosome** (it needs the donor's whole chromosome first), computed inside the
  donor's task. Rejected: computing it in the summary pass (would keep per-donor state there).
- **Same tool, two modes.** Rejected: two scripts (the model would be duplicated).

## Not in this milestone

- `COUNT_UNION` / `UNION_TIERS` (already per pool / per donor) and the union itself (`MARKER_UNION`).
- Union size options (per-taxon unions, thinning): `docs/notebooks/03_union_rarefaction.qmd`, user's decision.
- The discovery/veto review (`docs/notebooks/02_witness_veto.qmd`, `04_line_pool_denoiser.qmd`).

## Order with the planned run

Attempt 3 of the union test (`docs/runs/genotype_union_6donors_races_chr10.md`, eight donors, chr10) runs first, on the
current pipeline (`dev` ef72df1 on hazel; keep the hazel checkout there until it finishes). Its `<chr>.donor_alleles.vcf.gz`
is the reference for test 4 below, and its resources add the eight-donor row to the table above.

## Tests

1. **Tool** (laptop): both modes on the Milestone 8 fixtures; the two-step output equals the one-step output record by
   record (GT, LLR, PRIOR, PALT, SRC). `K_s`, `R_s` hand-checked on a three-donor fixture.
2. **Wiring** (laptop, stubs, seconds): `UNION_SITE_COUNTS` once per chromosome, `FILL_DONOR_ALLELES` once per donor and
   chromosome, one merge per chromosome; the channel-level DAG.
3. **Slice** (laptop, real data, <= 15 min): the two pilot donors, chr10:1-5 Mb; output identical to Milestone 8's on the
   same slice.
4. **Cluster** (hazel, `hpc_dev`, < 30 min): `-stub-run`, then chr10 with the eight donors of attempt 3 resumed from its
   session (only the new processes run); `donor_alleles.vcf.gz` identical to attempt 3's (`bcftools isec` / record diff);
   time and memory per process at eight donors.

## Done when

- Tests 1-4 pass, outputs identical to Milestone 8's; `nf-core pipelines lint` has no failures.
- Resources for the new processes in config and `docs/RESOURCES.md`.
- `docs/structure.md` row `SITES_UNION_GAPFILL` lists the new processes; both metro maps show them.
- The report gives the memory of the per-donor task against the old one-task memory at 2, 4, 6 and 8 donors.
