# Decisions

One entry per decision, newest last. Terms as in `TERMINOLOGY.md`.

## 2026-10-02 Workflows

`ALIGNMENT` takes raw reads to one CRAM per sample and stops there; `GENOTYPE` reads those CRAMs.

## 2026-10-02 `--head N`

First N read pairs per library, before demultiplexing; test runs only. Not called `--subsample`, which means coverage
downsampling in genotyping. `--step alignment` takes the first N pairs per sample with nf-core `seqkit/head` (user,
2026-10-03), not with `EXTRACT_LANE`, which handles lanes only.

## 2026-10-02 Read processing, both kits

- Demultiplexing: read structures and mismatches as the Twist guides say (tool: see "Demultiplexing with fqtk").
  - 96-Plex (BC2S3 batch 1): `8B12S+T 8S+T`, fqtk's default mismatches (the guide sets none), which are the same
    `--max-mismatches 1 --min-mismatch-delta 2` (`fqtk demux --help`, 0.4.0): both kits allow one mismatch.
  - FlexPrep (BC1, BC2S3 batch 2): `6B2S+T 6B2S+T --max-mismatches 1 --min-mismatch-delta 2`.
- No adapter trimming, as both guides say. Twist publishes no adapter sequences; none are needed.
- After alignment, before duplicate marking: `fgumi clip --clipping-mode soft --clip-bases-past-mate true`, both kits.
  - Replaces `fgbio ClipBam --clip-bases-past-mate` (same option, a slower JVM tool); markdup sees the clipped reads and
    no extra sort is needed. Soft, not fgumi's default hard clipping.
  - Removes read-through into the mate's barcode, random bases and adapter: clips at the insert end in 94-97 % of reads.
  - Differs from the 96-Plex guide's `--clip-overlapping-reads` (the FlexPrep guide has no clipping): that option keeps
    one mate's half of the overlap by position, often the lower-quality base; past-mate leaves the overlap to mpileup,
    which keeps the better base. At `-Q 20` past-mate keeps 0.3 % (FlexPrep) / 0.9 % (96-Plex) more counted bases.
  - Both options together equal overlapping alone; not used.
- Open: the base quality of read-through bases, i.e. whether `-Q 20` alone would drop them.

## 2026-10-02 Allele counting

`bcftools mpileup -I -a AD -q 20 -Q 20`, default depth cap (250), default mate-overlap removal.

- `-Q 20`: bcftools' default minimum base quality is 1; about two thirds of non-reference observations were bases below
  Q20 (the lowest bins: Q9 NovaSeq X, Q11 NovaSeq 6000).
