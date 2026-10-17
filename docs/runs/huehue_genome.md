# Run plan: huehuetenangensis alone, whole genome (variant_calling, then ancestry per chromosome and per genome)

DRAFT, 2026-10-16.

## Why

User, 2026-10-16: "a genome-wide run should run in a smaller whole-genome data set"; "huehue alone". The first
genome-wide run of the split pipeline (Milestone 9e), before diploperennis: `variant_calling` on chr1-chr10, then
`ancestry` from its counts sheet with `--ancestry_fit chromosome` and `genome`. A shakedown, not final calls: with two
donors the union and gap filling pool little evidence; on chr10, run A (alone) fragmented 2 samples that + parviglumis
or + mexicana cleaned (notebook 06). The production union is open decision 2.

## Inputs

- Sheet: `docs/runs/genotype_huehue_chr10/huehue.csv` (run A, 93 rows: 2 Zh donors, 9 BC1 pools, 61 lines, 23 B73
  checks), `b73_controls.csv` (`B73_ERR3288215`); sheet check job 1323750: every path absolute and present, every donor
  keeps a pool and a line over 0.05x. Rechecked in seconds before the submit (CRAMs on `/rsstu`).
- `--lowcopy_bed ZEAL/reference/lowcopy_chr1-10.bed` (genome pilot, sha256 next to it), `--check_sites
bzeaseq/nilhmm/vcf/HQ_BZEA.vcf.gz`, `--regions chr1,chr2,chr3,chr4,chr5,chr6,chr7,chr8,chr9,chr10`.
- `ancestry`: the counts sheet the first run publishes (`results/samplesheets/huehue.counts.csv`), `--rigidity_mb 1`
  (default), the bundled v5 map.

## Before the run

- Code: `origin/dev` at `12dae9a` (Milestone 9e merged); hazel setup checks of 9e passed (jobs 1343306, 1343307). No
  new code, so no stub and no CodeRabbit.
- Checkout: `ZEAL/zealgt` is on `runs-genotype-huehue-chr10` (merged as PR #60), clean, used by no job; it moves to
  `origin/dev` (your OK): `git -C /rsstu/users/r/rrellan/BZea/ZEAL/zealgt fetch -q origin && git -C ... checkout --detach origin/dev`.

## Runs

`hpc_dev`, one cold launch directory per run under `nf_work/`; the two ancestry runs start when variant calling
succeeds (`--dependency=afterok`) and run side by side.

```
cd /rsstu/users/r/rrellan/BZea/ZEAL/zealgt
B=/rsstu/users/r/rrellan/BZea
S=$B/ZEAL/zealgt/docs/runs/genotype_huehue_chr10
N=/share/maize/frodrig4/nf_work
V=$N/zealgt_dev_hue_genome
# variant calling, chr1-chr10
vc=$(sbatch --parsable --partition=compute --qos=normal --time=12:00:00 --mem=16G \
  --export=ALL,ZEALGT_LAUNCH=$V,NXF_OPTS="-Xms1g -Xmx12g" \
  scripts/submit_head_job.sbatch hpc_dev --step variant_calling --input $S/huehue.csv \
  --b73_controls $S/b73_controls.csv --lowcopy_bed $B/ZEAL/reference/lowcopy_chr1-10.bed \
  --check_sites $B/bzeaseq/nilhmm/vcf/HQ_BZEA.vcf.gz --regions chr1,chr2,chr3,chr4,chr5,chr6,chr7,chr8,chr9,chr10 \
  --outdir $V/results)
# ancestry, per chromosome and per genome, from the counts sheet
for fit in chromosome genome; do
  sbatch --parsable --dependency=afterok:$vc --qos=short --time=02:00:00 --mem=8G \
    --export=ALL,ZEALGT_LAUNCH=${V}_anc_$fit \
    scripts/submit_head_job.sbatch hpc_dev --step ancestry --input $V/results/samplesheets/huehue.counts.csv \
    --ancestry_fit $fit --outdir ${V}_anc_$fit/results
done
```

Logs: `nf_work/zealgt_head_<job id>.log` per run; `.nextflow.log` in each launch directory.

## Estimates

| run                  | from                                                                                                                                  | time    |
| -------------------- | ------------------------------------------------------------------------------------------------------------------------------------- | ------- |
| variant calling      | run A, chr10 alone: 48 min (job 1323812); ten regions in one run, discovery per donor x region in parallel, chr1 twice chr10's length | ~2-4 h  |
| ancestry, chromosome | 20 RTIGER fits (2 donors x 10), as chr10's                                                                                            | minutes |
| ancestry, genome     | 2 fits over ~10x chr10's markers; `CALL_ANCESTRY` 1 cpu, 2 GB, 1 h are placeholders; a failure on memory or time is the measurement   | <1 h    |

- `/share`: run A 3.9 GB for chr10, so ~40 GB in `work/`; published counts ~0.3 GB (61 lines x ~4.5 MB compressed).
- Submitted at ~09:00: all done by ~13:00.

## Checks after the runs (bugs, not accuracy)

1. Every region succeeded; per donor and chromosome: tier-A sites, union sites, union-ALT markers, lines counted.
2. chr10 against run A (`nf_work/zealgt_dev_hue/genotype_huehue_chr10/results/genotype/union/`): union and donor
   alleles records; differences are CRISP run-to-run variation (Milestone 9d) or a bug.
3. Ancestry, chromosome vs genome fit, per donor: rigidity, lines dropped, donor segments per line (median, max), the
   curve rule (`decisions.md` 2026-10-11) pass/fail, and the ALT % in HET and ALT segments (line checks).
4. Genome-wide paintings of the 61 lines: SNP50K calls (`zealhmm/data/zeal/rtiger_50K_calls.csv`, all chromosomes)
   beside both fits.
5. `CALL_ANCESTRY` time and peak memory of the genome fit into `docs/RESOURCES.md`.

## Done when

- The three runs succeed; checks 1-5 in Attempts here.
- `nf_work/zealgt_dev_hue_genome*` on your cleanup list once the results are kept.
