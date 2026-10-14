# Milestone 9b: problem families kept out of the union, still genotyped at it

Approved by the user, 2026-10-14 ("spec approved, go ahead with 9b").

`SITES_UNION_GAPFILL` builds the union from the tier-A sites of the donors not named in `--union_exclude`. Every donor,
named or not, is scored, gap-filled and genotyped at that union.

## Why

User, 2026-10-14:

- "Leave problematic families out of the union use only for genotyping".
- After the diploperennis run: "Definitly those families are suspicious", option A (out of the union, still genotyped),
  and "I do not understand how those steps are not standard yet".

Problem families carry a background of their own donor's alleles in lines SNP50K calls B73. Their discovery brings
sites into the union for every donor, and gap filling calls some of them ALT for clean donors (mexicana chr10: 2.8-4.9 %
of each clean donor's markers; `agent/genochr10/qc/union_site_qc.md`).

## What changes

1. **New parameter `union_exclude`**: a string of comma-separated donor IDs, default empty, in `nextflow_schema.json`.
2. **`SITES_UNION_GAPFILL`**: `BCFTOOLS_MERGE` and `UNION_SITE_COUNTS` take only the donors not in the list (a `filter`
   on `ch_tier_a` and on the donor table).
   - The union and K / R (own tier-A, ref gaps per site) then come from the kept donors only.
   - `COUNT_UNION`, `UNION_TIERS`, `FILL_DONOR_ALLELES`, `DONOR_ALLELES_MERGE` and ancestry still run for every donor.
3. **The list per run** comes from the problem-family screen, `agent/` scripts for now, and is written in the run plan.

## Choices this spec settles (yours to confirm)

- **A parameter, not a samplesheet column.**
  - A per-donor setting does not belong on every sample row.
  - A new column changes every sample's `meta`, so on `-resume` every task would rerun.
  - Rejected: a column `union` in the samplesheet.
- **K and R summed over the kept donors only.** An excluded donor's own sites would otherwise count as evidence at the
  union sites. Rejected: totals over all donors.
- **An excluded donor's own tier-A sites inside the union still count as its own** in its gap filling, unchanged.
- **The screen stays outside the pipeline in this milestone.** It needs SNP50K calls, which are not a pipeline input.
  Making it a pipeline step is a later milestone. Rejected: the screen in this milestone (it widens the scope; the
  deadline is today).

## Tests

1. **Wiring** (laptop, stubs, seconds): with `--union_exclude` naming one test donor, `BCFTOOLS_MERGE` gets one VCF
   fewer and `FILL_DONOR_ALLELES` runs for every donor. nf-test snapshots for both cases; channel-level DAG.
2. **Tool:** `fill_donor_alleles.py` totals on a three-donor fixture with one donor left out.
3. **Cluster:** a hazel stub with tasks in the head job (`docs/running.md`, "Stubs on hazel"), then the diploperennis run
   resumed from job 1270808's session with the flagged donors named. Discovery comes from the cache; the union onward
   reruns.

## Done when

- Tests 1-3 pass; `nf-core pipelines lint` has no failures.
- `docs/structure.md` (row `SITES_UNION_GAPFILL`) and both metro maps updated.
- `docs/decisions.md`: problem families out of the union, genotyped at it.
