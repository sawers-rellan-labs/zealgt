# Decisions

One entry per decision, newest last. Terms as in `TERMINOLOGY.md`. An entry marked **Superseded** no longer holds:
follow its pointer.

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

**Superseded** (base quality) by "2026-10-17 VARIANT_CALLING discovery (Milestone 9h)".

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

## 2026-10-03 Production demultiplexing in waves

- Outputs on `/rsstu/users/r/rrellan/BZea/ZEAL/demultiplex`, flat per sequencing batch: `<source>/<sample_id>_R{1,2}.fastq.gz`
  (`source` = `bc1`, `bc2s3_batch1`, `bc2s3_batch2`), not one folder per sample and not one per run.
- Limits that may be short at an unmeasured scale (`EXTRACT_LANE` time, `MULTIQC` memory and time in waves 07/08) are
  the measured value times `task.attempt`, so the retry doubles them; not padded requests (12 GB for MultiQC would be
  < 10 % efficient). The first chain (jobs 1071011-1071018) was stopped 16 min into wave 01 to run every wave with it.
- A Sequali failure never stops a production wave (`errorStrategy 'ignore'`): Sequali 1.0.2 crashed on PN7_SID583 and
  PN11_SID979 only inside Nextflow's task wrapper, with intact FASTQs; read QC is a report, the FASTQs are the product.
  Samples without a report are listed in the run plan. The root cause is a separate task.
- Each wave's FASTQ samplesheet in one folder, `samplesheets/<wave sheet name>.csv` (the output index cannot take its
  folder from `source`).
- The `/share` quota is the group's, so the run goes in waves of whole libraries, one sequencing batch per wave, each
  holding at most 2 TB of `work/`; 8 waves, chained, `cleanup` after each. Plan: `docs/runs/demultiplex_production.md`.

## 2026-10-04 No read-start mask in GENOTYPE

- The Twist read structures (2026-10-02 "Read processing, both kits") already skip every non-genomic base at
  demultiplexing: 96-Plex R1 `8B12S+T` drops the barcode and the 12-nt randomer, R2 `8S+T` the 8-nt randomer; FlexPrep
  `6B2S+T` drops the barcode and the 2 skip bases on both reads. Only template reaches minibwa.
- So GENOTYPE has no `MASK_READ_STARTS` and no `READ_POSITION_QC`. zealgt-old needed both because cutadapt removed only
  the barcode, leaving batch-1 R1 cycles 1-12 and BC1 cycles 1-2 in the reads, and recomputed the mask in five stages.
- Read-through of the opposite primer at a read's 3' end lies past the mate's end and is soft-clipped by `fgumi clip`
  in ALIGNMENT.

## 2026-10-04 Low-copy BED from bedtools, not a script

- The low-copy BED is built once outside the pipeline, from the B73 v5 gene GFF and the MaizeGDB TE GFF
  (`Zm-B73-REFERENCE-NAM-5.0.TE.gff3.gz`), with bedtools 2.31.1, and passed in like the reference:
  - genes: `gene` features, `bedtools slop -b 500`, `bedtools merge`;
  - non-TE: every TE feature `bedtools merge`d, `bedtools complement`, `bedtools merge -d 200`, ranges >= 500 bp;
  - low-copy: both together, `bedtools merge -d 200`, ranges >= 500 bp.
- It replaces zealbc1's chain: PHG `create-ranges --boundary gene --pad 500` for the genes, an inline Python TE
  complement (`agent/suggested_script_20260919_004007_te_mask_chr10.sh`) and `PHG/bin/make_union_bed.py` (merge, length
  filter, chr10 hard-coded). The 200 bp gap and 500 bp minimum were recorded only in those scripts.
- Checked on chr10 (hazel job 1094464): 8,084 ranges, 26.1 Mb vs zealbc1's 8,095 ranges, 26.0 Mb; 8,040 ranges
  identical, Jaccard 0.9985; the non-TE part identical (9,838 ranges, 20.7 Mb). The rest is near genes: `bedtools merge`
  joins overlapping padded genes (2,239 ranges) where PHG keeps them apart (about 2,489). Good enough (user).

