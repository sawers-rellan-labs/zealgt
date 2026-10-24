# Milestone 9h: discovery redesign

`VARIANT_CALLING` as decided in `../decisions.md` (entries 2026-10-17 to 2026-10-24 marked Milestone 9h) and tested on
chr10 on 2026-10-23/24 as the "depth + wideseq" set: QC-PASS B73 checks, CRISP per donor over its BC1 pools, its NIL pool
and the check pool, MAPQ >= 60 / BQ >= 30 throughout, inputs cut to the low-copy ranges, tier A and gap filling as now,
then a depth filter and a known-sites filter (the wideseq panel) on each donor's markers.

## Why (user)

- 2026-10-17: "I need the variant to be present in a BC1 and the segregating population. That was my intent." "the crisp
  thing should go over the 3 pools: BC1s: NILs: Checks. But only the decent checks not the ones contaminated"
  ("decent" replaced by the user with "QC PASS B73").
- 2026-10-22: "I believe we have established from the controls that there is a noise in the sequencing thta is why I
  suggested usingbthe Q30 and MQ 60. that filter must be kept throughpout." (without the swearing) "I need to institute
  the right discovery pipeline add the [...] "wideseq filter" nad check mexicana and diplo."
- 2026-10-23: "b73 has some sites that have sequence divergence from the reference those I would relly like removed".

## Inputs and outputs

- Inputs as now: the CRAM samplesheet (`wgs_metrics` column), `--fasta`, `--lowcopy_bed`, `--b73_controls`, `--regions`.
- New, both built once outside the pipeline like the low-copy BED:
  - `--known_sites`: a bgzipped, indexed sites VCF (CHROM POS REF ALT) of known variants, the role GATK BQSR's
    `--known-sites` plays; here the wideseq panel (Schnable 2023, `/rsstu/.../bzeaseq/wideseq_ref/`).
  - `--b73_checks`: a CSV of the QC-PASS B73 checks (`sample_id`), the 21 of 23 checks with a whole-genome mismatch rate
    under 0.1 % on bases of quality >= 30 (`samtools stats` with the reference, job 1388640; decisions.md 2026-10-21).
- Dropped: `--check_sites`, `--max_check_alt_rate`, and the output `dropped_b73_checks.tsv`.
- Outputs as now (discovery VCFs and site tables, union, donor alleles, counts, counts sheet). The counts sheet's
  `markers` column points at the filtered markers (known sites, depth).

## Changes

