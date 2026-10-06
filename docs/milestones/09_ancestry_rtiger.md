# Milestone 9: ancestry inference with RTIGER

Third stage of `GENOTYPE` (`CRAM_ANCESTRY_RTIGER` in `docs/structure.md`): each line's ancestry mosaic, the donor
segments it carries, as ranges, as an R/qtl genotype file on a 0.1 cM grid, and as a VCF.

## Why (user, 2026-10-05)

"We want the ancestry mosaic as the ranges and the VCF for R/qtl."

## Scope

Per donor and chromosome: RTIGER on the donor's lines at the donor's own tier-A sites (Text S6, "Ancestry inference"),
then the mosaic read at a marker grid for R/qtl and the VCF. Single-plant approximation: RTIGER's three states (B73/B73,
het, donor/donor) are used as they are, although each line is a six-plant bulk (Text S2). No per-site posteriors.

## Inputs

- From `CRAM_VARIANT_DISCOVERY_CRISP`, per donor: its tier-A sites (`tier_a`, Milestone 8).
- From `SITES_UNION_GAPFILL`: the union VCF of the chromosome (the grid's candidate markers).
- Per donor: its lines' CRAMs (`role` = nil, after the coverage filter), `meta.donor`.
- `--fasta`, `--region` as in Milestones 7 and 8.
- The maize genetic map: nilHMM's bundled v5 consensus map (`load_map("v5")`), inside the nilHMM container.

## Outputs

Per chromosome, in `genotype/ancestry/`:

- `<chr>.grid.tsv`: the R/qtl markers, `marker, chrom, bp, cM` (union sites at least 0.1 cM apart).
- Per donor:
  - `<donor>.<chr>.segments.bed`: the mosaic, `chrom, start, end, line, state` (0 B73/B73, 1 het, 2 donor/donor;
    BED coordinates).
  - `<donor>.<chr>.rqtl.csv`: R/qtl `csvr` (markers in rows: `marker, chr, cM`, then one column per line; `0`, `1`,
    `2` = state; `NA` where the line has no segment), for `read.cross()` with `format = "csvr"`,
    `crosstype = "bcsft"`, `BC.gen = 2`, `F.gen = 2`, `genotypes = c("0", "1", "2")` (BC2S2, user 2026-10-05).
  - `<donor>.<chr>.ancestry.vcf.gz` + `.tbi`: the grid markers, one sample per line; `REF`, `ALT` the union site's
    bases (`REF` = B73); `GT` `0/0`, `0/1`, `1/1` = ancestry dosage 0, 1, 2, `./.` without a segment; the header
    says `GT` is ancestry on the site's alleles, not the line's bases (as zealhmm `scripts/zeal_export_release.R`).
  - `<donor>.<chr>.dropped_lines.tsv`: lines removed by the marker QC, with their covered markers and the cut.

## Processes

Stage `CRAM_ANCESTRY_RTIGER`, one RTIGER call per donor and chromosome:

1. `COUNT_LINES` (nf-core `bcftools/mpileup`, patched in Milestone 8 to stage the index): each line at its donor's
   tier-A sites, `-I -a AD -q 20 -Q 20 -r <region>`, one task per line (as `COUNT_UNION`).
2. `CALL_ANCESTRY` (local module, nilHMM container, own tool `bin/call_ancestry.R`): per donor, the lines' counts in;
   rigidity r = 0.5 % of the donor's tier-A sites on the chromosome (user, 2026-10-05; chr10: Zx.0540_P3 164,
   Zx.0570_P2 241); lines with fewer than 2r covered markers (≥ 1 read) on the chromosome dropped (user: RTIGER fails
   below 2r); nilHMM `call_ancestry(caller = "rtiger", rigidity = r)`; segments and dropped lines out.
