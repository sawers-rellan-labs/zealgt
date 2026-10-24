# Run plan: variant calling and ancestry for every donor, whole genome (Milestone 9h method)

DRAFT, 2026-10-24. Submitted only after the user merges Milestone 9h. Model: `variant_calling_production.md`
(run 1367152, branch `runs-variant-calling-production`).

## Why

User, 2026-10-24, on the Milestone 9h spec: "this looks good make a handover for the next session to build test and
send the genomewide run". The comparison against SNP50K on the genome is the spec's "Not in this milestone" item:
mexicana EN chr1, PROLIF chr4, STPI chr2, KINKI chr2; diploperennis DTA, PH.

## Scope

- `--step variant_calling` with the Milestone 9h method (`docs/milestones/09h_discovery_redesign.md`), then
  `--step ancestry` on its counts sheet; chr1-chr10; `hpc_prod`.
- Ancestry per chromosome: `--ancestry_fit chromosome` and `--rigidity_mb 1` are the defaults, and `decisions.md` sets
  nothing else. A genome fit is not planned; if wanted later, `CALL_ANCESTRY` needs 48 GB for Zd.0010_P2 and
  Zd.0010_P3 (exit 137 at 16 GB, run 1387871).
- Results go to a new folder; run 1367152's `ZEAL/variant_calling` (25 GB) stays as it is.

## Inputs

- Run 1367152's sheet, copied unchanged (sha256 `85bfb1ac...`, as on hazel) into
  `docs/runs/variant_calling_ancestry_genome/samplesheet.csv` (2,173 rows), with `b73_controls.csv` (`B73_ERR3288215`):

  | taxon             | donors | BC1 | lines |
  | ----------------- | ------ | --- | ----- |
  | mexicana          | 42     | 163 | 722   |
  | parviglumis       | 40     | 168 | 606   |
  | diploperennis     | 6      | 25  | 256   |
  | luxurians         | 5      | 19  | 121   |
  | huehuetenangensis | 2      | 9   | 61    |
  | total             | 95     | 384 | 1,766 |

  Plus 23 `check` rows. Sheet check of 2026-10-17 (job 1349174): every path absolute and present; every donor keeps a
  pool and a line at or above 0.05x; 17 lines under the floor.

- `--b73_checks /rsstu/users/r/rrellan/BZea/ZEAL/reference/b73_checks_qcpass.csv`: 21 IDs, each a `check` row of the
  sheet; the sheet's other two checks, PN3_SID236 and PN5_SID468, are the ones left out (checked 2026-10-24).
- `--known_sites /rsstu/users/r/rrellan/BZea/ZEAL/reference/wideseq_sites_biallelic_snps.vcf.gz` (+ `.tbi`), present.
- `--lowcopy_bed /rsstu/users/r/rrellan/BZea/ZEAL/reference/lowcopy_chr1-10.bed`.
- Parameters: `docs/runs/variant_calling_ancestry_genome/params.yaml`; regions and outdir on the command line (below).
  Run config `run.config`: `queueSize = 400`, as run 1367152.

## The file quota: one run or two (OPEN, the user's choice)

`/share` group `maize` (Share01, `mmlsquota`, 2026-10-24): 10.2 of 20 TiB and **692,112 of 1,000,000 files**;
`frodrig4` owns 122,283 of those files. Space is not the limit; the file count is:

- Files per task: 23.4 in the chr10 check's `work/` (27,113 entries, 1,159 tasks), 22.9 in run 1367152 (the group
  count rose 413k -> 817k for 17,678 tasks). This run has ~19,600 variant-calling tasks: **~460k files** until
  `cleanup` at the end.
- One run needs the group at or under ~480k files at submission; it is at 692k, and removing the 2026-10-23/24 test folders (`nf_work/nb3*`-`nb4*`,
  `m09h_chr10_check`; the user's cleanup list) frees ~50k.
  The other ~570k files belong to other group members.

Options (mine):

1. **Two variant-calling runs, chr1-chr5 then chr6-chr10** (proposed): each ~10,000 tasks, ~230k files; the group stays
   under ~870k after the cleanup list. Every step after `FILTER_BC1` is per region (the union, gap filling, the depth
   filter over all donors), so the results equal one run's (CRISP's run-to-run variation aside, Milestone 9d). Cost:
   `FILTER_BC1` runs twice (+55 CPU-h, ~25 min), two counts sheets and two output folders.
2. One run, after the group frees ~250k files or OIT raises the file quota.