- No `-d 10000`: samples are 0.9-5.5x (48 BC1 samples); >= 250x covers at most 0.008 % of the genome, i.e. repeats.
- Open: CRISP discovery sets no base-quality threshold (`--mbq` default 10 keeps batch 1's Q11 bases); `--mbq 20`
  proposed, not measured.

## 2026-10-02 Samplesheet column `kit`

`kit` = `twist_flexprep` | `twist_96plex` names the library preparation kit and selects the read structure and
mismatches. Replaces `barcode_layout` (`symmetric` | `r1_only`), which described a consequence, not the kit.

## 2026-10-02 Container images on `/share`

`apptainer.cacheDir` = `/share/maize/frodrig4/apptainer/cache`; images are pulled there by an xfer job and pulled again
when the 30-day scratch purge removes them. Not `/rsstu`: slower (seen when building conda envs there).

## 2026-10-02 Demultiplexing with fqtk

`fqtk demux` (nf-core `fqtk`) replaces `fgbio DemuxFastqs`: same read structures and mismatch rule. On 5 M pairs per
lane it gave identical read sets per sample for all 75 samples of a 96-Plex lane and all 12 of a FlexPrep lane, in
20 s / 13 s instead of 4 min 12 s / 3 min 43 s, at half the memory (1.5-1.6 GB). 5 cpus, `--threads 5`, 2 GB per lane.

## 2026-10-02 Unmatched reads discarded

Reads matching no sample barcode are not kept, as before; their count per lane is in the published fqtk metrics.

## 2026-10-02 Development and production profiles

Two profiles over shared cluster settings (`conf/hpc_shared.config`), each with one fixed launch directory on `/share`
so `-resume` always finds the previous run's cache:

- `hpc_dev` (`nf_work/zealgt_dev`): runs on heads of one library; outputs are published as hard links
  (`publish_dir_mode = 'link'`): no extra space, and not symlinks, which break when `work/` is deleted. Files internal
  to a stage stay in `work/`, which is kept, so after a code change `-resume` reruns only the changed steps.- `hpc_prod` (`nf_work/zealgt_prod`): whole libraries; only CRAMs and QC are published; `cleanup = true` deletes a
  successful run's `work/` (a failed run keeps it for `-resume`); the head job runs on the normal QOS.
  A stage's result stops being published when the user decides the stage is production-ready.

## 2026-10-02 CRAMs to permanent storage

The CRAM process publishes each CRAM and its index straight to the `/rsstu` store with `mode: 'copy'` (another
filesystem) as its task ends; Nextflow finishes all publishing before the run succeeds and `cleanup` removes `work/`, and
a failed copy fails the run. No separate move step after the workflow.

## 2026-10-02 Shared plates: all barcodes to fqtk

A plate shared with another project gives fqtk all its barcodes, so the other project's reads (96-Plex barcodes are as
close as 2 apart, one error from ours) go to their own wells; those wells (`exclude` = TRUE in `meta/samples.csv`, e.g. the
21 `LANTEO` wells of BZea2) are dropped right after demultiplexing. A library with no kept well (BZea1) is not run.

## 2026-10-02 nf-core branch flow from Milestone 2 on

Milestone 1 went straight into `main` as 0.1.0. From Milestone 2 on, we use nf-core's branch flow: feature branches go
into `dev` by PR; `dev` goes into `main` only for a release; `patch` is for fixes to a release.

## 2026-10-02 Nextflow from a container on hazel

The head job runs Nextflow from a container, not from a conda environment or hazel's modules.

## 2026-10-02 Alignment: one module per tool

Alignment is a chain of nf-core modules, one per tool: `minibwa map` -> `fgumi clip` -> `samtools fixmate` -> `sort` ->
`markdup`. Not the old one-pipe `ALIGN_MARKDUP`; the cost is three intermediate BAMs per sample in `work/`.

## 2026-10-03 Read group per sample

One read group per sample: `ID` and `SM` = `sample_id`, `LB:<library>`, `PL:ILLUMINA`, `PU` lists the sample's lanes.
Not one read group per lane: no use here, the samples are not diploid and there is no GATK/BQSR.

## 2026-10-02 minibwa 0.7

nf-core `minibwa/map` (minibwa 0.2) is patched to minibwa 0.7: the version of the old runs, of the prebuilt B73 index and
the current bioconda release. 0.2 would need a new B73 index.

## 2026-10-03 CRAM QC

Per CRAM, in parallel: samtools stats (alignment summary, duplicates, mapped bases), Picard CollectWgsMetrics (usable
depth and `PCT_EXC_*`; `PCT_EXC_TOTAL` is the floor π of the missing-data model) and mosdepth with nf-core/sarek's WGS
settings `-n --fast-mode --by 500` (raw depth per 500 bp window). Not Picard CollectMultipleMetrics: it repeats samtools
stats. CollectWgsMetrics on the whole genome, default STRICT validation, Picard defaults. QC files go to `cram/` next to
the CRAM.

## 2026-10-03 mosdepth stages the reference index

nf-core `mosdepth` is patched to take an optional `.fai` with the FASTA; without it htslib builds the index in every task.
An upstream PR to nf-core/modules comes later.

