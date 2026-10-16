# Run plan: GENOTYPE chr10, huehuetenangensis alone, with parviglumis, with mexicana

DRAFT, 2026-10-16.

## Why

User, 2026-10-16: "genotype huehue on its own in chr10, we need data to have a decision; even better run a test of
huehue alone, huehue and parva, and huehue and mexicana". The decision: whether Z. mays ssp. huehuetenangensis (two
donors) gets its own union or joins another taxon's union. Chen 2022 (Fig. 2a source data), FST:
huehuetenangensis-parviglumis 0.200, huehuetenangensis-mexicana 0.248, mexicana-parviglumis 0.068.

Methods as settled (`docs/decisions.md`): 9a union-ALT markers, every donor of a run in its union, flag never drop,
`min_reads` 1.

## Inputs

`docs/runs/genotype_huehue_chr10/` (written by `agent/huehue_chr10/write_sheets.py` from `meta/samples.csv`, after
`agent/genochr10/write_sheets.py`), every not-excluded `bc1_sample` and `nil` of the taxa named, plus the 23 B73 checks
(12 `B73-bulk`, 11 `B73`) of the mexicana and diploperennis sheets; `b73_controls.csv`: `B73_ERR3288215`.

| run | sheet                    | donors       | BC1 pools | lines | checks | rows |
| --- | ------------------------ | ------------ | --------- | ----- | ------ | ---- |
| A   | `huehue.csv`             | 2 Zh         | 9         | 61    | 23     | 93   |
| B   | `huehue_parviglumis.csv` | 2 Zh + 40 Zv | 177       | 667   | 23     | 867  |
| C   | `huehue_mexicana.csv`    | 2 Zh + 42 Zx | 172       | 783   | 23     | 978  |

- Zh: `Zh.0020_P3` (4 pools, 26 lines), `Zh.0030_P4` (5 pools, 35 lines); aligned by `alignment_remaining.md`.
- C's 885 mexicana rows and all 23 checks are byte-identical to `genotype_mexicana_chr10/samplesheet.csv` (run
  1273053); `Zx.0390_P1` stays out (no BC1 pool).
- Sheet checks (`docs/running.md` "Stubs on hazel" step 1), job 1323750 (2026-10-16): every path absolute
  and present in all three sheets; every donor keeps a BC1 pool and a line at or above 0.05x. Under the floor (dropped
  by the pipeline, donors keep other lines): A none; B five Zv lines; C the seven Zx lines of 1273053.

## Before the run

- Code: `origin/dev` at `8bfdbe7`; this branch adds only these docs and sheets. GENOTYPE's modules, subworkflows,
  workflows and `conf/hpc_dev.config` are unchanged since run 1273053's commit `7235667` (only `hpc_prod.config` and
  `stub_hazel.config` differ). No new code, so no CodeRabbit review and no stub; the hazel process tests passed on dev
  (job 1322572).
- Checkout: `ZEAL/zealgt` is on `m09b-union-exclude` (`e575a7c`, not merged into dev), clean, used by no job (the 9d
  regression, job 1323153, runs from `ZEAL/zealgt_stubtest`). It switches to this branch for the three runs (user's
  OK): `git -C /rsstu/users/r/rrellan/BZea/ZEAL/zealgt fetch -q origin && git -C ... checkout runs-genotype-huehue-chr10`.
  The same checkout path keeps C's cache valid (file inputs are hashed by path).

## Runs

All three at once, `hpc_dev`, `--region chr10`, the mexicana and diploperennis parameters. Head jobs normal QOS, 12 h,
16 GB, heap 12 GB.

- A and B cold, each in its own launch directory: `nf_work/zealgt_dev_hue`, `nf_work/zealgt_dev_hue_parv`.
- C in `nf_work/zealgt_dev`, resuming session `05f75070` (run 1273053): the 42 mexicana donors' discovery and the B73
  checks' tasks come from the cache; the Zh discovery, the union of 44 donors and everything after it run. The
  alternative, its own cold launch directory, adds ~0.7 h of discovery and ~0.5 TB on `/share`.

