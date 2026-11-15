# Run plan: variant calling for every donor, whole genome (production)

DRAFT, 2026-10-16. Rescopes `agent/ancestry_production_draft_20261006.md` (on hold since 2026-10-06), which ran
discovery and ancestry as one step; that draft stays as the record.

## Why

User, 2026-10-16: "now that I have decoupled variant discovery from ancestry, that plan should scope to variant
discovery". Milestone 9e split the step (`decisions.md` 2026-10-16): "the only thing that I need genome-wide are the
counts; the variant discovery can be done once and then we can fiddle with the HMM".

## Scope

- `--step variant_calling` (discovery, union, gap filling, each line's counts at its donor's markers), chr1-chr10,
  ending at the published counts and the counts sheet `samplesheets/<input>.counts.csv`.
- Out of scope: `--step ancestry` (per chromosome or genome fit, rigidity); later runs read this plan's counts sheets.
- What changed since the old draft: every ZEAL sample is aligned (waves 1-24, last 2026-10-16), so the alignment stage
  and its waves leave the plan; `--regions` runs every chromosome in one run.

## Inputs

- Samples (`meta/samples.csv`, not excluded, landraces out), each with a CRAM in `ZEAL/alignment/cram/`:

  | taxon             | donors | BC1 | lines |
  | ----------------- | ------ | --- | ----- |
  | mexicana          | 42     | 163 | 722   |
  | parviglumis       | 40     | 168 | 606   |
  | diploperennis     | 6      | 25  | 256   |
  | luxurians         | 5      | 19  | 121   |
  | huehuetenangensis | 2      | 9   | 61    |
  | total             | 95     | 384 | 1,766 |

  Plus the 23 B73 checks of the earlier sheets (12 `B73-bulk`, which the check filter reads, and 11 `B73`) and
  `b73_controls.csv` (`B73_ERR3288215`). `PN17_SID1574` (`Zx.0390_P1`, no BC1 pool) stays out, as in run 1273053.

- `--lowcopy_bed ZEAL/reference/lowcopy_chr1-10.bed`, `--check_sites bzeaseq/nilhmm/vcf/HQ_BZEA.vcf.gz`,
  `--regions chr1,...,chr10`.
