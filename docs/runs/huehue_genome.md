# Run plan: huehuetenangensis alone, whole genome, variant calling

DRAFT, 2026-10-16.

## Why

User, 2026-10-16: "a genome-wide run should run in a smaller whole-genome data set"; "huehue alone". The first
genome-wide run of the split pipeline (Milestone 9e), before diploperennis: `variant_calling` on chr1-chr10, ending at
the published counts and counts sheet. Scope (user, 2026-10-16): "now that I have decoupled variant discovery from
ancestry, that plan should scope to variant discovery"; the RTIGER fits on these counts (per chromosome, per genome)
are separate experiments, not part of this run. A shakedown, not final calls: with two
donors the union and gap filling pool little evidence; on chr10, run A (alone) fragmented 2 samples that + parviglumis
or + mexicana cleaned (notebook 06). The production union is open decision 2.

## Inputs

- Sheet: `docs/runs/genotype_huehue_chr10/huehue.csv` (run A, 93 rows: 2 Zh donors, 9 BC1 pools, 61 lines, 23 B73
  checks), `b73_controls.csv` (`B73_ERR3288215`); sheet check job 1323750: every path absolute and present, every donor
  keeps a pool and a line over 0.05x. Rechecked in seconds before the submit (CRAMs on `/rsstu`).
- `--lowcopy_bed ZEAL/reference/lowcopy_chr1-10.bed` (genome pilot, sha256 next to it), `--check_sites
bzeaseq/nilhmm/vcf/HQ_BZEA.vcf.gz`, `--regions chr1,chr2,chr3,chr4,chr5,chr6,chr7,chr8,chr9,chr10`.

## Before the run

- Code: `origin/dev` at `12dae9a` (Milestone 9e merged); hazel setup checks of 9e passed (jobs 1343306, 1343307). No
  new code, so no stub and no CodeRabbit.
- Checkout: `ZEAL/zealgt` is on `runs-genotype-huehue-chr10` (merged as PR #60), clean, used by no job; it moves to
  this branch, `runs-huehue-genome` (`origin/dev` plus this plan and its run config; your OK):
  `git -C /rsstu/users/r/rrellan/BZea/ZEAL/zealgt fetch -q origin && git -C ... checkout runs-huehue-genome`.

## Runs

`hpc_dev`, a cold launch directory under `nf_work/`.

```
cd /rsstu/users/r/rrellan/BZea/ZEAL/zealgt
B=/rsstu/users/r/rrellan/BZea
S=$B/ZEAL/zealgt/docs/runs/genotype_huehue_chr10
N=/share/maize/frodrig4/nf_work
V=$N/zealgt_dev_hue_genome
# variant calling, chr1-chr10
sbatch --parsable --partition=compute --qos=normal --time=12:00:00 --mem=16G \
  --export=ALL,ZEALGT_LAUNCH=$V,NXF_OPTS="-Xms1g -Xmx12g" \
  scripts/submit_head_job.sbatch hpc_dev --step variant_calling --input $S/huehue.csv \
  --b73_controls $S/b73_controls.csv --lowcopy_bed $B/ZEAL/reference/lowcopy_chr1-10.bed \
  --check_sites $B/bzeaseq/nilhmm/vcf/HQ_BZEA.vcf.gz --regions chr1,chr2,chr3,chr4,chr5,chr6,chr7,chr8,chr9,chr10 \
  --outdir $V/results -c $B/ZEAL/zealgt/docs/runs/huehue_genome.config
```

Logs: `nf_work/zealgt_head_<job id>.log` per run; `.nextflow.log` in each launch directory.

## Estimates

Run A's chr10 trace (job 1323812, `execution_trace_2026-10-16_09-22-06.txt`) per process, each chromosome's work scaled
by its low-copy Mb (`lowcopy_chr1-10.bed`: chr1 55.7, chr10 26.1, all ten 367.1 Mb; chr1 = 2.13 x chr10, genome =
14.1 x chr10), the B73 check filter once (`agent/hue_genome/estimate_genome.py`):

| process                  | longest task, chr10 | longest task, chr1 (est.) | CPU-h, genome | peak memory, chr10 |
| ------------------------ | ------------------- | ------------------------- | ------------- | ------------------ |
| `CRISP`                  | 14.7 min            | 31 min                    | 5.4           | 0.46 GB            |
| `SAMTOOLS_ADDREPLACERG`  | 1.8 min             | 3.8 min                   | 1.4           | 0.42 GB            |
| `SAMTOOLS_MERGE`         | 0.9 min             | 1.9 min                   | 1.5           | 0.69 GB            |
| `COUNT_UNION`            | 1.0 min             | 2.1 min                   | 1.2           | 0.24 GB            |
| `COUNT_LINES` (61 lines) | 0.1 min             | 0.2 min                   | 0.5           | 0.25 GB            |
| the other 19 processes   | < 1 min             | < 1.5 min                 | 1.0           | < 0.7 GB           |

- Variant calling: ~11 CPU-h, ~1,100 tasks at 40 at a time; chr1's chain ~42 min of compute plus the Slurm scheduling
  waits (run A: 48 min wall on a ~20 min chain): mostly Slurm's scheduling pass (~50 s per step, the cluster's).
  Nextflow finds a finished task within 5 s (grid `pollInterval` default, `AbstractGridExecutor.groovy:63` in
  26.04.6) and reads the queue every 1 min (`queueStatInterval`), 10 s in this run's config as in the hazel stubs; so ~1-1.5 h. Every process stays under its `hpc_dev` limits. Head job
  on the normal QOS, 12 h: a run that outlives the short QOS's 2 h is killed with its head job
  (`scripts/submit_head_job.sbatch`).
- `/share`: run A 3.9 GB for chr10, so ~40-55 GB in `work/`; published counts ~0.3 GB (61 lines x ~4.5 MB compressed).

## Checks after the run (bugs, not accuracy)

1. Every region succeeded; per donor and chromosome: tier-A sites, union sites, union-ALT markers, lines counted.
2. chr10 against run A (`nf_work/zealgt_dev_hue/genotype_huehue_chr10/results/genotype/union/`): union and donor
   alleles records; differences are CRISP run-to-run variation (Milestone 9d) or a bug.
3. The counts sheet: one row per line and region (61 x 10), every file present.
4. Time and peak memory per process into `docs/RESOURCES.md` (the estimates above against the trace).

## Done when

- The run succeeds; checks 1-4 in Attempts here.
- `nf_work/zealgt_dev_hue_genome*` on your cleanup list once the results are kept.

## Attempts

- 2026-10-16: variant calling head job 1343856 (started 20:38, normal QOS). Submitted with the earlier plan's two
  ancestry head jobs 1343857 (chromosome) and 1343858 (genome) behind it (`afterok`); out of scope since the plan was
  rescoped, to be cancelled by the user (`scancel 1343857 1343858`).