The commands below are option 1. For option 2: one variant-calling run with `--regions chr1,...,chr10 --outdir $O`,
then one ancestry run.

## Runs

Checkout `ZEAL/zealgt_prod` (now `c15330a`, branch `runs-variant-calling-production`) at a tag of `dev` after the
merge, e.g. `vc-9h-genome-<date>`. Head jobs on the normal QOS, 16 GB, `NXF_OPTS="-Xms1g -Xmx12g"`. Variant calling in
the default launch directory `nf_work/zealgt_prod`; ancestry in `nf_work/zealgt_prod_ancestry`, so ancestry of the
first half runs beside variant calling of the second.

1. Setup checks at the tag (`docs/running.md` "Stubs on hazel"): one job, every process's stub at once plus `nextflow
config` and `inspect` with this run's parameters:
   `sbatch --export=ALL,ZEALGT_REPO=$C,PARAMS=$C/docs/runs/variant_calling_ancestry_genome/params.yaml,PROFILE=hpc_prod scripts/run_hazel_tests.sbatch`.
   No slice: the tag adds docs to the code tested in Milestone 9h.
2. The chain, one submission (four head jobs, each after the one it reads):
   ```
   C=/rsstu/users/r/rrellan/BZea/ZEAL/zealgt_prod; R=$C/docs/runs/variant_calling_ancestry_genome
   O=/rsstu/users/r/rrellan/BZea/ZEAL/variant_calling_ancestry_genome; A=/share/maize/frodrig4/nf_work/zealgt_prod_ancestry
   H="--partition=compute --qos=normal --mem=16G --no-requeue --parsable"
   E="ALL,ZEALGT_REPO=$C,NXF_OPTS=-Xms1g -Xmx12g"
   v1=$(sbatch $H --time=1-00:00:00 --export="$E" $C/scripts/submit_head_job.sbatch hpc_prod \
     -params-file $R/params.yaml -c $R/run.config --regions chr1,chr2,chr3,chr4,chr5 --outdir $O/chr1-chr5)
   v2=$(sbatch $H --time=1-00:00:00 --dependency=afterok:$v1 --export="$E" $C/scripts/submit_head_job.sbatch hpc_prod \
     -params-file $R/params.yaml -c $R/run.config --regions chr6,chr7,chr8,chr9,chr10 --outdir $O/chr6-chr10)
   a1=$(sbatch $H --time=12:00:00 --dependency=afterok:$v1 --export="$E,ZEALGT_LAUNCH=$A" $C/scripts/submit_head_job.sbatch hpc_prod \
     --step ancestry --input $O/chr1-chr5/samplesheets/samplesheet.counts.csv --outdir $O/chr1-chr5)
   a2=$(sbatch $H --time=12:00:00 --dependency=afterok:$v2:$a1 --export="$E,ZEALGT_LAUNCH=$A" $C/scripts/submit_head_job.sbatch hpc_prod \
     --step ancestry --input $O/chr6-chr10/samplesheets/samplesheet.counts.csv --outdir $O/chr6-chr10)
   ```
   The two ancestry runs share their launch directory, so the second waits for the first.

## Estimates

From the chr10 check (jobs 1532055-56: 48 donors, 188 BC1 pools; `docs/RESOURCES.md`), scaled to 95 donors and 384
BC1 pools; genome / chr10 per process from run 1367152's trace (13-14.5; 14.1 for new processes), `FILTER_BC1`
already whole-genome. Script and table: `agent/m09h/plan/estimate_genome.py`, `estimate_genome.tsv`.

| process (9h)                                                     | tasks, genome | CPU-h, genome | longest (chr10 check) | 1367152: tasks, CPU-h |
| ---------------------------------------------------------------- | ------------- | ------------- | --------------------- | --------------------- |
| `FILTER_BC1`                                                     | 384           | 55            | 20.6 min              | 384, 120              |
| `CRISP`                                                          | 950           | 184           | 13.6 min (chr1 ~26)   | 950, 207              |
| `COUNT_UNION`                                                    | 3,860         | 61            | 2.2 min               | 3,860, 69             |
| `SAMTOOLS_MERGE`, `SAMTOOLS_ADDREPLACERG`                        | 970 each      | 85            | 4.5 min               | 1,940, 74             |
| `UNION_TIERS`                                                    | 950           | 24            | 1.4 min               | 950, 43               |
| `BCFTOOLS_MPILEUP`                                               | 1,900         | 23            | 0.8 min               | 1,900, 16             |
| `COUNT_LINES`                                                    | 950           | 18            | 2.6 min               | 950, 22               |
| `FILTER_WITNESS`                                                 | 950           | 16            | 1.8 min               | 950, 33               |
| others (`CRISP_CONTIGS`, `KNOWN_SITES` etc., 950 or 10 per kind) | 7,690         | 13            | <= 1.3 min            | 5,794, 23             |
| variant calling, all                                             | 19,574        | ~480          |                       | 17,678, 606           |
| ancestry (`CALL_ANCESTRY`, `ANCESTRY_VCF_INDEX` 950 each, grid)  | 1,910         | ~2            | 0.4 min               | -                     |

- **Tasks**: ~19,600 variant calling, ~1,900 ancestry. Option 1 adds 384 (`FILTER_BC1` twice): ~10,000 per half.
- **Slurm submissions** (`submitRateLimit` 20/min; arrays of 20 count once): variant calling ~1,050 (more with
  partial arrays), >= ~55 min of submitting spread over the run; ancestry 1,910 single jobs (`CALL_ANCESTRY` and
  `ANCESTRY_VCF_INDEX` have no arrays in `hpc_prod`), so **>= 96 min** by the rate limit alone, ~48 min per half.
- **Wall** (mine): 1367152 took 2 h 51 min with `FILTER_BC1` up to 50.6 min and chr1 CRISP 38 min; here 20.6 min and
  ~26 min. Option 1: ~1.5-2.5 h per variant-calling half, ancestry ~1 h per half after it: **~4-6 h** for the chain.
  Option 2: ~2.5-3 h, then ancestry ~1.7-2 h.
- **Peak `/share`** (mine): the chr10 check's `work/` was 154 GB, ~99 GB of it `FILTER_BC1`'s copies (written bytes);
  the rest (~55 GB) scales by donors and genome/chr10 to ~1.5 TB, the copies by pools to ~0.2 TB. One run ~1.7 TB;
  halves ~1.1 TB (chr1-chr5, 61 % of the union sites) and ~0.8 TB; ancestry small. Group space free: 9.8 TiB.
- **CPU-h**: ~480 variant calling (~535 with option 1), ~2 ancestry; 1367152 used 606.
- **Memory**: every 9h process at most 0.72 of its request on chr10; chr1 holds ~2x chr10's sites, and the limits that
  could matter (`CRISP` 2 GB, `COUNT_LINES` 4 GB, `FILTER_SITE_DEPTH` 4 GB) double on a retry.
- **Outputs on `/rsstu`**: ~25 GB as 1367152, plus ancestry; 11 TB free.

## Cleanup of intermediates

As `variant_calling_production.md`: `hpc_prod` has `cleanup = true`, so each successful run deletes its own `work/`;
outputs are copied to `/rsstu` first. A failed run keeps its `work/` for `-resume` (same launch directory); removing a
failed attempt's `work/` is the user's. The supervising agent stops and asks when the group passes 950k files or
`/share` `work/` passes 3 TB.

## Checks after the runs (bugs, not accuracy)

1. Every region succeeded; the counts sheets have 950 rows in all (95 donors x 10), each count VCF the donor's 1,749
   lines in all; `markers_per_chrom.tsv` per donor and chromosome, none at 0.
2. chr10 against the Milestone 9h chr10 check (42 mexicana, 6 diploperennis donors): markers per donor, and the same
   criteria as the report. More markers here would support my reading of the OPEN LOD question (the all-taxa union).
3. Time and peak memory per process into `docs/RESOURCES.md`.

## Judging the method (the user's criteria, against SNP50K)

- Per chromosome, each taxon: class-separation MSE, genotype classes against BC2S2, segments per line.
- QTL genome-wide, family covariate: mexicana EN chr1, PROLIF chr4, STPI chr2, KINKI chr2; diploperennis DTA, PH.
  SNP50K from the zealhmm per-taxon scans (`results/sim/zeal/rqtl/zeal_*_scanone_by_taxon.csv`), rescanned with the same
  model as this run's genotypes.

## Order

1. The user merges Milestone 9h (this plan rides in its PR) and chooses option 1 or 2.
2. The test folders' cleanup, by the user; the group file count read again (`/usr/lpp/mmfs/bin/mmlsquota -g maize gpfsHPCcommon2`).
3. Tag, checkout on hazel, setup checks (step 1 of "Runs").
4. The chain, one submission, unattended.

## Attempts

None yet.