- One input sheet with every donor (the union pools every donor in the run's sheet):
  `docs/runs/variant_calling_production/samplesheet.csv` (2,173 rows) and `b73_controls.csv`, written by
  `agent/vc_prod/write_sheet.py` from `meta/samples.csv`. Every row of the earlier run sheets in `docs/runs/` is in it
  unchanged (`agent/vc_prod/compare_sheets.py`); the luxurians rows are new. Sheet check on hazel (paths present, each
  donor keeps a pool and a line over 0.05x), job 1349174 (2026-10-17): 2,173 rows, every path absolute and present
  (`b73_controls.csv` too); every donor keeps a pool and a line at or above 0.05x. 17 lines under the floor (dropped by
  the pipeline, their donors keep other lines): 7 Zx (as in run 1273053), 3 Zd, 5 Zv, 2 Zl.

## Runs

One `variant_calling` run over every donor (decision 1); it publishes the counts and one counts sheet.
Head job on the normal QOS, 16 GB, `NXF_OPTS="-Xms1g -Xmx12g"`, `hpc_prod` (decision 3), parameters in
`docs/runs/variant_calling_production/params.yaml` (outputs in `ZEAL/variant_calling`).

- Checkout `ZEAL/zealgt_prod` (a fresh clone; the old one was removed in cleanup) at tag `vc-prod-20261017`; launch
  folder `nf_work/zealgt_prod` (default).
- Setup checks (`docs/running.md` "Stubs on hazel"), one job from that checkout, every process's stub at once on
  `hpc_prod` beside the run's `nextflow config` and `inspect`; no chained pipeline stub:
  `sbatch --export=ALL,ZEALGT_REPO=$C,PARAMS=$C/docs/runs/variant_calling_production/params.yaml scripts/run_hazel_tests.sbatch`.
- The run (`C=/rsstu/users/r/rrellan/BZea/ZEAL/zealgt_prod`):
  ```
  sbatch --partition=compute --qos=normal --time=1-00:00:00 --mem=16G --no-requeue \
    --export=ALL,ZEALGT_REPO=$C,NXF_OPTS="-Xms1g -Xmx12g" \
    $C/scripts/submit_head_job.sbatch hpc_prod -params-file $C/docs/runs/variant_calling_production/params.yaml
  ```

## Estimates

Measured on chr10 with 88 donors (diploperennis, parviglumis, mexicana; `genotype_diplo_parviglumis_mexicana_chr10`,
2026-10-16, trace `execution_trace_2026-10-16_12-30-36.txt`; 727,756 union sites, 3,199 tasks, 28.2 CPU-h with
ancestry), scaled to 95 donors and chr1-chr10. Genome / chr10 is 14.1 by low-copy Mb and 17.1 by union sites (the
huehuetenangensis genome run, job 1343856: 1,168,623 vs 68,177); ~15 below.

| process (chr10, 88 donors)                 | tasks  | longest      | CPU-h | peak RSS | production (95 donors, genome)            |
| ------------------------------------------ | ------ | ------------ | ----- | -------- | ----------------------------------------- |
| `CRISP`                                    | 82     | 16.1 min     | 12.2  | 0.55 GB  | ~200 CPU-h; chr1 tasks ~35-45 min         |
| `COUNT_UNION`                              | 358    | 3.1 min      | 4.7   | 0.26 GB  | ~75 CPU-h                                 |
| `UNION_TIERS`                              | 88     | 2.5 min      | 2.6   | 1.80 GB  | chr1 ~4 GB (2.2 x chr10's sites): 8 GB    |
| `SAMTOOLS_MERGE`, `_ADDREPLACERG`          | 164    | 3.7 min      | 4.3   | 0.90 GB  | ~70 CPU-h                                 |
| `COUNT_LINES` (per line, pre-9f)           | 1,569  | 0.2 min      | 1.1   | 0.25 GB  | 950 tasks after 9f; memory from 9f test 6 |
| `FILL_DONOR_ALLELES`                       | 88     | 0.6 min      | 0.6   | 0.75 GB  | chr1 ~1.7 GB                              |
| `UNION_SITE_COUNTS`, `DONOR_ALLELES_MERGE` | 1 each | 3.1, 3.6 min | 0.1   | 0.72 GB  | chr1 ~1.6 GB, ~8 min                      |

- CPU: ~400-500 CPU-h; tasks ~18,000 (Milestone 9f: one `COUNT_LINES` per donor and region; ~41,000 without).
- Wall: ~4-6 h on `hpc_prod` (`queueSize` 80), ~8-10 h on `hpc_dev` (40); the longest task CRISP on chr1. Milestone 9f
  lets chr2-chr10 go on while chr1's CRISP runs (huehuetenangensis genome: 1 h 41 min before, ~58 min after).
- Memory (set in 9f): `UNION_TIERS` 8 GB (chr1 ~4 GB); `COUNT_LINES` 4 GB for a donor's lines in one task (up to 64).
- `/share`: `work/` of 9f test 6 (huehuetenangensis genome-wide, 2 donors, 70 samples) was 51 GB; scaled to 95 donors
  ~1.5-2.5 TB; `cleanup = true` (`hpc_prod`) deletes `work/` only when the run succeeds, so the whole of it stays until
  then (attempt 4 held 1.4 TB when it stopped). Milestone 9g's filtered copies for CRISP add ~1.9 TB (the 384 BC1 CRAMs
  are 1,397 GB, the 1,766 line CRAMs behind the witness pools 544 GB): peak ~3.5 TB.
- Stop point for the supervising agent (user, 2026-10-17): `work/` above 6 TB on `/share` (the ~3.5 TB peak plus
  headroom): stop resuming and ask the user; removing a failed attempt's `work/` is the user's.
- Published counts: ~77 GB plain, ~8 GB compressed (`-Oz`) for the whole population, on `/rsstu`.

## Order

1. Done in Milestone 9f: limits from the estimates above: `UNION_TIERS` 8 GB; `COUNT_LINES` 4 GB (0.84 GB peak with 35
   lines in 9f test 6, doubling on retry).
2. Done, merged 2026-10-17 (PR #64): Milestone 9f (`docs/milestones/09f_efficiency_before_production.md`) merged, all its changes debugged before the run
   (user, 2026-10-16: "we need to debug all this changes before sending the whole genome run"): group sizes for the
   discovery and union barriers, CRISP memory, one count VCF per donor and region, short Slurm job names; its test 6
   reruns huehuetenangensis genome-wide on `hpc_dev`.
3. The sheet written and checked (every donor, luxurians included).
4. Hazel setup checks at the production tag (parallel process stubs, config, containers). Done: job 1349204
   (2026-10-17, `ZEAL/zealgt_prod` at `vc-prod-20261017`), 26 of 26 process tests, config and `inspect` (29 containers)
   passed in 4 min 20 s. No slice: the tag adds docs and sheets only to `dev`; 9f test 6 ran real data genome-wide.
5. The run, one submission, unattended.

## Checks after the runs (bugs, not accuracy)

1. Every region of every run succeeded; per donor and chromosome: tier-A sites, union sites, union-ALT markers, lines
   counted.
2. chr10 against per-taxon chr10 runs: the earlier ones (`genotype_*_chr10.md`) were deleted with their `/share`
   folders (2026-10-17), so after this run one `--step variant_calling --regions chr10` run per taxon (mexicana,
   parviglumis, diploperennis, luxurians, huehuetenangensis), `hpc_dev`, sheets = each taxon's rows of this run's sheet
   plus the same checks (user, 2026-10-17); then union and donor alleles, and per donor the
   union-ALT markers its taxon discovered, kept or lost; differences are CRISP run-to-run variation (Milestone 9d), the
   union's other donors, or a bug.
3. The counts sheet has a row for every donor and region, its count VCF holding every line of the donor.
4. Time and peak memory per process into `docs/RESOURCES.md`.

## Decisions (user, 2026-10-16)

1. **Union design: one union of all donors**, one run. Gap filling's prior already comes from all
   other donors (Milestone 8, Eq. `eb`); on chr10, huehuetenangensis alone fragmented 2 samples that + parviglumis or +
   mexicana cleaned (notebook 06). With 94 other donors the prior `pi = (2 mu_d + k) / (2 + m)` nears `k / m`, so
   alleles of one taxon get a smaller prior than in a per-taxon union: fewer of their gaps filled, some own sites
   re-scored to missing. Check: chr10 of the all-donor union against the per-taxon chr10 runs (check 2). If own-taxon
   markers are lost, a subset of each donor's markers to sites its taxon discovered (`SRC=own` in some donor of the
   taxon, bcftools on `donor_alleles.vcf.gz`) before `--step ancestry`; not built.
2. **Luxurians in**: 5 donors, 19 BC1 pools, 121 lines.
3. **`hpc_dev` until production**: the debugging runs (9f's tests) on `hpc_dev`; the production run on
   `hpc_prod` (frozen tag, `cleanup = true`, outputs on `/rsstu`).
4. **Ancestry afterwards (not this plan): 1 Mb rigidity over the all-donor union's markers**, expected denser per Mb than
   a per-taxon union's (huehuetenangensis alone needed 5 Mb and the genome fit to reach SNP50K-level fragmentation: median
   7.5 and 7 donor segments per line, jobs 1346167-1346168).

## Done when

- Every run succeeds; checks 1-4 in an Attempts section here; the counts sheets' paths in this plan.

## Attempts

1. Job 1349242 (2026-10-17 01:58, tag `vc-prod-20261017`, session `f9ec7cac`): cancelled by the user at 02:04
   (Nextflow exit 1). `hpc_prod` had no job arrays for variant calling: with `submitRateLimit` 20/1min the ~17,500
   single jobs would have taken ~14.5 h to submit.
2. Job 1349425 (2026-10-17 02:14, tag `vc-prod-arrays-20261017`, `-resume f9ec7cac`): job arrays of 20 for the
   per-donor and per-sample variant-calling processes in `hpc_prod` (PR #65; user: "I want the array jobs
   implemented"). Setup checks at the tag, job 1349371: 26 of 26 process tests, config and `inspect` passed (4 min 38 s).
3. Job 1350342 (2026-10-17 02:38, tag `vc-prod-arrays-20261017b`, `-resume f9ec7cac`): attempt 2 stopped to rerun with
   `queueSize = 400` in `docs/runs/variant_calling_production/run.config` (`hpc_prod`'s 80 held the run at ~100-170
   CPUs; hazel allows ~768 running CPUs per user). Failed at 03:42 (1 h 05 min): CRISP `Zl.0020_P3_chr1` segfaulted at
   1.79 of 2 GB (job 1353412_10); exit 1, so not retried.
4. Job 1358990 (2026-10-17 03:50, tag `vc-prod-arrays-20261017c`, `-resume f9ec7cac`): CRISP 6 GB in the run config.
   Failed at 04:32 (43 min): the same task segfaulted at 1.83 GB (job 1359025_14), so memory was not the cause.
   Diagnosis (`agent/crisp_debug/`): a use-after-free in CRISP 1a9027e. `evaluate_OPE_readpair`
   (`parsebam/variant.c:148`) lets a primary R1 and its supplementary record (0x800) both claim R2, and
   `free_read_queue` then writes into the freed R2 (valgrind). Such reads are in every CRAM checked (108 in this
   witness on chr1, 4-20 per BC1 CRAM); the other tasks survived by luck. `samtools view -F 0x800` on the five CRAMs
   let the full chr1 task finish (229,627 calls vs 234,635; the lost calls have lower QUAL and sit nearer TE edges, job
   1365010). Reported upstream: https://github.com/vibansal/crisp/issues/35. Fix: Milestone 9g (no supplementary
   records in variant calling); the run restarts cold after it merges (`work/` deleted in cleanup).
5. Job 1367152 (2026-10-17, tag `vc-prod-9g-20261017`, cold: `work/` deleted): Milestone 9g (PR #66), no
   supplementary records in variant calling; run config `queueSize = 400` only; head job 16 GB, `-Xmx12g`. Started
   12:28 (node c207n01, session `9a313da1`). **Succeeded**: pipeline completed 15:19:49 (2 h 51 min), cleanup of `work/`
   until 15:33 (head job 3 h 04 min, exit 0, MaxRSS 16.0 GB = the request). 17,678 tasks, all COMPLETED at the first
   attempt (no retry, no failure), 606 CPU-h. Peak on `/share`: 3.22 TB for `frodrig4` in all (`work/` 2.67 TB at 1 h,
   when `du` still finished); group file count peaked at 817,053 of 1 M; after cleanup 23 GB.

## Results

- Outputs in `ZEAL/variant_calling/` (`/rsstu/users/r/rrellan/BZea/ZEAL/variant_calling`): counts sheet
  `samplesheets/samplesheet.counts.csv` (950 rows = 95 donors x 10 chromosomes; columns donor, region, counts,
  markers, union), count VCFs and markers in `variant_calling/counts/<donor>/<chr>/`, unions and donor alleles in
  `variant_calling/union/`, discovery in `variant_calling/discovery/`; trace
  `pipeline_info/execution_trace_2026-10-17_12-28-34.txt`.
- Checks 1 and 3 (job 1387272, table `variant_calling_production/checks_per_donor_region.tsv`): every region of the
  run succeeded; the counts sheet has a row for every donor and region and no other; every count VCF holds exactly the
  donor's lines at or above 0.05x (1,749 = 1,766 - the 17 under the floor; none missing, none extra); every donor and
  region has union-ALT markers. `Zx.0520_P4` has no tier-A site on any chromosome: it has one BC1 pool (as in
  `genotype_mexicana_chr10.md` and notebook 03); its markers (15,305-90,517 per chromosome) are all gap-filled.

  | chromosome | union sites | tier-A, donor median | union-ALT markers, donor median (min-max) | lines counted |
  | ---------- | ----------- | -------------------- | ----------------------------------------- | ------------- |
  | chr1       | 1,550,021   | 21,142               | 196,681 (50,448-373,398)                  | 1,749         |
  | chr2       | 1,489,395   | 23,572               | 206,524 (57,289-353,367)                  | 1,749         |
  | chr3       | 1,358,490   | 19,713               | 163,080 (71,259-341,612)                  | 1,749         |
  | chr4       | 1,202,608   | 15,640               | 164,546 (20,944-326,164)                  | 1,749         |
  | chr5       | 1,073,013   | 13,879               | 138,465 (19,379-258,658)                  | 1,749         |
  | chr6       | 734,301     | 10,208               | 73,698 (15,305-163,317)                   | 1,749         |
  | chr7       | 971,253     | 16,640               | 121,351 (34,334-245,316)                  | 1,749         |
  | chr8       | 913,816     | 11,234               | 104,009 (21,226-241,583)                  | 1,749         |
  | chr9       | 905,753     | 13,163               | 114,437 (17,790-208,312)                  | 1,749         |
  | chr10      | 779,916     | 11,719               | 107,973 (20,290-198,485)                  | 1,749         |

  | taxon             | donors | tier-A per donor, genome median | union-ALT markers per donor, genome median | lines counted |
  | ----------------- | ------ | ------------------------------- | ------------------------------------------ | ------------- |
  | mexicana          | 42     | 185,336                         | 1,464,234                                  | 715           |
  | parviglumis       | 40     | 108,368                         | 1,356,064                                  | 601           |
  | diploperennis     | 6      | 538,054                         | 1,419,232                                  | 253           |
  | luxurians         | 5      | 300,175                         | 1,333,147                                  | 119           |
  | huehuetenangensis | 2      | 631,761                         | 1,852,254                                  | 61            |

- Check 4: `docs/RESOURCES.md` "VARIANT_CALLING production, measured".
- Check 2 (approved by the user 2026-10-17, not yet submitted): sheets `variant_calling_production/chr10_<taxon>.csv`
  (each taxon's rows of the production sheet plus the 23 B73 checks; mexicana 908 rows, parviglumis 797,
  diploperennis 304, luxurians 163, huehuetenangensis 93), tag `vc-prod-9g-20261017-chr10` (the run's tag plus these
  sheets, docs only; checked out in `ZEAL/zealgt_prod`). Each run its own launch directory, `hpc_dev`, head 16 GB:
  ```
  C=/rsstu/users/r/rrellan/BZea/ZEAL/zealgt_prod; B=/rsstu/users/r/rrellan/BZea; N=/share/maize/frodrig4/nf_work
  for t in mexicana parviglumis diploperennis luxurians huehuetenangensis; do
    L=$N/zealgt_dev_chr10_$t; mkdir -p $L
    sbatch --parsable --partition=compute --qos=normal --time=12:00:00 --mem=16G --no-requeue \
      --export=ALL,ZEALGT_REPO=$C,ZEALGT_LAUNCH=$L,NXF_OPTS="-Xms1g -Xmx12g" \
      $C/scripts/submit_head_job.sbatch hpc_dev --step variant_calling \
      --input $C/docs/runs/variant_calling_production/chr10_$t.csv \
      --b73_controls $C/docs/runs/variant_calling_production/b73_controls.csv \
      --lowcopy_bed $B/ZEAL/reference/lowcopy_chr1-10.bed --check_sites $B/bzeaseq/nilhmm/vcf/HQ_BZEA.vcf.gz \
      --regions chr10 --outdir $L/results
  done
  ```
  Comparison afterwards per donor: tier-A shared, union-ALT markers of the taxon run kept, lost (site absent from the
  all-donor union, or present but not called ALT) and gained.
