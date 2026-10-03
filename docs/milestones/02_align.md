# Milestone 2: alignment

Second step of `ALIGNMENT`: demultiplexed lane reads to one duplicate-marked CRAM per sample, with one read group per
lane.

## Inputs

- Per sample x lane read pairs from `FASTQ_DEMULTIPLEX_FQTK`. Milestone 1's `CAT_FASTQ` is removed, because alignment
  needs the lanes kept apart. The demux stage emits `[meta + lane, [R1, R2]]` per sample and lane.
- `--fasta`: `Zm-B73-REFERENCE-NAM-5.0.fa` on `/rsstu` (hazel), with its `.fai`.
- `--minibwa_index`: the existing prebuilt index next to the FASTA (`.l2b`, `.mbw`).
- Tests use `tests/fixtures/ref/tiny.fa`, its `.fai` and a minibwa index built once from it, all tracked.
- Samplesheet: no new columns. The read group comes from `sample_id`, `library` and the lane in the demux meta.

## Outputs

- Per sample: `<sample_id>.cram` and `.crai`, published with `mode: 'copy'` to the `/rsstu` store (decision "CRAMs to
  permanent storage").
- Per lane, one read group:
  - `ID:<sample_id>.<lane>`, `SM:<sample_id>`, `LB:<library>`, `PL:ILLUMINA`, `PU:<lane>`.
  - `<lane>` is the lane file stem, e.g. `LIBX_TESTFC01_L1` (Novogene) or `LIBB1_S1_L001` (batch 1).
- During development every process publishes its outputs (`hpc_dev`).

## Processes

Stage `FASTQ_ALIGN_MINIBWA`, every module from nf-core:

1. `MINIBWA_MAP`, one task per sample x lane.
   - `ext.args` = `-x sr -R '<read group>'`, built from `meta` in `conf/modules.config`.
   - `sort_bam = false`: the output is query-grouped, as fgumi needs.
2. `FGUMI_CLIP`, one task per sample x lane: `--clipping-mode soft --clip-bases-past-mate true`. fgumi's default is
   hard clipping.
3. `SAMTOOLS_FIXMATE`, one task per sample x lane: `-m`. It adds the mate-score tags markdup needs, after clipping, so
   they describe the clipped reads.
4. `SAMTOOLS_SORT`, one task per sample x lane: coordinate order.
5. `SAMTOOLS_MERGE`, one task per sample: lanes collected with `groupTuple` and a `groupKey` set to the sample's lane
   count. Samples with a single lane skip the merge (`branch`, as in Milestone 1).
6. `SAMTOOLS_MARKDUP`, one task per sample: `-d 2500 --output-fmt cram`. Duplicates are flagged, not removed.

## Choices this spec settles

- **Clipping before duplicate marking, with fgumi** (user, 2026-10-02). Markdup sees the clipped reads, and no extra sort
  is needed. Rejected: `fgbio ClipBam`, a slower JVM tool with the same option, and clipping after markdup.
- **One module per tool** (user). Rejected: the old one-pipe `ALIGN_MARKDUP`. The cost is three intermediate BAMs per
  lane in `work/`.
- **Read group per lane, SM = `sample_id`** (user). This gives Picard metrics per lane.
  - The nil_id stays out of CRAM headers, as `meta/PROVENANCE.md` says.
  - The 3 batch-2 replicate pairs (`replicate_of`) are merged in genotyping, via the read-group-to-sample map of
    `bcftools mpileup`.
  - Rejected: SM = `nil_id_resolved` with merged CRAMs (one registry fix, e.g. PN17_SID1574's nil_id, would make a CRAM
    stale), and one read group per sample (the old repo's way).
  - This replaces the 09-28 rule "one read group per sample" in `PROVENANCE.md`; that file and `decisions.md` are
    updated in this milestone.
- **`PU` = the lane file stem.** The flow cell is already in every read name, and markdup reads it from there. Rejected:
  reading the flow cell from the first FASTQ header, which needs an extra task or file reading in channel code.
- **No index module.** The B73 index is prebuilt and the fixture index is tracked. Rejected: `MINIBWA_INDEX` on every
  production run, since `cleanup` deletes `work/`.

- **minibwa 0.7** (user): nf-core `minibwa/map` pins 0.2; it is patched with `nf-core modules patch` to 0.7, the version
  of the old runs, the prebuilt B73 index and the current bioconda release. Rejected: 0.2, which needs a new B73 index.

## Open, to check during the work

- Whether `samtools markdup` writes the `.crai` (`--write-index`) through the nf-core module. If not, add
  `SAMTOOLS_INDEX`.
- Markdup statistics (`-f`): published if the module allows it, otherwise left to `CRAM_QC_SAMTOOLS_PICARD`.
- Task disk use of the intermediate BAMs on one batch-1 lane.

## Tests

1. **Wiring** (laptop, stubs, seconds).
   - The pipeline stub test on the two fixture libraries: LIBX has 2 plain lanes, LIBB1 has 2 tar lanes.
   - Checks: one CRAM per kept sample, one map/clip/fixmate/sort task per sample x lane, one merge per multi-lane
     sample.
   - The same run writes the channel-level DAG.
2. **Tool behaviour** (laptop, Docker, minutes): nf-test of `FASTQ_ALIGN_MINIBWA` on `tiny.fa`. Checks:
   - one `@RG` per lane with the fields above;
   - reads on `chrA`;
   - soft clips where a read passes its mate's start;
   - duplicates flagged and kept (`samtools flagstat`).
3. **Cluster wiring** (hazel, Apptainer): `-profile hpc_dev -stub-run` on the Milestone 1 minimal sheet.
4. **Resource profile** (hazel, <= 30 min per process): one BC1 lane and one batch-1 lane with `--head`. CPU, peak memory
   and run time per process go into `conf/hpc_dev.config` / `conf/hpc_prod.config`.

- Budget: all laptop tests together <= 5 min.

## Done when

- Stub and tool tests pass; `nf-core pipelines lint` has no failures.
- The DAG shows `MINIBWA_MAP -> FGUMI_CLIP -> SAMTOOLS_FIXMATE -> SAMTOOLS_SORT` per lane, then `SAMTOOLS_MERGE ->
  SAMTOOLS_MARKDUP` per sample.
- Resource numbers are in config, measured, one line per process.
- `decisions.md`, `docs/structure.md` and `meta/PROVENANCE.md` record this milestone's choices.
- The report lists the choices made during the work.