## 2026-10-03 MultiQC before imported CRAMs

The last `ALIGNMENT` row is split: MultiQC on the QC files first (Milestone 4), `MARKDUP_IMPORT` for the imported
zealbc1/nilhmm CRAMs separately (Milestone 5).

## 2026-10-03 markdup duplicate counts

`samtools markdup` writes its counts (`--json -f`): duplicates split into PCR and optical (`-d 2500`) and the estimated
library size, which samtools stats and Picard do not give. The file goes to `cram/` next to the CRAM and into MultiQC.

## 2026-10-03 No import step

Every BC1 and BC2S3 CRAM is made from raw reads by `ALIGNMENT`; existing alignments are not imported. The pipeline
exists to replace Nirwan's BC2S3 BAMs (demultiplexed and clipped with Trimmomatic) with processing as the Twist guides
recommend. Supersedes the `MARKDUP_IMPORT` half of "MultiQC before imported CRAMs". The B73 control BAMs belong to
`GENOTYPE`.

## 2026-10-03 CollectWgsMetrics default algorithm

Picard CollectWgsMetrics runs without `--USE_FAST_ALGORITHM`: on the deepest BC1 CRAM (5.5x) its output was not
identical (MEAN_COVERAGE, SD_COVERAGE, PCT_EXC_TOTAL and 38 histogram bins differ) and it was only 13 % faster
(36.6 vs 42.2 min). Test: `docs/later/picard_fast_algorithm.md`.

## 2026-10-03 Demultiplexing as its own workflow

Demultiplexing becomes its own workflow, run once per set of libraries; the per-sample FASTQs (lanes joined) and their
samplesheet are kept on `/rsstu` next to the multiplexed originals, which stay; `ALIGNMENT` reads per-sample FASTQs. Why
(user): demultiplexing inside every run ties up sample selection for development and production batches. Per-sample
FASTQs ~0.85 x raw (~5.9 TB; BZea5 L001 fqtk test). Not nf-core/demultiplex 1.8.0: it unpacks whole `.tar.gz` run
folders, takes one read-structure list, has no per-kit mismatches and does not join lanes.

## 2026-10-03 fqtk, not cutadapt

fqtk stays the demultiplexer (user). On 5 M pairs of a FlexPrep and a 96-Plex lane, every pair zealgt-old's cutadapt
(`-e 0`) assigned went to the same sample under fqtk, none to another; fqtk's one mismatch kept 1.9-2.7 % more pairs.
Test: `docs/later/fqtk_vs_cutadapt.md`.

## 2026-10-03 Demultiplexing per lane

fqtk runs once per lane, and `CAT_FASTQ` joins each sample's lanes (user). Reasons:

- Data source: the reads arrive split by lane (providers: `meta/sources/SOURCES.tsv`, `meta/PROVENANCE.md`). Novogene
  delivered BC1 and BC2S3 batch 2 as one file pair per lane (e.g. 1C `_L5`, `_L6`, `_L7`); the NCSU GSL tars of batch
  1 hold one member per lane (`_L001`, `_L002`).
- History:
  - Nirwan ran sabre per plate and lane (`github.com/nirwan1265/Mapping`, `src/demultiplex_sabre.csh`).
  - zealgt-old ran cutadapt per lane because cutadapt could not read the lanes as one stream (job 972171,
    2026-09-28, its `docs/PLAN_pipeline.md:48-50`).
  - zealbc1 copied each library's lanes into one file per read before cutadapt (`nilhmm/modules/demux.nf`).
- Not tested: whether fqtk reads a library's lanes as one stream.
- Cost: `CAT_FASTQ`'s tasks and a second copy of the FASTQs in `work/` (~6.2 TB at peak), which fits the `/share` quota.
- Rejected: one fqtk task per library on a stream of its lanes; and copying the lanes into one file first, which costs
  the same disk as the per-lane outputs.
