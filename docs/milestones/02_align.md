# Milestone 2: alignment

Second step of `ALIGNMENT`: each sample's demultiplexed reads to one duplicate-marked CRAM, with one read group per
sample.

## Inputs

- Per sample read pairs from `FASTQ_DEMULTIPLEX_FQTK`, lanes joined by `CAT_FASTQ` as in Milestone 1. The demux meta
  also carries `lanes`: the sample's lane file stems, comma-joined.
- `--fasta`: `Zm-B73-REFERENCE-NAM-5.0.fa` on `/rsstu` (hazel), with its `.fai`.
- `--minibwa_index`: the existing prebuilt index next to the FASTA (`.l2b`, `.mbw`).
- Tests use `tests/fixtures/ref/tiny.fa`, its `.fai` and a minibwa index built once from it, all tracked.
- Samplesheet: no new columns. The read group comes from `sample_id`, `library` and `lanes` in the demux meta.

## Outputs

- Per sample: `<sample_id>.cram` and `.crai`, published with `mode: 'copy'` to the `/rsstu` store (decision "CRAMs to
  permanent storage").
- Per sample, one read group:
  - `ID:<sample_id>`, `SM:<sample_id>`, `LB:<library>`, `PL:ILLUMINA`, `PU:<lanes>`.
  - `<lanes>` are the lane file stems, comma-joined, e.g. `LIBX_TESTFC01_L1,LIBX_TESTFC01_L2` (Novogene) or
    `LIBB1_S1_L001,LIBB1_S1_L002` (batch 1).
- During development every process publishes its outputs (`hpc_dev`).

## Processes

Stage `FASTQ_ALIGN_MINIBWA`, every module from nf-core, one task per sample each:

1. `MINIBWA_MAP`.
   - `ext.args` = `-x sr -R '<read group>'`, built from `meta` in `conf/modules.config`.
   - `sort_bam = false`: the output is query-grouped, as fgumi needs.
2. `FGUMI_CLIP`: `--clipping-mode soft --clip-bases-past-mate true`. fgumi's default is
   hard clipping.
3. `SAMTOOLS_FIXMATE`: `-m`. It adds the mate-score tags markdup needs, after clipping, so
   they describe the clipped reads.
4. `SAMTOOLS_SORT`: coordinate order.
5. `SAMTOOLS_MARKDUP`: `-d 2500 --output-fmt cram`. Duplicates are flagged, not removed.
6. `SAMTOOLS_INDEX`: the `.crai`.

## Choices this spec settles

- **Clipping before duplicate marking, with fgumi** (user, 2026-10-02). Markdup sees the clipped reads, and no extra sort
  is needed. Rejected: `fgbio ClipBam`, a slower JVM tool with the same option, and clipping after markdup.
- **One module per tool** (user). Rejected: the old one-pipe `ALIGN_MARKDUP`. The cost is three intermediate BAMs per
  sample in `work/`.
- **Read group per sample, ID and SM = `sample_id`** (user, 2026-10-03), the 09-28 rule in `meta/PROVENANCE.md`.
  - Rejected: one read group per lane. It has no use here: the samples are not diploid and there is no GATK/BQSR.
  - The nil_id stays out of CRAM headers, as `meta/PROVENANCE.md` says.
- **`PU` = the sample's lane file stems, comma-joined.** The flow cell is already in every read name, and markdup reads
  it from there. Rejected: reading the flow cell from the first FASTQ header, which needs an extra task or file reading
  in channel code.
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
   - Checks: one CRAM per kept sample, one task per sample for each process, no merge.
   - The same run writes the channel-level DAG.
2. **Tool behaviour** (laptop, Docker, minutes): nf-test of `FASTQ_ALIGN_MINIBWA` on `tiny.fa`. Checks:
   - one `@RG` per sample with the fields above, `PU` listing both lanes of LIBX;
   - reads on `chrA`;
   - soft clips where a read passes its mate's start;
   - duplicates flagged and kept (`samtools flagstat`).
3. **Cluster wiring** (hazel, Apptainer): `-profile hpc_dev -stub-run` on the Milestone 1 minimal sheet.
4. **Resource profile** (hazel, <= 30 min per process): one BC1 lane and one batch-1 lane with `--head`. CPU, peak memory
   and run time per process go into `conf/hpc_dev.config` / `conf/hpc_prod.config`.

- Budget: all laptop tests together <= 5 min.

## Done when

- Stub and tool tests pass; `nf-core pipelines lint` has no failures.
- The DAG shows `CAT_FASTQ -> MINIBWA_MAP -> FGUMI_CLIP -> SAMTOOLS_FIXMATE -> SAMTOOLS_SORT -> SAMTOOLS_MARKDUP ->
  SAMTOOLS_INDEX` per sample.
- Resource numbers are in config, measured, one line per process.
- `decisions.md`, `docs/structure.md` and `meta/PROVENANCE.md` record this milestone's choices.
- The report lists the choices made during the work.
