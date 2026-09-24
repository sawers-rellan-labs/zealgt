# zealgt

Genotyping pipeline for the ZEAL population (teosinte × B73 BC₂S₃ near-isogenic lines): from pooled BC1 libraries and BC₂S₃ skims to
per-line **ancestry** (RTIGER) and **imputed genotypes** at the union of informative sites (pairwise PHG), for QTL mapping and GWAS.

Successor of the exploratory work in `zealbc1` (chr10 pilots, 2026-09-10 → 24). Code and data are separate: this repo is code and docs;
data and results live on the BZea partition on hazel.

## Documents
| file | what |
|---|---|
| `docs/PLAN_pipeline.md` | pipeline plan (draft): stages as Nextflow entries, caching/rerun rules, storage and cleanup (from the 2026-09-24 disk audit), sample QC, known issues and open decisions |
| `docs/REQUIREMENTS.md` | requirements for a minimal run: inputs, software, measured compute per stage, hard-coded values to parameterize |
| `docs/math_supplement.tex` | mathematical supplement (draft): crossing scheme, BC1 pools vs BC₂S₃ bulks, reads at low coverage (λ), variant discovery, marker union and gap filling, ancestry inference and genotype imputation |
| `docs/runs/` | one run card per run: purpose, donors (BC1 samples, lines, coverage), exclusions |

Build the supplement: `latexmk -pdf -outdir=build docs/math_supplement.tex`.