## 2026-10-04 zealbc1 is a comparison, not a target

- GENOTYPE follows its specs; zealbc1 outputs are for comparison, close but not identical (user). Milestone 7's tier A
  keeps zealbc1's `inconsistent` flag: the first spec draft dropped it without a reason (user).
- "Close enough" at the mosaic (ancestry) level: Dice–Sørensen > 90 % (user); no metric computed yet.

## 2026-10-05 CRISP pool size: -p 12 for every pool

**Superseded** (the witness pool) by "2026-10-17 VARIANT_CALLING discovery (Milestone 9h)"; `-p 12` for every pool
kept by "2026-10-23 CRISP pool size: -p 12 for every pool (Milestone 9h)".

- `-p 12` (6 plants x 2 haplotypes) is what matters for the BC1 pools. The witness pool gets the same 12: at its low
  coverage the number of lines would not change the calls, so no per-pool sizes in the `--bams` file (user).

## 2026-10-05 Split alignment: insert size estimated from the sample, as sarek

- Why split: one map, clip and fixmate chain per full BC1 library needs 6 h and 16 cpus on `compute` / normal, where
  the 10 map tasks of job 1098401 waited with start estimates of 13:15-16:40 on submission at 00:27 (cancelled
  unstarted). Chunks under 2 h run on `compute_partners` / short, where our jobs start within a minute (sacct,
  frodrig4, 30 days: median 0.1 min over 11,088 jobs). Milestone 2a.
- Precedent: nf-core/sarek `--split_fastq`, default 50,000,000 reads per chunk (`nextflow_schema.json`), split by fastp
  `--split_by_lines` (`conf/modules/trimming.config`); chunks are aligned separately and merged per sample before
  duplicate marking. We split with `seqkit split2` (fastp trims and filters by default).