| #   | step                   | change                                                                                                                                                                                                                                           | decision               |
| --- | ---------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ---------------------- |
| 1   | read filters           | CRISP `--mmq 60 --mbq 30`; `-q 60 -Q 30` in `BCFTOOLS_MPILEUP`, `COUNT_UNION`, `COUNT_LINES`                                                                                                                                                     | 2026-10-22             |
| 2   | QC-PASS checks         | the check pool = the `check` samples listed in `--b73_checks` (any batch); replaces `CHECK_COUNTS`, `CHECK_ALT_RATE`                                                                                                                             | 2026-10-21             |
| 3   | inputs cut to low-copy | `FILTER_BC1` and the pool filters: `samtools view -F 0x800 -L <low-copy BED>` (the module's `bed` input)                                                                                                                                         | 2026-10-23             |
| 4   | CRISP pools            | per donor x region: its NIL pool (first, as the witness now), the check pool (second), its BC1 pools; `-p 12` for every pool                                                                                                                     | 2026-10-17, 2026-10-23 |
| 5   | check pool rule        | after `BED_CLIP`: drop records where CRISP's check pool `FORMAT/AC` >= 1 (`bcftools view -e`), then drop the check pool column before scoring                                                                                                    | 2026-10-23             |
| 6   | NIL rule               | `WITNESS_VETO` as now (>= 1 ALT read in the NIL pool), on the donor's own sites only                                                                                                                                                             | 2026-10-23, 2026-10-24 |
| 7   | own sites              | tier A as now (`POOLED_LIKELIHOOD_TIERS`; the B73 controls and the check pool as the error source)                                                                                                                                               | 2026-10-24             |
| 8   | gap filling            | `SITES_UNION_GAPFILL` as now, with the read filters of row 1; no NIL rule on gap-filled sites                                                                                                                                                    | 2026-10-23, 2026-10-24 |
| 9   | known-sites filter     | per donor x region, its union-ALT markers kept where CHROM, POS, REF and ALT are in `--known_sites` (nf-core `bcftools/isec`), before `COUNT_LINES`                                                                                              | 2026-10-23             |
| 10  | depth filter           | after `COUNT_LINES`, per region over all donors' count VCFs: a marker kept where its reads summed over the lines of the donors carrying it are 0.5-2x those lines' expected reads (each line's mean reads per marker); new local module and tool | 2026-10-24             |
| 11  | docs                   | `structure.md`, both metro maps, `docs/RESOURCES.md`; the math supplement and the Milestone 7 spec keep tier A, lose the "witness" name for the NIL pool                                                                                         |                        |

## Choices this spec settles (approved by the user, 2026-10-24)

- **Check pool second in CRISP's input list**, so the rule of row 5 reads a fixed sample index (`FMT/AC[1:0]`).
  Rejected: selecting the pool by name (bcftools expressions index samples by position).
- **Known-sites filter before `COUNT_LINES`, depth after**: the known-sites filter needs no counts and makes counting
  cheaper; depth needs the lines' reads. Rejected: both after counting (as on chr10; same markers, more counting).
- **The depth filter is an own tool** (`bin/filter_site_depth.py`): no established tool sums reads over several VCFs'
  samples against each sample's own expected depth. Rejected: `bcftools` `INFO/DP` bounds (absolute, not per line).
- **QC-PASS as an input list**, not computed in the pipeline: the list does not change between runs. Rejected: a
  `samtools stats` step per check and a parser tool.
- **The NIL pool keeps the witness's channel and module wiring**, renamed in `structure.md` and the docs only.

## Not in this milestone

- The genome-wide run and its QTL comparison against SNP50K (mexicana EN chr1, PROLIF chr4, STPI chr2, KINKI chr2;
  diploperennis DTA, PH): a run plan in `../runs/` after the merge.
- Joint CRISP over all pools (window test nb40, 2026-10-24): a later milestone if wanted.
- Renaming "MAF" in the zealhmm notebooks.

## Tests

1. **Tools** (laptop): `filter_site_depth.py` against hand-computed ratios; the check pool rule and the NIL rule as
   `bcftools view` expressions on a fixture VCF; `bcftools isec` keeps only exact CHROM POS REF ALT matches.
2. **Wiring** (laptop, stubs): DAG and both metro maps.
3. **Hazel setup**: `nextflow config`, `inspect`, process stubs, all at once (`scripts/run_hazel_tests.sbatch`).
4. **Review**: CodeRabbit on the commit range.
5. **Slice** (laptop, <= 15 min): the pilot slice through `variant_calling` and `ancestry`; sites per step reported
   against `dev`.
6. **chr10 check** (hazel): both taxa (42 mexicana, 6 diploperennis donors) through `variant_calling` and `ancestry`,
   compared with the 2026-10-23 depth + wideseq set on the four criteria of `zeal-chr10-no-tiers.qmd` (class-separation
   MSE, BC2S2 classes, segments per line, PH and DTA LOD). Expected differences: the check pool rule, the 21 QC-PASS
   checks, inputs cut to low-copy.
7. **Profile** (hazel, <= 30 min per process): CRISP with three pool kinds on one donor's chr10, the depth filter on
   chr10.

## Done when

- Tests 1-7 pass; test 6 within a few tenths of the 2026-10-23 numbers or the differences explained; `nf-core pipelines
lint` has no failures; docs above updated.
