# Milestone 9e: VARIANT_CALLING and ANCESTRY split

The `genotype` step becomes two steps. `variant_calling` runs discovery, union and gap filling and counts every line at
its donor's markers; it stops at the published counts, as `alignment` stops at the CRAM. `ancestry` reads those counts
and runs RTIGER and the grid, with the fit unit an option: one fit per donor and chromosome (today) or one per donor over
all chromosomes. Steps: `demultiplex` -> `alignment` -> `variant_calling` -> `ancestry`.

## Why (user, 2026-10-16)

"The only thing that I need genome-wide are the counts. The variant discovery can be done once and then we can fiddle
with the HMM. Similar to the alignment part that we decided to separate." The SNP50K test (`agent/rigidity/chromfit/`)
showed a fit over all 10 chromosomes gives less fragmented calls; testing it on our markers needs genome-wide counts
without rerunning discovery for every HMM setting.

## Inputs

- `variant_calling`: as `genotype` today (`schema_cram.json`, `--b73_controls`, `--lowcopy_bed`, `--check_sites`,
  `--regions`).
- `ancestry`: the counts sheet a `variant_calling` run published (`schema_counts.json`, new), one row per line and
  region: `sample_id, donor, region, counts` (the line's count VCF), `markers` (the donor's marker VCF), `union` (the
  region's union VCF). `--genetic_map` moves to this step.
- New parameter `--ancestry_fit`: `chromosome` (default) or `genome`.

## Outputs

- `variant_calling/discovery/`, `variant_calling/union/` (today's `genotype/discovery/`, `genotype/union/`).
- `variant_calling/counts/<donor>/<region>/`: each line's count VCF and the donor's marker VCF; the counts sheet
  `samplesheets/<input name>.counts.csv` (workflow output `index`, as the FASTQ sheet of `demultiplex`).
- `ancestry/`: today's `genotype/ancestry/` (segments, dropped lines, line checks, grid, R/qtl, VCF). With `genome`, one
  segments, dropped and line-checks file per donor for all chromosomes; the grid stays per region.

## Processes

- `VARIANT_CALLING` (`workflows/variant_calling.nf`, today's `genotype.nf`): `CRAM_VARIANT_DISCOVERY_CRISP` ->
  `SITES_UNION_GAPFILL` -> `LINE_COUNTS` (new stage from today's first half of `CRAM_ANCESTRY_RTIGER`:
  `DONOR_SUBSET` -> `DONOR_ALT_SITES` -> `COUNT_LINES`). Modules unchanged.
- `ANCESTRY` (`workflows/ancestry.nf`, new): `ANCESTRY_RTIGER` (the second half: `CALL_ANCESTRY` ->
  `ANCESTRY_GRID` -> `ANCESTRY_VCF_INDEX`). `CALL_ANCESTRY`'s input is grouped with `groupTuple` by `[donor, region]`
  (`chromosome`) or by `donor` (`genome`).
- `bin/call_ancestry.R`: chromosomes from the markers' `CHROM` (today fixed to 1); the 2r coverage cut per chromosome,
  as RTIGER requires. One chromosome in gives today's output.
- `bin/write_ancestry_grid.R`: reads only the segments on its region's chromosome.

## Files

`main.nf` (steps; `ZEALGT`), `nextflow_schema.json`, `assets/schema_counts.json`, `workflows/{variant_calling,ancestry}.nf`,
`subworkflows/local/{line_counts,ancestry_rtiger}/`, `subworkflows/local/utils_nfcore_zealgt_pipeline/`
(schema per step), `bin/call_ancestry.R`, `bin/write_ancestry_grid.R`, `conf/{modules,hpc_dev,hpc_prod}.config`,
`tests/`, `.github/workflows/metro_check.yml`, both metro maps, `docs/{structure,running,usage,output,TERMINOLOGY}.md`.

## Choices this spec settles (yours to confirm)

- **Cut after `COUNT_LINES`.** Gap filling step 1 reads only BC1 pools and B73 controls, so nothing flows back from
  RTIGER. Rejected: CRISP and gap filling inside the ancestry step (every HMM setting would rerun discovery).
- **Step names `variant_calling`, `ancestry`** (as nf-core/sarek's `variant_calling`). Rejected: `variant`,
  `variantcall`, `ancestry_calling`.
- **Short task names** (user, 2026-10-16: hazel task names run to ~80 characters): stages `LINE_COUNTS` and
  `ANCESTRY_RTIGER`, and the pipeline workflow in `main.nf` renamed `SAWERSRELLANLABS_ZEALGT` -> `ZEALGT`, so
  `ZEALGT:VARIANT_CALLING:LINE_COUNTS:COUNT_LINES` (46) instead of 79. Rejected: nf-core's input_task_tool stage names
  (`CRAM_MARKER_COUNTS_BCFTOOLS`). The prefix rename is its own commit; no lint test reads that
  name (nf-core tools 4.1.0), but a template sync (`TEMPLATE` branch) brings the template's name back into
  `main.nf`, resolved by hand at each sync.
- **A counts sheet as the `ancestry` input**, published as a workflow-output index. Rejected: a results folder as input
  (the pipeline would list files itself).
- **`--ancestry_fit chromosome` the default**, so outputs stay as today. Rejected: `genome` the default before it is
  tested on our markers.
- **Rigidity unchanged**: 0.5 % of the markers in the fit (with `genome`, of all chromosomes' markers). The rule
  (fraction, 512, per Mb) is open decision 1 and stays out of this milestone.
- **Published paths renamed** (`genotype/` -> `variant_calling/`, `ancestry/`); results already on `/rsstu` stay where
  they are. Rejected: keeping `genotype/` for the first step (the name would no longer say what it holds).

## Not in this milestone

- The genome-wide diploperennis run (its own run plan after this milestone).
- The planned `GAP_FILLING_LINES` and `GENOTYPE_PROJECTION` rows: they read ancestry, so they will go in `ancestry`.

## Tests

1. **Tools** (laptop): `call_ancestry.R` on the chr10 fixture gives today's files byte for byte; on a two-chromosome
   fixture it fits once and writes both chromosomes. `write_ancestry_grid.R` with two chromosomes' segments.
2. **Wiring** (laptop, stubs): `variant_calling` with two regions publishes counts and the sheet; `ancestry` from that
   sheet with `chromosome` (donors x regions `CALL_ANCESTRY` tasks) and `genome` (one per donor); both DAGs.
3. **Hazel setup**: `nextflow config` and `inspect` for both steps, the stubs of `CALL_ANCESTRY` and `ANCESTRY_GRID`.
4. **Review**: CodeRabbit on the commit range.
5. **Slice** (laptop, <= 15 min): the pilot slice through `variant_calling` then `ancestry --ancestry_fit chromosome`;
   segments, line checks and grid equal those of `genotype` on `dev`.

## Done when

- Tests 1-5 pass; `nf-core pipelines lint` has no failures.
- `docs/structure.md` and both metro maps show the two steps; `decisions.md` holds only the choices you confirm.