```
cd /rsstu/users/r/rrellan/BZea/ZEAL/zealgt
B=/rsstu/users/r/rrellan/BZea
S=/rsstu/users/r/rrellan/BZea/ZEAL/zealgt/docs/runs/genotype_huehue_chr10
N=/share/maize/frodrig4/nf_work
G="--b73_controls $S/b73_controls.csv --lowcopy_bed $B/ZEAL/reference/lowcopy_chr10.bed --check_sites $B/bzeaseq/nilhmm/vcf/HQ_BZEA.vcf.gz --region chr10"
H="--parsable --partition=compute --qos=normal --time=12:00:00 --mem=16G"
# A: huehuetenangensis alone
sbatch $H --export=ALL,ZEALGT_LAUNCH=$N/zealgt_dev_hue,NXF_OPTS="-Xms1g -Xmx12g" \
  scripts/submit_head_job.sbatch hpc_dev --step genotype --input $S/huehue.csv $G \
  --outdir $N/zealgt_dev_hue/genotype_huehue_chr10/results
# B: huehuetenangensis + parviglumis
sbatch $H --export=ALL,ZEALGT_LAUNCH=$N/zealgt_dev_hue_parv,NXF_OPTS="-Xms1g -Xmx12g" \
  scripts/submit_head_job.sbatch hpc_dev --step genotype --input $S/huehue_parviglumis.csv $G \
  --outdir $N/zealgt_dev_hue_parv/genotype_huehue_parviglumis_chr10/results
# C: huehuetenangensis + mexicana, resuming run 1273053's session
sbatch $H --export=ALL,NXF_OPTS="-Xms1g -Xmx12g" \
  scripts/submit_head_job.sbatch hpc_dev --step genotype --input $S/huehue_mexicana.csv $G \
  --outdir $N/zealgt_dev/genotype_huehue_mexicana_chr10/results \
  -resume 05f75070-d26e-4647-943a-e7e45a898bae
```

Logs: `nf_work/zealgt_head_<job id>.log` per run; `.nextflow.log` in each launch directory.

## Estimates

| run | from                                                     | time     |
| --- | -------------------------------------------------------- | -------- |
| A   | diploperennis 1270808 (6 donors, 304 samples): 2.2 h     | ~1-2 h   |
| B   | mexicana 1273053: discovery ~0.7 h, union->ancestry ~2 h | ~2.5-3 h |
| C   | as B, discovery of two donors only                       | ~2-2.5 h |

- CPUs: `queueSize` 40 per run, tasks of 1-4 CPUs (4: the pools' `SAMTOOLS_MERGE`), measured peaks ~100-160 per run.
  Three runs plus the 9d regression (job 1323153) <= 4 x 160 = 640 CPUs, inside the short QOS's 768. Tasks past it
  queue; they do not fail.
- `/share`: 1273053 grew `frodrig4`'s usage by ~0.5 TB; B about as much, A and C less; within the group quota.
- Submitted together ~10:00: all done by ~13:00.

## Comparison (after the runs)

From each run's `genotype/union/` (per-donor tier-A VCFs, `chr10.union.vcf.gz`, `chr10.donor_alleles.vcf.gz`) and
`genotype/ancestry/<donor>.chr10.line_checks.tsv`; curve rule by `agent/genochr10/mex_rule/apply_curve_rule.py`.

For `Zh.0020_P3` and `Zh.0030_P4`, side by side in A, B, C:

1. tier-A sites (the same in all three: discovery is per donor);
2. union size;
3. union-ALT markers (`donor_alleles` GT=1), split into own tier-A and gap-filled sites;
4. line checks: segments per line (median, max), ALT % in REF/HET/ALT segments; curve rule (`decisions.md`,
   2026-10-11) pass or fail;
5. class shares of line genotypes against BC2S2 (HET 6.25 %, donor 9.4 %);
6. SNP50K segments for the same lines (`zealhmm/data/zeal/rtiger_50K_calls.csv`: all 61 Zh lines have chr10 calls).

Partner taxon:

- B: union size with and without Zh (40 Zv donors' union vs B's); no parviglumis-only run exists, so B's parviglumis
  line checks are a first baseline, not a comparison.
- C: union size vs 1273053 (42 donors); line checks of the 42 mexicana donors vs 1273053 (curve-rule pass/fail per
  donor, segments per line, ALT % per state).

Reading: Zh joins a taxon if its line checks there match A's or better and the partner's donors keep their 1273053
results; otherwise it keeps its own union.

## Done when

- The three runs succeed; the comparison table here; the user's decision on Zh's union.
- Time and peak per run in `docs/RESOURCES.md`.
- `nf_work/zealgt_dev_hue`, `nf_work/zealgt_dev_hue_parv` and C's `work/` on the user's cleanup list once results are
  kept.