3. `ANCESTRY_GRID` (local module, nilHMM container, own tool `bin/write_ancestry_grid.R`): the union sites placed on
   the v5 map (`bp_to_cm`), thinned to markers ≥ 0.1 cM apart by the greedy sweep (sort by cM, keep the first, skip all
   within 0.1 cM; exact on a line, Jena et al. 2018; zealhmm `scripts/teonam_gwas118k_thin01.R`); each donor's
   segments read at the grid (zealhmm `rasterize_states`): the grid, the R/qtl file and the VCF (plain) out.
4. `ANCESTRY_VCF_INDEX` (nf-core `bcftools/view`, `-Oz --write-index=tbi`): the VCF compressed and indexed; the nilHMM
   container has no bgzip.

## Choices this spec settles (yours to confirm)

- **RTIGER markers: the donor's discovery tier-A sites.** Rejected: the union's re-scored own ALT sites, which would
  make ancestry wait for step 1 (now the two run side by side, `structure.md`).
- **Rigidity 0.5 % of the donor's markers per chromosome** (user). Rejected: a fixed 500 (zealbc1), the SNP50K density
  rule (2026-09-23).
- **Single-plant states, no posteriors** (user). Rejected: bulk states (Text S2) and per-site posteriors, which only
  joint genotyping (Text S5, proposal) needs.
- **One grid per chromosome, shared by all donors**, from the union. Rejected: a grid per donor (R/qtl files of
  different donors would not line up); `bcftools +prune` (thins by bp or LD, not cM).
- **Thinning in our tool**, a few lines. Rejected: waiting for nilHMM's `method = "jena2018"` (nilhmm#28, open).
- **One R/qtl file per donor** (each donor's lines are one `bcsft` population). Rejected: one file over all donors
  (that is the joint linkage model, outside R/qtl's `read.cross`).
- **Lines below 2r covered markers dropped** (user, 2026-10-05): RTIGER fails on them.
- **Ancestry dosage on the union site's `REF`/`ALT`**, as the zealbc1 release export (user, 2026-10-05); at sites
  where the donor carries the B73 base, `GT` is ancestry, not the line's bases. Rejected: a symbolic `<DONOR>` allele;
  a grid per donor from its own tier-A sites.
- **R/qtl numeric 0/1/2, `NA` missing, BC2S2** (user, 2026-10-05), as the shared dataset plan's 0/1/2 matrices.
  Rejected: `A`/`H`/`B` with `-`.

## Not in this milestone

- `GAP_FILLING_LINES` (step 2), `GENOTYPE_PROJECTION`, joint genotyping, the QTL scan itself (the pilot's 84 lines are
  below zealbc1's n > 100 per taxon for R/qtl), the per-chromosome fan-out of `--region`.

## Tests

1. **Tool** (laptop): `call_ancestry.R` on counts simulated with nilHMM (`simulate_nil`, `simulate_counts`, a BC2S2
   design) against the true mosaic; the rigidity and the marker QC on hand-made counts, and RTIGER's error on a line
   below 2r. `write_ancestry_grid.R`: the thinning against the zealhmm reference sweep; rasterizing hand-made
   segments; the R/qtl file read back with `qtl::read.cross`; the VCF read with bcftools. R code passes `lintr`, formatted with `styler`.
2. **Wiring** (laptop, stubs, seconds): two donors, one count per line, one RTIGER call per donor, one grid; the DAG.
3. **Slice** (laptop, real data, ≤ 15 min): both pilot donors and their 84 lines, chr10:1-5 Mb, Docker.
4. **Cluster** (hazel, `hpc_dev`, < 30 min): `-stub-run`, then both pilot donors on the whole chr10, `-resume` from
   the chr10 union run (job 1111642), for the resource profile and the segments per line against zealbc1's RTIGER
   (`ZEAL/results/union_zx0540_zx0570_chr10/rtiger/`). A bug check.

## Done when

- Tool, stub and slice tests pass; `nf-core pipelines lint` has no failures.
- The hazel run on chr10 wrote the four outputs per donor and the grid; resources are in config.
- `docs/structure.md`: this row "built (milestone 9)"; Text S6 states the rigidity rule and the grid.
