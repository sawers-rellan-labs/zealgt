# Run plan: alignment of the remaining 35 mexicana donors

DRAFT (2026-10-11), for the user's choices below; nothing submitted.

## Why

User, 2026-10-11: "write the plan for the 35 mexicana donors". Step 7 of the chr10 plan: GENOTYPE on chr10 for all 43
mexicana donors (step 8) needs every mexicana BC1 pool and line aligned; 8 donors are (289 samples, union tests).

## Inputs and outputs

- Samples: every `meta/samples.csv` row with taxon mexicana, role `bc1_sample` or `nil`, not excluded, of the 35 donors
  with no CRAM yet: 597 samples (126 BC1 pools, 471 lines), 44 libraries; rows from the production demultiplexing
  sheets (`ZEAL/demultiplex/samplesheets/demultiplex_<NN>.csv`), unchanged.
- Raw FASTQ: 2,027 GB (bc1 1,584, bc2s3_batch1 303, bc2s3_batch2 140); largest sample 34 GB.
- Outputs: `--outdir /rsstu/users/r/rrellan/BZea/ZEAL/alignment`, beside the 404 CRAMs there: `cram/<sample_id>.cram`,
  `.crai` and CRAM QC (CollectWgsMetrics, samtools stats, mosdepth). CRAMs ~0.32 x raw (attempt 3: 45 GB from
  140 GB), so ~650 GB on `/rsstu` (13 TB free).

## Waves

`work/` peak was 8.2 x raw in attempt 3 (2 h 45 min, 38 samples, 140 GB raw, `/share` peak 1.39 TB). `/share` holds the
group's 20 TB (now 0.3 TB used). Samples are filled in sheet order up to a cap of `work/` peak (alignment is per sample,
so a library may span waves):

| cap per wave | waves | samples per wave | raw per wave | estimate per wave | all waves |
| ------------ | ----- | ---------------- | ------------ | ----------------- | --------- |
| 2 TB         | 9     | 12-270           | 147-244 GB   | ~3-5 h            | ~1.5-2 d  |
| 4 TB         | 5     | 25-392           | 89-488 GB    | ~5-9 h            | ~1.5-2 d  |

Estimates scale attempt 3's 140 GB in 2 h 45 min; the bc1 pools dominate raw size and time.

## Settings

- `hpc_prod`, `cleanup = true` (a wave's `work/` goes once it succeeded and published), worktree `ZEAL/zealgt_prod` at a
  new tag on `dev` 3b1b039, launch directory `nf_work/zealgt_prod`. Since attempt 3's tag (`align-pilot-20261005`,
  58100b6) the alignment modules and subworkflows are unchanged; `main.nf`, `nextflow.config` and `hpc_prod.config`
  gained GENOTYPE, and the alignment `SAMTOOLS_MERGE` selector became `.*FASTQ_ALIGN_MINIBWA:SAMTOOLS_MERGE` (same
  resources).
- One head job per wave, chained with `--dependency=afterok`, normal QOS, `--time=1-00:00:00`, `--no-requeue`: as the
  production demultiplexing (`scripts/submit_demultiplex_waves.sh`). `--no-requeue` because Slurm requeues a head job
  after a node failure (`JobRequeue = 1`) without `-resume`, so the wave would restart from zero and orphan its `work/`.
- Head job memory 16 GB, `NXF_OPTS="-Xms1g -Xmx12g"`, as attempt 3 (its MaxRSS equalled the request because the JVM
  grows into what it is given, not because it needed more). The chain script passes them; the stub checks `ReqMem`.
- MultiQC per wave: `multiqc/alignment/<input basename>/`, as the demultiplexing's read-QC report; now every run writes
  `multiqc/multiqc_report.html` and a wave would replace the last one's (and attempt 3's) report.
- Wave sheets in `docs/runs/alignment_mexicana35/alignment_<NN>.csv`, copied to `/share/maize/frodrig4/nf_work/
alignment_mexicana35/` for the run.

## Choices for the user

1. **Cap per wave: 2 TB** (as the production demultiplexing; leaves the group 18 TB). Rejected: 4 TB (fewer waves, same
   total time, twice the space held).
2. **Chain script: `scripts/submit_demultiplex_waves.sh` takes the step** (`--step alignment`, sheet prefix), renamed
   `scripts/submit_waves.sh`, passing `--mem`, `NXF_OPTS` and `--no-requeue`; the demultiplexing plan's recovery commands
   updated; reviewed with CodeRabbit before the run. Rejected: a second copy for alignment.
3. **A one-wave `-stub` chain on hazel first** (minutes): checks the new tag's `main.nf` and `hpc_prod` resource
   selectors on alignment, the chain script's change and the per-wave MultiQC path. Rejected: no stub (`main.nf`
   changed since attempt 3).
4. **MultiQC report per wave** (`main.nf` output path, as above). Rejected: one report rebuilt after the last wave.

## Supervision (a new session, from a handover)

- After the user's OK on the submission the waves run unattended. A background poller on the chain (`sacct` state,
  `/share` usage, ssh and stat timings) is the session's signal; the user watches the head logs.
- On a failed wave: `scancel` the pending waves (`afterok` never releases them), read the failed task's `.command.err`,
  resubmit from that wave with `RESUME=<session id>`; the failed attempt's `work/` goes on the user's removal list
  (`cleanup` deletes only what the successful run made). The session stops and asks on code fixes or if `/share` passes
  4 TB.
- Known and accepted: retries get the same time and memory (except Picard and MultiQC); scaled to the largest sample the
  tightest is `MINIBWA_MAP` memory, 12.9 of 16 GB. Three lines have 1-19 MB of raw FASTQ (the pilot aligned a 9.3 MB
  line); they fall under GENOTYPE's 0.05x floor anyway. Adversarial review: `agent/align35/adversarial_review.md`.

## Done when

- Every wave succeeded and `cleanup` emptied its `work/`; `/share` back to its level before the run.
- 597 new CRAMs with index and CollectWgsMetrics in `ZEAL/alignment/cram/`; MEAN_COVERAGE per sample and per wave in the
  report; time and peak per wave in `docs/RESOURCES.md`.
