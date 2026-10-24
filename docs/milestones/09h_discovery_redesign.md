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
| 12  | markers per chromosome | `CALL_ANCESTRY` logs and writes each chromosome's markers and the median line's covered markers (`markers_per_chrom.tsv`); no donor x chromosome exclusion; the zero-marker path tested                                                          | 2026-10-24             |

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

## Report (2026-10-24)

All tests on this branch. One question is OPEN for the user (the chr10 LODs, below); the rest is done.

### Tests

| #   | test                   | result                                                                                                                                                                                                                                                     |
| --- | ---------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | tools (laptop)         | `tests/bin/test_filter_site_depth.py` 3/3; the check pool rule and the NIL rule as `bcftools view` expressions on fixture VCFs; `bcftools isec` keeps exact CHROM POS REF ALT only; `tests/bin/test_ancestry_tools.R` 73/73, the zero-marker path included |
| 2   | wiring (laptop, stubs) | `tests/variant_calling.nf.test` 3/3, `tests/ancestry.nf.test` 4/4; both metro maps; `nf-core pipelines lint` 0 failures                                                                                                                                    |
| 3   | hazel setup            | jobs 1531870, 1531871, 1531973: all pass after the isec test fix (28de8c5); the new bcftools 1.23.1 image cached (job 1531869)                                                                                                                             |
| 4   | review                 | CodeRabbit dc8252c..d2fc2be: one finding, fixed (989b04b: the run stops when no `--b73_checks` ID is a check sample); second pass clean                                                                                                                    |
| 5   | slice (laptop)         | pilot, 2 donors, chr10:1-5 Mb, `dev` against 9h: below                                                                                                                                                                                                     |
| 6   | chr10 check (hazel)    | 42 mexicana and 6 diploperennis donors; variant calling job 1532055 (2 h 15 min), ancestry job 1532056 (10 min): below                                                                                                                                     |
| 7   | profile (hazel)        | `docs/RESOURCES.md` "Milestone 9h steps, measured on chr10" (fbb1689); no task failed or retried, no process above 0.72 of its memory request; requests unchanged                                                                                          |

### Slice (test 5)

Records per step, `dev` / 9h: CRISP 6,012 / 3,582 (Zx.0570_P2) and 3,054 / 1,846 (Zx.0540_P3); after the NIL rule
2,581 / 1,432 and 1,919 / 1,052; tier A 1,610 / 904 and 1,114 / 598; union 2,450 / 1,368; union-ALT markers 1,587 / 846
and 1,380 / 726; markers counted 1,587 / 126 and 1,380 / 111 (9h after the known-sites filter); 116 after the depth
filter. Segments per line 1.19 / 1.16 (43 lines) and 1.49 / 1.31 (39 lines). The slice's known-sites fixture was
wideseq positions only (any non-REF ALT accepted), so its share kept is not the method's; the chr10 check with the real
panel keeps 39.7 % / 38.8 %, as on 2026-10-23. Tables: `agent/m09h/slice/steps.tsv`, `segments.tsv`.

### chr10 check (test 6), against SNP50K and the 2026-10-23 "depth + wideseq" set

573 mexicana and 252 diploperennis lines, the same in all three sets; family covariate, chr10-only permutation
thresholds (`agent/m09h/chr10_check/compare_*.tsv`, `compare.log`).

| chr10                      | mex SNP50K | mex 10-23 | mex 9h | dip SNP50K | dip 10-23 | dip 9h |
| -------------------------- | ---------- | --------- | ------ | ---------- | --------- | ------ |
| markers per donor (median) | -          | 32,453    | 19,567 | -          | 26,423    | 14,797 |
| class-separation MSE       | 0.157      | 0.024     | 0.019  | 0.131      | 0.032     | 0.027  |
| HET %                      | 10.1       | 7.4       | 7.3    | 8.7        | 7.7       | 7.7    |
| ALT %                      | 1.4        | 4.9       | 5.0    | 3.1        | 4.5       | 4.7    |
| segments per line          | 0.49       | 1.13      | 1.09   | 0.51       | 1.23      | 1.14   |
| PH full max LOD            | 7.04       | 6.70      | 6.19   | 5.25       | 6.32      | 6.32   |
| DTA full max LOD           | 3.16       | 3.17      | 3.41   | 6.70       | 7.91      | 7.27   |

- Class separation and fragmentation improve on 10-23 in both taxa; classes are as on 10-23.
- Markers 42-45 % fewer than 10-23, from two causes:
  1. This check's union came from 48 donors of two taxa; run 1367152 (behind the 10-23 set) pooled 95 donors of all
     taxa. Sites from the other taxa were 15 % (mexicana) and 10 % (diploperennis) of each donor's old markers.
  2. Tier-A sites 0.71x (mexicana) and 0.67x (diploperennis): MAPQ 60 / BQ 30, the check pool rule, the 21 QC-PASS
     checks and the low-copy cut together (their shares cannot be separated in this run).
- Known-sites share 39.7 % / 38.8 % (as 10-23); the depth filter keeps 75 % / 71 %. Fewest markers on a chromosome:
  Zx.0560_P4, 2,629. No line dropped.
- **OPEN for the user**: mexicana PH −0.51 and diploperennis DTA −0.64 against 10-23 are more than "a few tenths".
  My reading, not proven: fewer markers, mostly from the two-taxa union. The genome-wide run pools all taxa as 1367152
  and 10-23 did, and its chr10 against this check tests that reading (run plan, check 2).

### Choices made during the work

- **`CRISP_CONTIGS` added** (nf-core `bcftools/reheader --fai`, one task per donor x region): CRISP writes no contig
  lines, and `bcftools view -s ^B73_checks` refuses to drop a sample without them.
- **The check pool rule folded into `BED_CLIP`** (one `bcftools view -s ^B73_checks -e 'FMT/AC[1:0]>=1'` call) instead
  of a process of its own after `BED_CLIP` (spec row 5): one Slurm job fewer per donor x region; with `CRISP_CONTIGS`
  the job count equals the spec's.
- **The `--b73_checks` test fixture lists `C_1` only**: `C_2` holds the NIL pool's reads (as a QC-PASS check its ALT
  counts would drop every site) and `C_3` is a Purple check.
- **`ifEmpty` error when no listed check is in the sheet** (CodeRabbit): otherwise the run ended without variant-calling
  output. Listed checks absent from a subset sheet (slice, coverage floor) still leave the pool silently.

### DAG

The laptop stub run's `-with-dag` (`agent/m09h/stub_vc/dag.html`) and the chr10 check's `pipeline_dag_2026-10-24_05-10-28.html` (variant calling) and
`pipeline_dag_2026-10-24_07-26-00.html` (ancestry) in `/share/maize/frodrig4/nf_work/m09h_chr10_check/results/pipeline_info/`;
the processes as in `docs/images/zealgt_metro_full.svg`.

### Next

The genome-wide run: `docs/runs/variant_calling_ancestry_genome.md`, submitted after this milestone merges.
