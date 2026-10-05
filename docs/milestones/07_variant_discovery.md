# Milestone 7: variant discovery

First stage of `GENOTYPE`: per donor and chromosome, the sites where the donor haplotype carries a teosinte allele
(tier-A sites), from the donor's BC1 pools and its lines, inside the low-copy regions.

## Why (user, 2026-10-04)

"It is too much data to process and most of it is uninformative. Filtering lowers the need for computation and
filtering to lowcopy regions increases the fraction of signal against the repeat noise. 85% of the maize genome are
repeats, so most variants found in the alignment at this stage are still likely repeats (even after the MAPQ filters).
If the BC2S3 or BC1 samples were diploid individuals at high coverage I could use DeepVariant or GATK to filter out
low quality variants. I have pools, which are misspecified for DeepVariant and GATK variant calling pipelines."

## Inputs

- Per sample `[ meta, cram, crai ]` from `ALIGNMENT`: the donor's BC1 pools (`role` = BC1) and lines (`role` = BC2S3),
  `meta.donor`, rows with `exclude = TRUE` dropped. Samples under 0.05x (CollectWgsMetrics `MEAN_COVERAGE`) are dropped
  first (the coverage-filter row, inline in the workflow).
- `--fasta` with its `.fai`.
- `--lowcopy_bed` (new parameter): the low-copy BED, built once outside the pipeline (decision 2026-10-04).
- `--region` (new parameter, development scope): one chromosome or a window of it, `chr10` or `chr10:1-20000000`.
- `--check_sites` (new parameter): teosinte-vs-B73 panel sites for the B73 check filter, SNP50K `HQ_BZEA.vcf.gz` for now.
- `--max_check_alt_rate` (new parameter, default `0.01`): the B73 check filter's cut.
- B73 controls for the site error rate, as in zealbc1 (`docs/notebooks/02_donor_discovery_tiers_witness.qmd`):
  - the B73 check pool ("skim10"): the batch-1 B73 checks (`role` = check, pedigree `B73-bulk`), ordinary samples,
    merged in silico, without the checks that carry teosinte DNA (step 0 below);
  - NCBI B73 ERR3288215 (15.5x): not a sample of ours, so a reference input like a panel of normals (nf-core/sarek
    `--pon`): `--b73_controls`, a file listing its CRAM, aligned once with `ALIGNMENT` in a separate run.
- Tests: the Milestone 2 `tiny.fa` fixtures for wiring; a real-data slice for the tools (Tests).

## Outputs

Per donor and chromosome, in `genotype/discovery/`:

- `<donor>.<chr>.vcf.gz` + `.tbi`: CRISP's records inside the low-copy BED that the witness keeps.
- `<donor>.<chr>.sites.tsv.gz`: one row per site with pooled depth and ALT reads per pool, LLR, the flags
  (`af_gt_half`, `hidepth`, `inconsistent`) and the tier (`A`, `B`, `C`, `ref`, none). Tier-A sites feed the next rows (union,
  ancestry).

## Processes

Stage `CRAM_VARIANT_DISCOVERY_CRISP`, one task per donor and chromosome (`groupTuple` on `meta.donor`, the pool CRISP
needs); samples are routed by `role` with a channel `branch` (BC1 pools and lines per donor, B73 checks):

0. B73 check filter: `BCFTOOLS_MPILEUP` (nf-core, as `CHECK_COUNTS`) counts each B73 check at `--check_sites`
   (`-I -a AD -q 20 -Q 20`); a local module `CHECK_ALT_RATE` (`bcftools query` of the AD sums) gives its share of ALT
   reads; a channel `filter` keeps the checks at or below `--max_check_alt_rate`. The dropped checks are listed with
   their rate in `genotype/discovery/b73_checks.tsv`.
1. `SAMTOOLS_MERGE` (nf-core): the donor's line CRAMs in `--region` into one witness BAM; the same module merges
   the B73 checks into the B73 check pool.
2. `SAMTOOLS_ADDREPLACERG` (nf-core): one read group per merged pool (CRISP splits a file by read group).
3. `CRISP` (local module, container `ghcr.io/sawers-rellan-labs/zealgt-crisp:1a9027e`): the BC1 CRAMs plus the
   witness, `--bed <lowcopy, clipped to --region> --regions <chr> --sm 0 -p 12 --mmq 20 --mbq 20 --filterreads 0 --minc 2` (zealbc1, plus `--mbq 20`).
