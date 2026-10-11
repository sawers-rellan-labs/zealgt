# Milestone 9a: RTIGER at the donor's union-ALT sites, with a per-line dosage check

Approved by the user, 2026-10-11 ("spec approved, go ahead").

Change to `CRAM_ANCESTRY_RTIGER` (Milestone 9): each donor's markers are the union sites gap filling called ALT for it,
not its own tier-A sites; `CALL_ANCESTRY` also writes the per-line checks of the curve rule.

## Why

User, 2026-10-08: own tier-A markers can't be believed where no line carries an introgression; they fail for families
whose lines don't cover the chromosome. Tested in `agent/` scripts on the eight chr10 donors (2026-10-08 to 10-11):
Zx.0090_P2 went from 18 to 1.5 donor segments per line (SNP50K 2.5); segment dosage REF 1-2 %, HET 38-45 %, ALT 79-87 %;
class shares over 249 lines HET 7.6 %, ALT 5.5 % (SNP50K 10.2 / 0.9). The user's curve rule (`docs/decisions.md`,
2026-10-11) is checked on these calls.

## What changes

1. **Markers per donor** (new, two nf-core `bcftools/view` calls per donor and chromosome, on
   `<chr>.donor_alleles.vcf.gz` from `SITES_UNION_GAPFILL`):
   - `DONOR_SUBSET`: `-s <donor>`;
   - `DONOR_ALT_SITES`: `-i 'GT="1"' -G`, sites only. A separate call: with `-s` in the same call, `-i` tests every
     sample (found in the agent test).
2. **`COUNT_LINES`**: each line at its donor's union-ALT sites (was: tier-A). Settings unchanged.
3. **`CALL_ANCESTRY`**: markers = the union-ALT sites; rigidity 0.5 % of them (as tested; chr10 48-104 k markers, so r
   = 242-522). `bin/call_ancestry.R`: `--tier-a` renamed `--markers`; new output `<donor>.<chr>.line_checks.tsv`, from
   the counts and segments it already holds: `line, n_donor_segments, donor_bp, ref/het/alt_reads,
ref/het/alt_alt_pct` (as `agent/union8/union_markers/check_lines.py`).
4. `ANCESTRY_GRID`, `ANCESTRY_VCF_INDEX`: unchanged.

`CRAM_ANCESTRY_RTIGER` takes `donor_alleles` instead of `tier_a`, so ancestry now waits for gap filling.

## Inputs and outputs

- Inputs: `SITES_UNION_GAPFILL.out.donor_alleles` (`[meta, vcf.gz, tbi]`, per chromosome), the CRAMs, as before.
- Outputs (`genotype/ancestry/`): as Milestone 9, plus `<donor>.<chr>.line_checks.tsv`. Segments change because the
  markers change.

## Choices this spec settles (yours to confirm)

- **Markers = union sites called ALT for the donor, own or gap.** Rejected: own tier-A only (the reason above); union own
  sites only (the gap-filled sites cover chromosomes the donor's own discovery misses).
- **Two nf-core `bcftools/view` calls**, not a custom script. Rejected: one view with `-s` and `-i` together (tests all
  samples); a script (bcftools does it).
- **Line checks written by `CALL_ANCESTRY`**, which already holds the counts and segments. Rejected: a separate process
  and script (reads every line's counts a second time).
- **Line checks as values, no pass/fail and no coverage per donor in the pipeline.** The curve rule's thresholds and the
  coverage (check 3) are applied downstream (notebook 03). Rejected: flags in the pipeline (thresholds would become
  pipeline parameters for an analysis choice).
- **Filter 1 retired** (drop markers that read ALT in 2 or more lines REF there; user, 2026-10-11). Tested on the eight
  chr10 donors (`agent/union8/union_markers/filt1/before_after.tsv`): it dropped 2-6.5 % of markers and changed little.
  - ALT segments still stop at 81-92 % ALT, so the ceiling does not come from these markers.
  - Class shares over 249 lines: HET 7.55 / ALT 5.46 % before, 7.47 / 5.53 % after.
  - The six curve donors are the same.
  - Its fixed two-line cut drops proportionally more markers in large families, where chance hits pass it.

  Rejected: keeping it as a step that changes nothing the checks measure.

## Not in this milestone

- Joint genotyping (step 2 of the supplement): parked by the user.
- Unions per taxon (open: measure what parviglumis sites add to mexicana gap filling once parviglumis donors are
  aligned).
- The curve itself and the 43-donor run (`docs/runs/`).

## Tests

1. **Tool** (laptop): `call_ancestry.R --markers` on the existing fixtures (`tests/bin/test_ancestry_tools.R`); the line
   checks hand-checked on a two-line fixture; the two views on a three-donor `donor_alleles` fixture give exactly the
   sites with `GT=1` for the chosen donor.
2. **Wiring** (laptop, stubs, seconds): two views and one `CALL_ANCESTRY` per donor and chromosome, `COUNT_LINES` per
   line; `CRAM_ANCESTRY_RTIGER` after `SITES_UNION_GAPFILL`; the channel-level DAG; nf-test snapshots updated.
3. **Slice** (laptop, real data, <= 15 min): the two pilot donors, chr10:1-5 Mb.
4. **Cluster** (hazel, `hpc_dev`, < 30 min): `-stub-run`, then chr10 with the eight donors resumed from attempt 3's
   session (only the views, `COUNT_LINES` and later rerun). Markers per donor equal the agent test's
   (`n_markers_clean.tsv`, and 69,103 / 56,582 for Zx.0160_P2 / Zx.0470_P2); segments equal `out2/` (same seed); line
   checks equal `lines_check.tsv`; time and memory per process.

## Done when

- Tests 1-4 pass; `nf-core pipelines lint` has no failures.
- Resources in config and `docs/RESOURCES.md` (agent test: line counts <= 12 min / 479 MB per line, RTIGER <= 1.1 GB per
  donor).
- `docs/structure.md` row `CRAM_ANCESTRY_RTIGER` and both metro maps show the views and the new input.
- `docs/decisions.md`: the marker rule and the choices above, once confirmed.