- minibwa estimates the insert size per batch of reads from the sample itself; no fixed `-I` (user: "the best
  estimate comes from the sample"). Fixed values would be one per kit (head-run means 230-484, SD 102-128).
- So the split changes a few alignments (S_2A_3, 4 M pairs in 1 M-pair chunks against unsplit, jobs 1099457 /
  1099789): same 4,000,000 reads and read group; 0.39 % of records differ, 0.06 % in position, 0.32 % in MAPQ
  only (mostly 1-3). Accepted (user).
- Why the difference is small for GENOTYPE: MAPQ matters downstream only through one cut, MAPQ 20 (CRISP `--mmq 20`,
  mpileup `-q 20`). A shift of 1-3 changes a read's fate only when it crosses 20, so only for reads already within
  about 3 of it, a small part of the 0.32 % (not counted). The 0.06 % placed elsewhere are expected to be mostly
  mates in repeats, where either placement was already ambiguous (not checked); GENOTYPE works in low-copy regions,
  and the witness veto and the pooled likelihood use many reads per site.

## 2026-10-05 GENOTYPE inputs and discovery outputs (Milestone 7 build choices)

**Superseded** (the witness veto; the B73 check filter, by the QC-PASS cutoff of 2026-10-21) by "2026-10-17 VARIANT_CALLING discovery (Milestone 9h)".

Confirmed by the user from the Milestone 7 report; item 11 for now, open to change.

- `GENOTYPE` reads a CRAM samplesheet with a `wgs_metrics` column; the coverage filter reads MEAN_COVERAGE from it,
  `--min_mean_coverage` default 0.05.
- `--b73_controls` is a CSV (`sample_id, cram, crai`), at least one row; the controls are cut to `--region` with
  `samtools merge -R` and get a read group.
- `--region` goes to CRISP `--regions`; the low-copy BED is not clipped to it.
- The witness veto keeps biallelic SNPs only (`-m2 -M2 -v snps`), so the donor VCF holds the same records as the site
  table, and the any-ALT vs first-ALT question of multi-allelic sites does not arise.
- The B73 check filter counts each check's ALT share over all check sites, no region filter.
- `dropped_b73_checks.tsv` lists the dropped checks only (was `b73_checks.tsv`).
- Roles from `meta/samples.csv`: `bc1_sample`, `nil` (was `line`), `check` with pedigree `B73-bulk`; `landrace_line`
  stays.
- Every biallelic SNP gets a site row; tier none is written ".".
- `--step genotype` requires `--region`, `--lowcopy_bed`, `--check_sites`, `--b73_controls`; `--minibwa_index` only for
  alignment.

## 2026-10-11 Sample introgression dosage check: families with balanced tissue pools for the marker-union estimate

User's rule (2026-10-09), thresholds confirmed 2026-10-11 on the eight chr10 donors' union-ALT calls; named the sample
introgression dosage check (ALT read frequency check) on 2026-10-16 (was "curve rule"). Families that pass have
balanced tissue pools, the others unbalanced tissue pools (`docs/TERMINOLOGY.md`). Only families with balanced tissue
pools enter the rarefaction (accumulation) curves that estimate the total marker union.

- A donor/chromosome enters the union curves if its lines pass (1) few introgressions and (2) segment dosage, and (3) the lines
  passing 1-2 cover the chromosome. Contamination can fake full coverage, so failing lines don't count toward it.
- (1) at most 4 donor (HET/ALT) segments per line.
- (2) per line, reads in REF segments <= 3 % ALT, in HET segments 30-55 % ALT, in ALT segments >= 75 % ALT.
- (3) donor segments of the passing lines cover >= 90 % of the chromosome (user's proposal; per-family expectation
  under the registry pedigree checked first).
- Families with unbalanced tissue pools stay off the union curves; their lines are still called at union-ALT markers.

## 2026-10-11 RTIGER markers: the donor's union-ALT sites (Milestone 9a)

Spec approved by the user, 2026-10-11 (`docs/milestones/09a_union_alt_markers.md`).

- Each donor's RTIGER markers are the union sites gap filling called ALT for it, own or gap (was: its own tier-A sites).
  Reason (user, 2026-10-08): own tier-A markers can't be believed where no line carries an introgression.
- Rigidity stays 0.5 % of the markers.
- Two nf-core `bcftools/view` calls per donor (`-s`, then `-i 'GT="1"' -G`), not a script.
- `CALL_ANCESTRY` writes per-line checks (donor segments, bp, reads and ALT % per state) as values; the dosage check's
  thresholds and coverage are applied downstream.
- Filter 1 (drop markers reading ALT in 2 or more REF lines) retired: on the eight chr10 donors it changed neither the
  ALT ceiling, the class shares nor the curve set, and its fixed cut drops more markers in large families.

## 2026-10-16 Families stay in the union: Milestone 9b not merged, 9c dropped

User, 2026-10-16 ("keep 9b as a record, record the decision"), on the chr10 diagnosis reviewed 2026-10-15.

- Every donor's tier-A sites enter its taxon's union (Milestone 9a as on `dev`); no family is left out.
- Milestone 9b (`--union_exclude`) is not merged; branch `m09b-union-exclude` stays as a record. Leaving families out
  changed neither QTL power (diploperennis DTA LOD 7.89 / 7.89 / 7.88) nor noise (mexicana kept donors 1.06 -> 1.10
  introgressions per line).
- Milestone 9c (the dosage check deciding a second union pass) is dropped; draft spec on branch `m09c-curve-rule` only.
- Lines and families are flagged, never dropped; the sample introgression dosage check stays a check applied downstream of the line checks.

## 2026-10-16 Steps variant_calling and ancestry (Milestone 9e)

Spec approved by the user, 2026-10-16 (`docs/milestones/09e_variant_calling_ancestry_split.md`).

- `--step genotype` becomes `variant_calling` (discovery, union, gap filling, each line's counts at its donor's
  markers) and `ancestry` (RTIGER and the grid). Reason (user): "the only thing that I need genome-wide are the
  counts; the variant discovery can be done once and then we can fiddle with the HMM", as alignment was separated.
- `variant_calling` publishes the counts and a counts sheet (`samplesheets/<input name>.counts.csv`); `ancestry` reads it.
- `--ancestry_fit chromosome` (default, outputs as before) or `genome` (one RTIGER fit per donor over its regions).
- Short task names: stages `LINE_COUNTS` and `ANCESTRY_RTIGER`; the pipeline workflow `ZEALGT`.
- Published folders `variant_calling/` and `ancestry/` (were `genotype/`); results already on `/rsstu` stay where they are.
- RTIGER rigidity as a window in Mb, replacing 0.5 % of the markers (user, 2026-10-16: "the per Mb rule seems to work
  the best everywhere for now"; "1 Mb default, add it to 9e"): r = `--rigidity_mb` (default 1) x the median line's
  covered markers per Mb of the markers' span, per chromosome and per genome alike.

## 2026-10-16 Efficiency before production (Milestone 9f)

Spec approved by the user, 2026-10-16 (`docs/milestones/09f_efficiency_before_production.md`).

- Group sizes read from the samplesheet (`groupKey`), so each donor and region goes on once its own files are in.
- One count VCF per donor and region (a sample per line), published as the counts; the counts sheet one row per donor
  and region. Rejected: splitting it back to one file per line.
- `COUNT_LINES` with full BAQ (`-D`; user: "go with -D"): partial BAQ looks at every sample in the call, so a line's
  counts depended on its siblings (slice: 60 of 82 lines moved by 1-2 reads). Rejected: no BAQ (`-B`); one call per line.
- CRISP log timestamps left to a PR upstream (`vibansal/crisp`). Rejected: `gawk` in the CRISP image.

## 2026-10-17 Job arrays for variant calling in `hpc_prod`

User, 2026-10-17: "I want the array jobs implemented": arrays of 20 for the per-donor and per-sample variant-calling
processes; `submitRateLimit` 20/1min would take ~14 h to submit ~17,500 single jobs (run 1349242, cancelled).

## 2026-10-17 No supplementary records in variant calling (Milestone 9g)

User, 2026-10-17: exclude supplementary records (0x800) consistently across variant calling, always (no parameter), at
the variant-calling input; the `/rsstu` CRAMs stay whole. CRISP 1a9027e has a use-after-free on them
(vibansal/crisp#35) that stopped the production run.

- CRISP reads filtered copies (`samtools view -F 0x800`): each BC1 CRAM once, whole genome; each witness pool per region.
  The four mpileup steps skip them with `--ff UNMAP,SECONDARY,QCFAIL,DUP,SUPPLEMENTARY`.
- Rejected: filtering at CRAM export (the archive loses the records, 2,173 CRAMs re-exported); a parameter; filtered
  copies of every CRAM (about the alignment archive's size on `/share`).
- Accepted (user, 2026-10-17: "the losses are ok"): ~2 % fewer discovery records and tier-A sites (pilot slice, chr10:1-5
  Mb; full chr1 of Zl.0020_P3: 229,627 vs 234,635 CRISP calls), counts at most 4 reads per cell.

## 2026-10-17 VARIANT_CALLING discovery (Milestone 9h)

User, 2026-10-17, in their words: "I need the variant to be present in a BC1 and the segregating population. That was my
intent." "the crisp thing should go over the 3 pools: BC1s: NILs: Checks. But only the decent checks not the ones
contaminated" ("decent" replaced by the user with "QC PASS B73"); the BC1 pools "would share almost all the variants
and so they will have poor contrast". On Q30 for reads: "I think it is a good decision after that filter the B73
selection was less dependent on the batch". The word "witness" was coined by an agent (zealbc1, 2026-09-21).

| existing entry                                                                | what it says                                                                        | overruled by (VARIANT_CALLING, Milestone 9h)                                                                                                                                   |
| ----------------------------------------------------------------------------- | ----------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Milestone 7 spec; math supplement Section 4.1                                 | tier A needs ALT reads in >= 2 BC1 pools                                            | a variant must be in a BC1 and in the segregating population (the NIL in silico pool)                                                                                          |
| 2026-10-05 GENOTYPE inputs and discovery outputs; math supplement Section 4.2 | the witness veto: keep a site only with >= 1 ALT read in the witness pool           | the same rule, with the NIL in silico pool as one of CRISP's pools; no separate veto, no "witness"                                                                             |
| 2026-10-05 CRISP pool size                                                    | `-p 12` for every pool, the witness pool included                                   | three pool kinds: the donor's BC1s, its NIL in silico pool, one pool of QC-PASS B73 checks; `-p 12` for every pool (user, 2026-10-23)                                          |
| zealbc1 DECISIONS 2026-09-23                                                  | CRISP = BC1s + BC2S3 pool only; B73 enters after CRISP (step 4)                     | the QC-PASS B73 checks go into CRISP as a pool                                                                                                                                 |
| 2026-10-02 Allele counting; Milestone 7 (CRISP)                               | mpileup `-q 20 -Q 20`; CRISP `--mmq 20 --mbq 20`                                    | MAPQ >= 60 and base quality >= 30 in discovery and counting (user: "after that filter the B73 selection was less dependent on the batch"; MAPQ 60 and BQ 30: 2026-10-22 entry) |
| 2026-10-05 GENOTYPE inputs and discovery outputs                              | B73 check filter: < 1 % ALT share at the check sites (SNP50K), B73-bulk checks only | QC-PASS B73 checks: mismatch rate < 0.1 % on bases of quality >= 30, whole genome, no genotypes (21 of 23; user, 2026-10-21)                                                   |
| none                                                                          |                                                                                     | sites kept only if in the wideseq panel (Schnable 2023; 2026-10-23 entry)                                                                                                      |

- The B73 checks: all 23 of the run's sheet (12 batch-1 B73-bulk, 11 batch-2 B73) are candidates; batch 1 has lower
  base quality (average 35 vs 40), measured in notebook 08.
- QC-PASS cutoff (user, 2026-10-21: "use the 0.1% Q30 mismatch cutoff, record it"): the whole-genome mismatch rate on
  bases of quality >= 30 (`samtools stats` with the reference, job 1388640) under 0.1 %. It keeps 21 of 23 checks and
  drops PN3_SID236 and PN5_SID468; a round number, call-free and independent of run 1367152, as the user required
  on 2026-10-17 ("no genotypes"; "other number sound tailored for a result").
- Variant-calling production run 1367152 (2026-10-17) used the overruled rules; its outputs are a baseline only.

## 2026-10-22 Read and population site filters (Milestone 9h)

**Superseded** (MAF >= 0.05) by "2026-10-23 Site filters: no MAF, wideseq kept (Milestone 9h)"; the read filters and
the depth filter stand.

User, 2026-10-22: "I believe we have established from the controls that there is a noise in the sequencing thta is why
I suggested usingbthe Q30 and MQ 60. that filter must be kept throughpout." "In addition to those the two successful
filters seem to be the 0.5-2x coverage per site and the MAF >0.05".

- Read filters MAPQ >= 60 and BQ >= 30 in every step that reads alignments (CRISP and every mpileup); also recorded on
  branch `mapq60-bq30` (fda7f3a, 2026-10-21).
- Population site filters, as in the SNP50K joint call (2024 VCF headers, `joint_genotype/all_samps/7_filtered_samples/`:
  `INFO/DP>= 427.00 && INFO/DP<=1505 && QUAL>=70 && INFO/MQ>40 && INFO/QD>=0.75`, then MAF >= 0.05): a site's reads
  over the lines in 0.5-2x the lines' expected reads, and >= 5 % of the lines with an ALT read.
- Evidence (zealhmm `zeal-chr10-snp50k-filters.qmd`, chr10, run 1367152's counts at MAPQ/BQ 20): PV23 floor pi 0.286 ->
  0.148 with depth + MQ + MAF (SNP50K: 0.161); at the SNP50K sites zealgt's PV23 CRAMs (MAPQ 60, BQ 30) give pi 0.171,
  KS D 0.067 (job 1498209). Recount at MAPQ 60 / BQ 30 pending (jobs 1498762-66).
- OPEN (mine): where the site filters go: proposed after counting all lines at every union site (whole cohort), before
  the donor markers are chosen.

## 2026-10-23 CRISP pool size: -p 12 for every pool (Milestone 9h)

User, 2026-10-23: "keep -p 12 for all pools, record it".

- `-p 12` for the donor's BC1 pools, its NIL in silico pool and the QC-PASS B73 check pool; no per-pool sizes. "Pool
  sizes set per pool" in the 9h table above was an agent's wording, not the user's.
- Context (mine, calculated from notebook 08, not measured): CRISP takes a pool as carrying ALT from a share of about
  1/p (8.3 % at 12). The check pool's ALT share from error (0.1-0.26 %) stays below it, the B73 blocks every check
  carries (chr1 296-299 Mb, chr5 218-219 Mb, ~20-25 % ALT) above it; the check pool's true size (21 x 12 = 252) would
  put it at 0.4 %, near the error level.

## 2026-10-23 B73 check pool filter: CRISP's check pool call (Milestone 9h)

User, 2026-10-23: "b73 has some sites that have sequence divergence from the reference those I would relly like
removed"; "use CRISP's check pool call, record it".

- A site is dropped where CRISP calls the QC-PASS B73 check pool a carrier of the ALT allele, genome-wide; no region
  list.
- Rejected: >= 1 ALT read in the check pool (user: "that is every single error in the check pool"); a mask of the
  notebook 08 blocks (chr1 296-299 Mb, chr5 218-219 Mb).
- OPEN (mine): the field read for the call, the check pool's `FORMAT/AC` >= 1 (CRISP's maximum-likelihood ALT count,
  "." in pools it does not call in run 1367152's VCFs); to confirm in the tool tests.

## 2026-10-23 NIL pool: >= 1 ALT read (Milestone 9h)

User, 2026-10-23: "use >= 1 ALT read in the NIL pool, record it".

- "Present in the segregating population" (2026-10-17 entry) is tested as >= 1 ALT read in the donor's NIL in silico
  pool (forward, reverse or overlapping reads), as the witness veto does now.
- Rejected: CRISP's call for the NIL pool. Context (mine, not measured): at ~4.5x per site and a donor ALT share often
  under 1/12, it would drop real donor sites carried by few lines.
- OPEN: how "present in a BC1" is tested.

## 2026-10-23 Site filters: no MAF, wideseq kept (Milestone 9h)

User, 2026-10-23 (capitals removed): "yeah the MAF filter doesnt seem to be helpful"; "yeah fro some reason that
wideseq filtering is working"; "I like the mexicana and diplo get the same number of sites ~30k leaving maf out";
"record dropping MAF and keeping wideseq in decisions.md".

- No MAF filter on the donor markers (drops the MAF >= 0.05 of the 2026-10-22 entry).
- Wideseq kept: a marker is kept only if its position, REF and ALT are in the wideseq panel (Schnable 2023,
  `/rsstu/.../bzeaseq/wideseq_ref/`).
- Evidence (chr10, run 1367152's gap-filled markers, lines recounted at MAPQ 60 / BQ 30, depth 0.5-2x + MQ > 40,
  RTIGER at 1 Mb; zealhmm `zeal-mex-chr10-maf.qmd`, `zeal-dip-chr10-rtiger-filters.qmd`; hazel jobs 1521271-72,
  1522424, 1523451):

  | chr10                                         | no MAF, wideseq | MAF, wideseq | no MAF, no wideseq | SNP50K |
  | --------------------------------------------- | --------------- | ------------ | ------------------ | ------ |
  | mexicana markers per donor (median)           | 32,453          | 2,101        | 81,994             | -      |
  | diploperennis markers per donor (median)      | 26,423          | 1,587        | 72,402             | -      |
  | mexicana segments per line (572 lines)        | 1.13            | 1.18         | 1.96               | 0.49   |
  | diploperennis segments per line               | 1.23            | -            | 2.42               | 0.51   |
  | mexicana PH full LOD at 54 cM (all lines)     | 5.12            | 4.20         | 4.60               | 6.77   |
  | diploperennis DTA full max LOD                | 7.91            | -            | 7.89               | 6.70   |
  | diploperennis PH full max LOD                 | 6.32            | -            | 5.63               | 5.25   |
  | diploperennis ALT segments, ALT read fraction | 0.803           | -            | 0.748              | 0.421  |

  Family covariate, chr10-only permutation thresholds. Diploperennis with MAF ran only through the union matrix (DTA
  8.43, all lines at the 5,035 union sites).

- Context (mine, not measured): at ~0.3x the share of lines with an ALT read measures coverage more than frequency; a
  real site carried by 12.5 % of lines shows an ALT read in ~3 % of them.

## 2026-10-23 Gap filling kept, the union only as candidate sites (Milestone 9h)

User, 2026-10-23: "I know tHta the gap filling shgould be added"; "nope the complicated gap fill stays"; "keep the
controls, record gap filling in decisions.md". Earlier (2026-10-22): "the union part seems to break mexicana and fix
diplo".

- Gap filling as in run 1367152: the donors' sites merged into one union per region; each donor's BC1 pools counted at
  every union site (`COUNT_UNION`) and scored with the tier code (`UNION_TIERS`, `score_pooled_likelihood.py`); each
  donor's allele at every union site from Eq. eb (`FILL_DONOR_ALLELES`). A donor's markers are the union sites called
  ALT for it (own or gap).
- `--b73_controls` kept: the external B73 controls stay in the per-site error rate, beside the B73 check pool.
- The union is only the list of candidate sites: each donor's lines are counted at its own markers, never at every
  union site (the union matrix).
- Rejected:
  - the union matrix, every line at all union sites (mexicana nb28: 11,606 sites, segments per line 0.93 vs 9a 0.78 on
    223 lines; ~94 % of the union with ALT in fewer than 2 of a mexicana donor's lines);
  - gap filling by a read rule (>= 1 ALT read in the donor's BC1s and in its NIL lines, no tier scoring; nb36, hazel jobs
    1523883-86): segments per line mexicana 1.77 vs 1.13, diploperennis 1.43 vs 1.23; QTL LODs within a few tenths.
- Evidence for the kept method: the chr10 table of "2026-10-23 Site filters: no MAF, wideseq kept".
- OPEN (mine): the donor's own sites in gap filling once 9h discovery drops tier A (the sites the 9h rule keeps);
  whether gap-filled sites also need >= 1 ALT read in the NIL pool (not in the tested method).

## 2026-10-23 Variant-calling inputs cut to the low-copy ranges (Milestone 9h)

User, 2026-10-23: "I think we could keep the low copy only why the wideseq I thibk it is fine as a last step filter";
"so this goes into 9h: So the filter step is samtools view -F 0x800 -L lowcopy.bed, with the pipeline's existing
low-copy BED, and wideseq stays as the last site filter."

- The filtered copies variant calling reads (today `FILTER_BC1`, `FILTER_WITNESS`: `samtools view -F 0x800`) also keep
  only reads overlapping the pipeline's low-copy BED (`-L`); reads are kept whole, a mate outside the ranges is dropped.
- Wideseq is not in that BED; it stays the last site filter, as in the tested chr10 method.
- Context (mine, not measured): copies about 15-20 % of the CRAMs' size (low-copy is 26 of chr10's 152 Mb); calls inside
  the ranges unchanged; CRISP's memory driven by the pools and local depth more than by file size.
