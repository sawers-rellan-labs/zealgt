# Run plan: GENOTYPE chr10, diploperennis with partner taxa in its union (draft)

Draft, for the user's OK before any submission.

## Why

User, 2026-10-16: "plan the same approach for diplo as we did for huehue: make the genotyping using information from
parviglumis and mexicana; there is a chance that the fragmentation improves; judging by the FST it should work."
Diploperennis fragments (diagnosis 2026-10-15, §3: 35 % of its SNP50K HET segments >= 1 Mb split into >= 3 pieces, 15 %
in mexicana; cause not found). Huehuetenangensis lost its fragmentation when a partner taxon joined its union
(notebook 06). FST (Chen 2022, Fig. 2a source data): diploperennis-parviglumis 0.230, -mexicana 0.277.

## Runs (chr10, code of runs A-C: origin/dev 8bfdbe7 via branch runs-genotype-huehue-chr10)

| run   | union donors                                   | baseline / note                                                         |
| ----- | ---------------------------------------------- | ----------------------------------------------------------------------- |
| alone | 6 diploperennis                                | existing run 1270808 (same code and parameters); no rerun               |
| D     | 6 diploperennis + 40 parviglumis               |                                                                         |
| E     | 6 diploperennis + 42 mexicana                  | resumes mexicana's session 05f75070 in nf_work/zealgt_dev, as run C did |
| F     | 6 diploperennis + 40 parviglumis + 42 mexicana | the three-taxon union also proposed for huehuetenangensis               |

- Sheets: as `docs/runs/genotype_huehue_chr10/` (made by `agent/huehue_chr10/write_sheets.py`): diploperennis rows from
  `docs/runs/genotype_diploperennis_chr10/samplesheet.csv`, partner rows from the huehue sheets (parviglumis from
  `huehue_parviglumis.csv`, mexicana from `huehue_mexicana.csv`, huehuetenangensis rows left out); the same B73 checks.
- hpc_dev, `--region chr10` (9d not merged into this code), parameters as runs A-C; head jobs on the normal QOS, 12 h,
  16 GB, `NXF_OPTS="-Xms1g -Xmx12g"`; each run its own launch folder except E (resume). Run D can resume run B's
  parviglumis discovery if launched in `nf_work/zealgt_dev_hue_parv` with `-resume <run B session>`; F can resume one of
  the two.
- Checkout: `ZEAL/zealgt` (on `runs-genotype-huehue-chr10`, no run uses it now); cached inputs are hashed by path, so
  resumed runs must use that same checkout.
- Before submitting: the sheet check (paths, every donor keeps a BC1 pool and a sample >= 0.05x) and
  `scripts/run_hazel_tests.sbatch` is not needed (no code change).

## Estimates (runs A-C, 2026-10-16)

D ~2-2.5 h (run B: 2 h 17 min), E ~1.5-2 h (run C: 1 h 44 min), F ~2.5-3 h; all side by side within the 768-CPU short
QOS; /share +0.5 TB each at most (frodrig4 at ~0.1 TB; group files at 50 % of 1 M: watch it).

## Comparison (a notebook like 06, inputs collected first by a script with a log, notebook build < 5 min)

For the 6 diploperennis donors, alone (1270808) against D, E, F: markers own / gap-filled; line checks (segments per
sample, REF / HET / ALT % ALT, sample introgression dosage check); the fragmentation measure of the diagnosis (share of
SNP50K HET segments >= 1 Mb kept whole / split into >= 3 pieces); class shares against BC2S2 and SNP50K; the dilution
factor per sample (notebook 05); a chromosome painting in the user's style (SNP50K | alone | + parviglumis | + mexicana
| all three; `agent/genochr10/dip_plots/fig1_paint_columns.R`). Partner effect: mexicana donors against 1273053.

Expectation, not a measurement: a smaller effect than for huehuetenangensis, because diploperennis already has 6
donors and 29-145 k markers per donor alone (its fragmentation may have another cause: dilution in Zd.0020_P3), and its
partners are more distant (0.23-0.28 against 0.20-0.25).
