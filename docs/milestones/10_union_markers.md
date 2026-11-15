# Milestone 10: union markers within each taxon (`--step markers`)

DRAFT, 2026-11-15, for the user's approval.

## Why

User, 2026-11-15: "I think I'll do the unipon for now"; on the huehuetenangensis union (row 2, jobs 1855319-1856527):
"what I do not like is that thatr does not seem to be a nextflow run". Row 2 was sbatch scripts in `agent/`; this
milestone makes it a pipeline step, so every taxon gets the same method from one run.

## What it does

A new step between `variant_calling` and `ancestry`, reading an existing variant-calling run (run 1367152) and writing a
counts sheet for `--step ancestry`. Per region, as row 2 did (`agent/hue_q60q30_maf/`, `agent/hue_q60q30_union/`):

1. **Recount** each donor's lines at its markers (the counts sheet's `markers`, the union-ALT markers of run 1367152)
   at MAPQ >= 60 / BQ >= 30 (decisions.md 2026-10-21).
2. **Flag sites per taxon**, over the lines of every donor of the taxon that has the site among its markers:
   - depth: reads summed over those lines in 0.5-2x their expected reads (each line's reads per marker in the region,
     from run 1367152's count VCF, as row 2's `lambda.tsv`);
   - MQ: read-weighted mean `INFO/MQ` > 40;
   - "MAF": lines with an ALT read / lines >= 0.05 (a line share, not an allele frequency).
3. **Keep each donor's markers** that pass all three and whose POS, REF, ALT are in wideseq (`--known_sites`).
4. **Union within the taxon**: the kept markers of the taxon's donors, one record per position.
5. **Count each donor's lines at its taxon's union** at MAPQ >= 60 / BQ >= 30.
6. **Counts sheet** `samplesheets/<input name>.markers.csv`: `counts` = step 5's VCF, `markers` = the taxon union,
   `union` = run 1367152's union (the ancestry grid), as row 2's `counts.csv`.

`--step ancestry` runs on that sheet unchanged (chromosome fit, 1 Mb rigidity, as row 2).

## Inputs and outputs

- `--input`: a VARIANT_CALLING counts sheet (`assets/schema_counts.json`: donor, region, counts, markers, union).
- `--crams`: the CRAM sheet of that run (`assets/schema_cram.json`), for the lines' CRAMs (`role = nil`, coverage floor
  as in variant calling).
- `--known_sites` (wideseq, `ZEAL/reference/wideseq_sites_biallelic_snps.vcf.gz`), the reference FASTA.
- Outputs under `markers/`: per donor x region the recount and union-count VCFs, per taxon x region the flags TSV and the
  union VCF, `marker_counts.tsv` (markers left after each filter, per donor x region, as row 2's), and the sheet.

## Processes (all per region)

| process        | tool                                                                                                                                             | per   |
| -------------- | ------------------------------------------------------------------------------------------------------------------------------------------------ | ----- |
| `RECOUNT`      | nf-core `bcftools/mpileup` (`-I -D -a AD -q 60 -Q 30 --ff UNMAP,SECONDARY,QCFAIL,DUP,SUPPLEMENTARY`, `-T` markers; call `-m -A`)                 | donor |
| `SITE_READS`   | nf-core `bcftools/query` (`%POS\t%REF\t%ALT\t%INFO/MQ[\t%AD]`)                                                                                   | donor |
| `FLAG_SITES`   | `bin/flag_marker_sites.py` (own script: no bcftools command sums reads and ALT-carrying lines over several donors' lines against expected reads) | taxon |
| `KEEP_MARKERS` | nf-core `bcftools/isec` (`-c none -n =2 -w 1`, `-T` the passing positions): the donor's markers in wideseq that pass                             | donor |
| `TAXON_UNION`  | nf-core `bcftools/concat` (`-a`) then `bcftools/norm` (`-d any`)                                                                                 | taxon |
| `COUNT_UNION`  | nf-core `bcftools/mpileup`, settings of `RECOUNT`, `-T` the taxon union                                                                          | donor |

- Taxon = the donor ID's prefix (`Zx`, `Zv`, `Zd`, `Zl`, `Zh`), a `map` on `meta.donor`; donors grouped by `groupTuple`
  with `groupKey` (each taxon's donor count known from the sheet).

## Choices this spec settles

- **A new step**, not a change to `variant_calling`: run 1367152's discovery is reused unchanged. Rejected: rerunning
  discovery at 60/30 (9h's route, rejected 2026-10-24).
- **Union within each taxon**, as row 2 and the chr10 mexicana/diploperennis union sets. Rejected: one union over all
  taxa (run 1367152's union, which the step reads only for the grid).
- **Expected reads from run 1367152's count VCF**, as row 2 tested. Rejected (mine): from the 60/30 recount (untested).
- **Filters as row 2**, no new ones; no tiers, no veto.

## Tests

1. Tool: `flag_marker_sites.py` on a fixture of row 2's chr10 rows; its flags equal `agent/hue_q60q30_maf/flags/chr10.tsv`.
2. Wiring: `--step markers` on stubs, laptop, seconds, with the DAG.
3. Hazel setup checks (`scripts/run_hazel_tests.sbatch`): config, inspect, every process's stub at once.
4. CodeRabbit on the commit range.
5. Slice: huehuetenangensis chr10, from run 1367152's sheet; `marker_counts.tsv` and the union size equal row 2's
   (`agent/hue_q60q30_maf/marker_counts.tsv`, `agent/hue_q60q30_union/union_sizes.tsv`).
6. Resources: from the slice and row 2's jobs (recount 1-4 min, <= 3 GB; union count 1-2.5 min, <= 2.5 GB).

## Done when

- The huehuetenangensis chr10 slice reproduces row 2's markers and union exactly, and `--step ancestry` on its sheet
  gives row 2's segments on chr10.
- Both metro maps show the new step; `docs/structure.md` has its row.
- Then the run: `docs/runs/union_markers_genome.md`.
