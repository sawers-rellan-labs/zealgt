# Milestone 9g: no supplementary reads in variant calling

Every `variant_calling` step leaves out supplementary records (SAM flag 0x800): CRISP reads filtered copies of its
inputs, the four `bcftools mpileup` steps skip them with `--ff`. The `/rsstu` CRAMs stay whole.

## Why (user, 2026-10-17)

The production run (`docs/runs/variant_calling_production.md`) stopped twice on CRISP `Zl.0020_P3_chr1`
(segfault at 1.79 and 1.83 GB, jobs 1353412_10 and 1359025_14). Debug (`agent/crisp_debug/`): a use-after-free in CRISP
1a9027e. `evaluate_OPE_readpair` (`parsebam/variant.c:148-150`) links a read to any later record with its name, mate
position and opposite insert size without checking that record is already linked, and CRISP keeps supplementary
records (`readmultiplebams.c:68`), so a primary R1 and its supplementary both claim R2 and R1 later writes into the freed
R2 (valgrind: invalid write in `free_read_queue`). Such names exist in every CRAM checked (chr1: 108 in this witness,
4-20 per BC1 CRAM); the other tasks survived by luck. `samtools view -F 0x800` before CRISP finished the full chr1 task
(229,627 calls vs 234,635 with supplementary records; the lost calls have lower QUAL and sit more often near TE edges,
job 1365010). User: exclude supplementary records consistently across variant calling, always (no parameter).

## Changes

1. **CRISP inputs** (`subworkflows/local/cram_variant_discovery_crisp/main.nf`), nf-core `samtools/view` (installed
   with `nf-core modules install`; not in the repo yet) with `-F 0x800 --write-index`:
   - each BC1 CRAM once, whole genome (384 tasks in production), as `FILTER_BC1`;
   - each witness pool per region after `SAMTOOLS_ADDREPLACERG` (950 tasks), as `FILTER_WITNESS`, in place of its
     `SAMTOOLS_INDEX` (the B73 control pools keep theirs: they go only to mpileup).
2. **mpileup steps** (`conf/modules.config`): `--ff UNMAP,SECONDARY,QCFAIL,DUP,SUPPLEMENTARY` (bcftools' default plus
   supplementary) in `CHECK_COUNTS`, `BCFTOOLS_MPILEUP`, `COUNT_UNION` (whose counts feed `UNION_TIERS` and gap filling)
   and `COUNT_LINES`.
3. **Resources**: the two filter processes in `hpc_dev` and `hpc_prod` (arrays of 20 in `hpc_prod`), from the debug
   run (five chr1 CRAMs in 4.5 min) until measured; `docs/RESOURCES.md`.
4. **Docs**: `docs/decisions.md` (the user's decision), `docs/structure.md`, both metro maps (two processes).

## Choices this spec settles

- **Filter at the variant-calling input** (user, 2026-10-17). Rejected: at CRAM export (the archive would lose
  supplementary records for good, and the 2,173 existing CRAMs would need re-export).
- **Always on** (user, 2026-10-17). Rejected: a parameter (two code paths for an option nobody turns off). When a fixed
  CRISP is pinned, the filter steps come out; the `--ff` lines may stay for consistency.
- **Copies only for CRISP** (user, 2026-10-17): CRISP has no flag filter; mpileup has `--ff`. Rejected: filtered copies
  of every CRAM (about the alignment archive's size on `/share`).
- **BC1 copies whole genome, witness copies per region**: a BC1 CRAM serves all ten regions of its donor; the witness
  is already per region.

## Not in this milestone

- A fixed CRISP image and the upstream report (`vibansal/crisp`; reproducer being built in `agent/crisp_repro/`).
- The CRISP module's exit-code handling (todo: crashes exit 1, so they are not retried).
- The production run: resumed from the plan after the merge, with every CRISP and mpileup task rerun.

## Tests

1. **Tools** (laptop): `samtools view -F 0x800` on a fixture CRAM with supplementary records keeps every other record
   (counts by flag); mpileup with the new `--ff` drops the supplementary reads' bases from `AD` and nothing else.
2. **Wiring** (laptop, stubs): the two filter steps feed CRISP; DAG and metro maps.
3. **Hazel setup**: `nextflow config`, `inspect`, the process stubs, all at once (`scripts/run_hazel_tests.sbatch`).
4. **Review**: CodeRabbit on the commit range.
5. **Slice** (laptop, <= 15 min):
   - regression: `Zl.0020_P3`, chr1:211,200,000-211,450,000, its four BC1 CRAMs and witness lines, through discovery:
     CRISP finishes (it aborts on this window today);
   - the pilot slice through `variant_calling`: union, donor alleles and counts against `dev`, differences reported
     (expected small: supplementary reads leave the counts).
6. **Profile**: none apart; the production run measures the two filter steps.

## Done when

- Tests 1-5 pass; `nf-core pipelines lint` has no failures; docs above updated.