4. `BCFTOOLS_VIEW` as `BED_CLIP` (nf-core): `-T <lowcopy BED>`, which drops the base CRISP calls one past every range
   end (CRISP bug, vibansal/crisp#34).
5. `BCFTOOLS_VIEW` as `WITNESS_VETO` (nf-core): keeps a record if the witness has >= 1 ALT read, as a bcftools
   expression on the witness sample's allele counts.
6. `BCFTOOLS_MPILEUP` (nf-core): the two B73 controls (check pool, ERR3288215) at the kept sites, `-I -a AD -q 20 -Q 20`
   (decision 2026-10-02).
7. `POOLED_LIKELIHOOD_TIERS` (local module, own tool `bin/score_pooled_likelihood.py`): the pooled likelihood ratio
   per donor (math supplement Eq. `eq:llr`: 6 plants per BC1 pool, `j` marginalised), site error rate from non-carrier
   pools and the B73 controls, flags, tiers. Tier A: LLR >= 6.9, ALT reads in >= 2 BC1 pools, no `hidepth`, `af_gt_half` or `inconsistent` flag
   (`inconsistent`, as zealbc1: one BC1 pool with >= 3 ALT reads while another has >= 10 reads and none ALT).

## Files

- `subworkflows/local/cram_variant_discovery_crisp/main.nf` (new): the wiring above.
- `modules/local/crisp/main.nf`, `modules/local/pooled_likelihood_tiers/main.nf` (new); the tool is a `path` input
  called through `python3` (decision on own tools, `docs/structure.md`).
- `bin/score_pooled_likelihood.py` (new) with its unit tests and fixtures.
- `modules/nf-core/{samtools/merge,samtools/addreplacerg,bcftools/view,bcftools/mpileup}/`: installed.
- `workflows/genotype.nf` (new), `main.nf` (`--step genotype`), `conf/modules.config` (`ext.args`),
  `conf/hpc_dev.config`, `conf/hpc_prod.config`, `nextflow_schema.json` (the new parameters).
- `modules/local/check_alt_rate/main.nf` (new): one `bcftools query`, ALT and total reads per check.

## Choices this spec settles (yours to confirm)

- **CRISP for discovery** (user: pools). Rejected: GATK HaplotypeCaller, DeepVariant, `bcftools call`, which assume
  diploid individuals.
- **Low-copy regions only**, through CRISP `--bed` and `BED_CLIP`. Rejected: the whole chromosome.
- **One path: zealbc1's step-4 values in `conf/modules.config` (`ext.args`), not pipeline parameters.** Rejected:
  zealgt-old's ~20 `--tier_*` pipeline parameters and input modes.
- **zealbc1's two B73 controls**, for the precedent check and for depth (a site error rate needs >= 20 B73 reads).
  The check pool flows from the samplesheet; ERR3288215 is a reference input (`--b73_controls`). Rejected: the B73
  checks one by one (about 0.4x each); the batch-2 B73 checks (zealbc1 did not use them); ERR3288215 as a samplesheet
  row, which is not a sample.
- **Witness veto as a bcftools expression.** Rejected: zealgt-old's `veto_by_witness.py`; it comes back only if the
  tool test shows bcftools cannot sum the witness's ALT counts in CRISP's format fields.
- **Witness built with nf-core `samtools/merge` + `samtools/addreplacerg`**, limited to one chromosome. Rejected:
  zealgt-old's local piped module; at one chromosome the intermediate is about 100 MB.
- **No annotation panels in step 4** (user). They only added columns and cost 2.4 GB of memory (zealgt-old); the
  comparison panels belong to the simulation QC (Not in this milestone).
- **CRISP `--mbq 20`** (user), the same base-quality floor as `bcftools mpileup -Q 20`. Rejected: CRISP's default
  `--mbq 10`, which keeps batch 1's Q11 bases.
- **B73 checks filtered by a fixed share of ALT reads, 1 % (user), a parameter; no hypothesis test.** At the SNP50K
  sites clean batch-1 checks show 0.08-0.49 % ALT reads, PN5_SID468 2.76 % and PN3_SID236 1.92 % (hazel job 1095438),
  the two zealbc1 dropped by hand. Rejected: hand-set `exclude` rows; a leave-one-out binomial test against the other
  checks (same result, harder to explain); a test against ERR3288215's rate (0.066 %), which flags 9 of 12 checks
  because B73 seed stocks differ from the reference (Liang & Schnable 2016, PLoS ONE 11:e0157942).

## Not in this milestone

- The union of donors and gap filling, ancestry, projection: the next rows.
- Identity QC (`docs/later/genotype_identity_qc.md`).
- The simulation QC (user: a separate task) that estimates and justifies the pipeline on simulated founders
  (math supplement, "Benchmark": the QC set of Gigi and TIL18), with the comparison panels it needs.

## Data for this milestone

Debugging data only (handover 2026-10-04: one donor, a handful of samples, one window, `--head`, `hpc_dev`):
Zx.0540_P3's 2 BC1 pools and 4 lines; three batch-1 B73 checks (PN5_SID468, PN3_SID236 and one clean check, so the
filter is tested); ERR3288215 (FASTQs at `ZEAL/raw/B73_control/ERR3288215/`, from zealbc1). All go through `--step alignment` with `--head` first. The full data
(the pilot's 94 samples, all 12 B73 checks, ERR3288215 aligned in full, about 3 h 21 min) belongs to the pilot run
plan in `docs/runs/`, with the whole-chromosome run and the precedent check against zealbc1.

## Tests

1. **Tool** (laptop): `score_pooled_likelihood.py` on small fixtures with hand-computed LLRs and tiers; reference
   answers from zealbc1's step-4 table for Zx.0540_P3 (post-fix rerun, job 949447) on a few hundred sites. The veto
   expression on a small CRISP VCF with known witness counts.
2. **Wiring** (laptop, stubs, seconds): one discovery task per donor, one B73 check pool, one mpileup task per B73 control, the DAG.
3. **Slice** (laptop, real data, <= 15 min): the milestone's samples, chr10:1-5 Mb, Docker.
4. **Cluster** (hazel, `hpc_dev`, < 30 min): `-stub-run`, then the milestone's samples on chr10:1-20 Mb for the
   resource profile. A bug check, not an accuracy check: no comparison with zealbc1 on a window.

## Done when

- Tool, stub and slice tests pass; `nf-core pipelines lint` has no failures.
- The hazel run on chr10:1-20 Mb wrote the VCF, the site table and `b73_checks.tsv`; resources are in config.
- The B73 check filter drops PN5_SID468 and PN3_SID236 and keeps the clean check.
- `docs/structure.md` marks the row "built (milestone 7)"; `decisions.md` holds only the choices you confirm.
