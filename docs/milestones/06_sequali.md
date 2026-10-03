# Milestone 6: read QC with Sequali in alignment

## Why

User, 2026-10-03: as nf-core/sarek (`workflows/sarek.nf:194-197`) and nf-core/variantcatalogue
(`workflows/variantcatalogue.nf:164`, `:369`) do with FastQC, read QC runs on the FASTQs the alignment receives and
goes into its MultiQC report, because the steps before it do no read QC.

## Inputs and outputs

- Input: each sample's FASTQ pair from the samplesheet, after `SEQKIT_HEAD` on `--head` test runs.
- Output per sample: `<sample_id>.html` and `<sample_id>.json`, one report for the pair, published to `cram/` next to
  the CRAM and its other QC (decision "CRAM QC": QC files go to `cram/`).
- The JSON goes into the alignment's MultiQC report (MultiQC's Sequali module, since MultiQC 1.22).

## Process

`SEQUALI` (nf-core `sequali`, Sequali 1.0.2, to install unpatched), called inline in `ALIGNMENT`: one task per sample,
in parallel with `MINIBWA_MAP` on the same reads.

## Choices this spec settles

- **Sequali** (user, 2026-10-03). It reads the pair together: adapters by overlap, insert sizes, per-tile quality,
  duplication estimate, overrepresented sequences against UniVec. Its README states "<2 GB of memory and 3-30 minutes
  runtime when run on 2 cores".
  - Rejected: FastQC (sarek's choice): each file on its own, slower.
  - Rejected: falco (nf-core/demultiplex's choice): the same reports as FastQC.
  - Rejected: fastp: its job is trimming, and we don't trim (decision "No adapter trimming").
- **In `ALIGNMENT`, on its input.** Rejected: in `DEMULTIPLEX`, where no QC report is made.
- **Always on.** Rejected: a `--skip_tools` switch, until a run needs it.

## Tests

1. Wiring (laptop, stubs): the alignment stub test counts one `SEQUALI` task per sample (6) and its published files.
2. Tool (laptop, Docker): the MultiQC test lists Sequali among its sources for the 6 kept samples.
3. Cluster wiring (hazel): `hpc_dev` stub of `--step alignment` on the 2-sample BZea5 sheet.
4. Resources (hazel, <= 30 min): `--step alignment` on PN5_SID464 and PN5_SID465 (BZea5, 4 M-pair head). CPU, memory
   and time per pair, scaled to the deepest bc1 samples (~300 M pairs), into `conf/hpc_dev.config` and
   `conf/hpc_prod.config`.

- Laptop tests together <= 5 min.

## Done when

- Tests pass; `nf-core pipelines lint` has no failures.
- The DAG shows `SEQUALI` per sample feeding `MULTIQC`.
- Resource lines measured; `structure.md` and the full map list `SEQUALI`.
