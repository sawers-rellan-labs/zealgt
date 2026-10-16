# Run plan: GENOTYPE chr10, diploperennis with partner taxa in its union (draft)

Draft, for the user's OK before any submission.

## Why

User, 2026-10-16: "plan the same approach for diplo as we did for huehue: make the genotyping using information from
parviglumis and mexicana; there is a chance that the fragmentation improves; judging by the FST it should work."
Diploperennis fragments (diagnosis 2026-10-15, §3: 35 % of its SNP50K HET segments >= 1 Mb split into >= 3 pieces, 15 %
in mexicana; cause not found). Huehuetenangensis lost its fragmentation when a partner taxon joined its union
(notebook 06). FST (Chen 2022, Fig. 2a source data): diploperennis-parviglumis 0.230, -mexicana 0.277.

## Runs (chr10, code of runs A-C: origin/dev 8bfdbe7 via branch runs-genotype-huehue-chr10)

| run   | union donors                                   | sheet                            | BC1 pools | lines | checks | rows  |
| ----- | ---------------------------------------------- | -------------------------------- | --------- | ----- | ------ | ----- |
| alone | 6 diploperennis                                | existing run 1270808; no rerun   | 25        | 256   | 23     | 304   |
| D     | 6 diploperennis + 40 parviglumis               | `diplo_parviglumis.csv`          | 193       | 862   | 23     | 1,078 |
| E     | 6 diploperennis + 42 mexicana                  | `diplo_mexicana.csv`             | 188       | 978   | 23     | 1,189 |
| F     | 6 diploperennis + 40 parviglumis + 42 mexicana | `diplo_parviglumis_mexicana.csv` | 356       | 1,584 | 23     | 1,963 |

- Sheets in `docs/runs/genotype_diploperennis_partners_chr10/` (written by `agent/diplo_chr10/write_sheets.py`):
  diploperennis rows verbatim from `genotype_diploperennis_chr10/samplesheet.csv`, parviglumis rows from
  `huehue_parviglumis.csv`, mexicana rows from `huehue_mexicana.csv` (huehuetenangensis rows left out), the same 23 B73
  checks and `b73_controls.csv`.
- Sheet check (`docs/running.md` "Stubs on hazel" step 1): job 1329747 (2026-10-16): every path absolute
  and present in all three sheets; every donor keeps a BC1 pool and a line at or above 0.05x. Under the floor (dropped
  by the pipeline): three Zd lines (as in 1270808), five Zv lines (as in run B), seven Zx lines (as in 1273053).
- Code: no change since runs 1270808, B and C (all three report script hash `a77ec18`), so no stub, review or process
  tests.
- hpc_dev, `--region chr10`, parameters as runs A-C; head jobs normal QOS, 12 h, 16 GB, `NXF_OPTS="-Xms1g -Xmx12g"`.
- Each run resumes the session that holds most of its discovery, one session per run (`-resume` reuses the session's
  cache; two runs on one session at once would share it):
  - D in `nf_work/zealgt_dev_hue_parv`, session `b394eaef` (run B): 40 parviglumis donors and the checks cached;
  - E in `nf_work/zealgt_dev`, session `05f75070` (run 1273053, as run C): 42 mexicana donors and the checks cached;
  - F in `nf_work/zealgt_dev_dip`, session `205a6299` (run 1270808): 6 diploperennis donors and the checks cached;
    parviglumis and mexicana discovery run again.
- Checkout: `ZEAL/zealgt`, on `runs-genotype-huehue-chr10` at `15fdb0d`, clean, no job; pulled to this commit before
  the submission. The same checkout path keeps the caches valid (file inputs are hashed by path).

```
cd /rsstu/users/r/rrellan/BZea/ZEAL/zealgt
git fetch -q origin && git checkout -q runs-genotype-huehue-chr10 && git pull -q --ff-only
B=/rsstu/users/r/rrellan/BZea
S=/rsstu/users/r/rrellan/BZea/ZEAL/zealgt/docs/runs/genotype_diploperennis_partners_chr10
N=/share/maize/frodrig4/nf_work
G="--b73_controls $S/b73_controls.csv --lowcopy_bed $B/ZEAL/reference/lowcopy_chr10.bed --check_sites $B/bzeaseq/nilhmm/vcf/HQ_BZEA.vcf.gz --region chr10"
H="--parsable --partition=compute --qos=normal --time=12:00:00 --mem=16G"
# D: diploperennis + parviglumis, resuming run B
sbatch $H --export=ALL,ZEALGT_LAUNCH=$N/zealgt_dev_hue_parv,NXF_OPTS="-Xms1g -Xmx12g" \
  scripts/submit_head_job.sbatch hpc_dev --step genotype --input $S/diplo_parviglumis.csv $G \
  --outdir $N/zealgt_dev_hue_parv/genotype_diplo_parviglumis_chr10/results \
  -resume b394eaef-2ad2-4664-bc96-42588938665d
# E: diploperennis + mexicana, resuming run 1273053
sbatch $H --export=ALL,NXF_OPTS="-Xms1g -Xmx12g" \
  scripts/submit_head_job.sbatch hpc_dev --step genotype --input $S/diplo_mexicana.csv $G \
  --outdir $N/zealgt_dev/genotype_diplo_mexicana_chr10/results \
  -resume 05f75070-d26e-4647-943a-e7e45a898bae
# F: diploperennis + parviglumis + mexicana, resuming run 1270808
sbatch $H --export=ALL,ZEALGT_LAUNCH=$N/zealgt_dev_dip,NXF_OPTS="-Xms1g -Xmx12g" \
  scripts/submit_head_job.sbatch hpc_dev --step genotype --input $S/diplo_parviglumis_mexicana.csv $G \
  --outdir $N/zealgt_dev_dip/genotype_diplo_parviglumis_mexicana_chr10/results \
  -resume 205a6299-ebd7-4c6d-8854-ad9841b51e5c
```

Logs: `nf_work/zealgt_head_<job id>.log` per run; `.nextflow.log` in each launch directory.

## Estimates (runs A-C, 2026-10-16)

D ~2-2.5 h (run B: 2 h 16 min), E ~1.5-2 h (run C: 1 h 42 min), F ~3-3.5 h (82 donors' discovery, ~0.7 h, plus the
largest union); all three at once within the 768-CPU short QOS (no other job of frodrig4 runs); /share +0.5 TB each at
most, F up to ~1 TB (group files at 50 % of 1 M: watch it).

## Comparison (a notebook like 06, inputs collected first by a script with a log, notebook build < 5 min)

For the 6 diploperennis donors, alone (1270808) against D, E, F: markers own / gap-filled; line checks (segments per
sample, REF / HET / ALT % ALT, sample introgression dosage check); the fragmentation measure of the diagnosis (share of
SNP50K HET segments >= 1 Mb kept whole / split into >= 3 pieces); class shares against BC2S2 and SNP50K; the dilution
factor per sample (notebook 05); a chromosome painting in the user's style (SNP50K | alone | + parviglumis | + mexicana
| all three; `agent/genochr10/dip_plots/fig1_paint_columns.R`). Partner effect: mexicana donors against 1273053.

Expectation, not a measurement: a smaller effect than for huehuetenangensis, because diploperennis already has 6
donors and 29-145 k markers per donor alone (its fragmentation may have another cause: dilution in Zd.0020_P3), and its
partners are more distant (0.23-0.28 against 0.20-0.25).
