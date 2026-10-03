# Milestone 6: read QC with Sequali

## Why

User, 2026-10-03: as nf-core/sarek (`workflows/sarek.nf:194-197`) and nf-core/variantcatalogue
(`workflows/variantcatalogue.nf:164`, `:369`) do with FastQC, read QC runs on the FASTQs and goes into a MultiQC
report. It runs where the FASTQs are made, at the end of demultiplexing, and again at the start of alignment only when
asked, for FASTQs that come from elsewhere.

## Stage

`FASTQ_SEQUALI` (local subworkflow): `SEQUALI` per sample (nf-core `sequali`, Sequali 1.0.2, unpatched), then one
`MULTIQC` (nf-core) over the Sequali JSON files.

- `DEMULTIPLEX`: always, on each kept sample's joined FASTQ pair.
- `ALIGNMENT`: only with `--read_qc` (default false), on the FASTQ pairs it reads, after `SEQKIT_HEAD` on `--head` test
  runs. The switch is a channel filter, so with the flag off no task runs.

## Outputs

- `reports/sequali/<sample_id>.{html,json}`, one report per FASTQ pair.
- `multiqc/reads/multiqc_report.html`: the read-QC report, one per run.
- The alignment's CRAM report (`multiqc/`) is unchanged.

## Choices this spec settles

- **Sequali** (user). It reads the pair together: adapters by overlap, insert sizes, per-tile quality, duplication
  estimate, overrepresented sequences against UniVec.
  - Rejected: FastQC (sarek's choice): each file on its own, slower.
  - Rejected: falco: the same reports as FastQC.
  - Rejected: fastp: its job is trimming, and we don't trim.
- **`FASTQ_SEQUALI`**, named after the tool (user). Rejected: `FASTQ_QC_SEQUALI`, the `<input>_<operation>_<tool>` rule,
  less clear about the tool.
- **In alignment, a flag, not "run if the reports are missing"** (user). Rejected: pipeline code that checks for
  existing reports.
- **fqtk's metrics stay out of MultiQC** (user). MultiQC has no fqtk module, and its custom content would keep only one
  lane per sample (fqtk writes one file per lane with the same sample names). They stay published in `reports/demux/`.

## Tests

1. Wiring (laptop, stubs):
   - `--step demultiplex`: 6 `SEQUALI` tasks, 1 read-QC `MULTIQC`, and the published report files;
   - `--step alignment --read_qc`: 6 `SEQUALI` tasks and 2 `MULTIQC` (reads, CRAMs);
   - `--step alignment` without the flag: no `SEQUALI`.
2. Tool (laptop, Docker): nf-test of `FASTQ_SEQUALI` on the tracked fixture FASTQs; MultiQC lists Sequali for the 6
   samples.
3. Cluster wiring (hazel): `hpc_dev` stubs of both steps on the BZea5 sheets.
4. Resources (hazel, <= 30 min): Sequali on the 2 BZea5 samples (4 M-pair head) and, if the time allows, one full 1C
   sample from the measurement (~240 M pairs); lines into `conf/hpc_dev.config` and `conf/hpc_prod.config`.

- Laptop tests together <= 5 min.

## Done when

- Tests pass; `nf-core pipelines lint` has no failures.
- The DAG shows `CAT_FASTQ -> SEQUALI -> MULTIQC` in demultiplexing.
- Resource lines measured; `structure.md` and the full map list `SEQUALI`.
