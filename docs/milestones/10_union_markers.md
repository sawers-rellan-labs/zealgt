# Milestone 10: union markers within each taxon (`--step markers`)

DRAFT, 2026-11-15, for the user's approval.

## Why

User, 2026-11-15: "I think I'll do the unipon for now"; on row 2 (huehuetenangensis union, sbatch scripts, jobs
1855319-1856527): "what I do not like is that thatr does not seem to be a nextflow run"; "I do not want 3000 lines of
code an 95 files for this run ... it should be sipler".

## Budget

About 230 lines in at most 8 files; no new nf-core modules; `variant_calling` and `ancestry` unchanged. `git diff --stat`
goes first in the report; over budget means cut, not explain.

## What it does

Reads run 1367152's outputs on `/rsstu` (nothing rerun or resumed) and writes a counts sheet for `--step ancestry`.
Per region, as row 2 (`agent/hue_q60q30_maf/`, `agent/hue_q60q30_union/`):

| process        | per   | what                                                                | tool                                                                   |
| -------------- | ----- | ------------------------------------------------------------------- | ---------------------------------------------------------------------- |
| `RECOUNT`      | donor | the donor's lines at its run-1367152 markers, MAPQ >= 60 / BQ >= 30 | installed nf-core `bcftools/mpileup` (as `COUNT_LINES`, `-q 60 -Q 30`) |
| `FLAG_MARKERS` | taxon | site flags, each donor's kept markers, the taxon union              | `bin/flag_marker_sites.py` (new)                                       |
| `COUNT_UNION`  | donor | the donor's lines at its taxon's union, MAPQ >= 60 / BQ >= 30       | installed nf-core `bcftools/mpileup`                                   |

`FLAG_MARKERS`, over the lines of every donor of the taxon that has the site among its markers (row 2's step B):

- depth: reads in 0.5-2x the expected reads (each line's reads per marker in the region, from its run-1367152 count VCF);
- MQ: read-weighted mean `INFO/MQ` > 40;
- line share: lines with an ALT read / lines >= 0.05;
- wideseq: POS, REF, ALT in `--known_sites`;
- union: the taxon's kept markers, one record per position (first donor's alleles, as row 2's `sort -u`).

Outputs: the union VCF (+ tbi), `flags.tsv`, `marker_counts.tsv` (markers left after each filter, per donor; row 2's
columns). Container: `python_pysam`, as `FILL_DONOR_ALLELES`.

Counts sheet `samplesheets/<input name>.markers.csv`: `counts` = `COUNT_UNION`'s VCF, `markers` = the taxon union,
`union` = run 1367152's union (the ancestry grid), as row 2's `counts.csv`.

## Inputs

- `--input`: run 1367152's counts sheet (`assets/schema_counts.json`).
- `--crams`: its CRAM sheet (`role = nil` rows; coverage floor as in variant calling).
- `--known_sites`: wideseq, `ZEAL/reference/wideseq_sites_biallelic_snps.vcf.gz`.
- Taxon = the donor ID's prefix (`Zx`, `Zv`, `Zd`, `Zl`, `Zh`), a `map` on `meta.donor`; donors per taxon by
  `groupTuple` with `groupKey`.

## Choices

- New step reading run 1367152. Rejected: rerunning discovery (9h, rejected 2026-10-24).
- Union within each taxon. Rejected: run 1367152's all-taxa union.
- Filters, wideseq and union in one script (one task per taxon x region). Rejected: `bcftools isec` + `merge` + `norm`
  (a new nf-core module, three more task kinds and their files under the file quota).
- Expected reads from run 1367152's count VCFs, as row 2. Rejected (mine): from the recount (untested).

## Tests

1. Script on a fixture cut from row 2's chr10 inputs: flags and markers equal row 2's.
2. Stubs on the laptop, seconds, with the DAG.
3. Hazel setup check (config, inspect, each process's stub).
4. CodeRabbit on the range.
5. Slice: huehuetenangensis chr10 from run 1367152's sheet; markers and union size equal row 2's
   (`agent/hue_q60q30_maf/marker_counts.tsv`, `agent/hue_q60q30_union/union_sizes.tsv`), and `--step ancestry` on its
   sheet gives row 2's chr10 segments.

## Done when

Tests pass within the budget; metro maps and `docs/structure.md` updated; then `docs/runs/union_markers_genome.md`.
