# Milestone 8: alignment split

`FASTQ_ALIGN_MINIBWA` maps each sample's reads in chunks, then merges them back into one CRAM per sample before
duplicate marking. Outputs do not change: one CRAM per sample, one read group.

## Why (user, 2026-10-05)

"If the queue puts us in a 7 hour wait you can implement and debug the split before that queue starts." A full BC1
library is one map, clip and fixmate chain of several hours (6 h, 16 cpus in `hpc_prod`), so it must run on `compute` /
normal, where the 10 map tasks of job 1098401 got start estimates of 13:15-16:40 on submission at 00:27. Chunks under
2 h run on `compute_partners` / short, where our jobs start within a minute (sacct, frodrig4, 30 days: 11,088 jobs,
median 0.1 min).

## Inputs

- Per sample read pairs, after `--head` (unchanged).
- No new parameters, no samplesheet change.

## Outputs

Unchanged: `<sample_id>.cram` + `.crai`, one read group per sample (Milestone 2), and the CRAM QC files.

## Processes

Stage `FASTQ_ALIGN_MINIBWA`, every module from nf-core:

1. `SEQKIT_SPLIT2` (new, nf-core `seqkit/split2`): each sample's pairs into chunks of 50,000,000 pairs (`--by-size`,
   `ext.args`). The chunks are paired by part number and carry `groupKey(meta, <number of chunks>)`.
2. Per chunk, as today per sample: `MINIBWA_MAP` (read group from the sample's meta, so every chunk carries the same
   one), `FGUMI_CLIP`, `SAMTOOLS_FIXMATE`, `SAMTOOLS_SORT`.
3. `SAMTOOLS_MERGE` (new here, nf-core `samtools/merge`): the sample's sorted chunks, grouped with `groupTuple` on the
   `groupKey`, into one coordinate-sorted BAM.
4. `SAMTOOLS_MARKDUP`, `SAMTOOLS_INDEX`: per sample, unchanged.

Resources (`conf/hpc_prod.config`): `MINIBWA_MAP` and `PICARD_COLLECTWGSMETRICS` move from `compute` / normal to the
default `compute_partners` / short (Picard measured 42 min on the deepest BC1 CRAM, `docs/later/picard_fast_algorithm.md`).
Chunk resources measured on hazel.

## Files

- `subworkflows/local/fastq_align_minibwa/main.nf`: split, per-chunk chain, merge.
- `modules/nf-core/seqkit/split2/`, `modules/nf-core/samtools/merge/`: installed.
- `conf/modules.config` (`SEQKIT_SPLIT2` `ext.args`), `conf/hpc_dev.config`, `conf/hpc_prod.config`, `docs/RESOURCES.md`.

## Choices this spec settles (yours to confirm)

- **`seqkit split2`.** Rejected: fastp (sarek's splitter, `--split_by_lines`): quality, length, adapter and polyG
  (NovaSeq) processing are on by default and would all have to be turned off; the `splitFastq` operator (splits in the
  head job).
- **50,000,000 pairs per chunk** (sarek's `--split_fastq` default): a 4 M-pair head maps in 2-3 min at 12 cpus (job
  1096590), so a chunk should map in well under 1 h. Rejected: the demultiplexed lanes as chunks (uneven sizes, and
  `CAT_FASTQ` has joined them).
- **Always split.** A sample under 50 M pairs is one chunk and one-file merge. Rejected: a `branch` past split and merge
  for small samples (two paths to test).
- **Merge the sorted chunks, then markdup.** Rejected: markdup per chunk (misses duplicates across chunks); one sort
  after an unsorted merge (one long task again).
- **Chunk size in `ext.args`, not a parameter** (as Milestone 7's step-4 values).

## Not in this milestone

- Keeping per-lane FASTQs in demultiplexing.
- Space: the chunks add one gzipped copy of each sample's reads to `work/`; the production space plan is rechecked
  in its run plan.

## Tests

1. **Tool** (laptop): `seqkit split2` on fixture pairs; the chunks joined back equal the input, pairs in order.
2. **Wiring** (laptop, stubs): a sample with 3 chunks gives 3 map, clip, fixmate and sort tasks, 1 merge, 1 markdup;
   the DAG.
3. **Equivalence** (laptop, real data, <= 15 min): S_2A_3's first 4 M pairs, split into 1 M-pair chunks (test
   `ext.args`) against the unsplit CRAM of job 1096590: same reads (count and names), `samtools flagstat` and the
   number of reads whose alignment differs. minibwa may estimate pairing statistics per batch of reads, so a few
   reads at chunk boundaries can differ; the number is reported for you to judge.
4. **Cluster** (hazel, `hpc_dev`, chunk tasks on `compute_partners`): the 10 Milestone 7 debugging samples on full
   libraries, from a worktree (`ZEALGT_REPO`) while job 1098401 still uses the checkout. Gives the chunk resources
   and the full CRAMs for Milestone 7.

## Done when

- Tool, stub and equivalence tests pass; `nf-core pipelines lint` has no failures.
- The hazel run wrote the 10 CRAMs with every task on `compute_partners`; resources are in config and `docs/RESOURCES.md`.
- `docs/structure.md` shows the split in the alignment row; `decisions.md` holds only the choices you confirm.
