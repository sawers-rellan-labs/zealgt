# Milestone 8: sites union and gap filling

Second stage of `GENOTYPE` (`SITES_UNION_GAPFILL` in `docs/structure.md`): one site list for all donors, and each
donor's allele at every site of it.

## Why (user, 2026-10-05)

The union step in this pipeline is analogous to the joint genotyping step in GATK (Van der Auwera, "Should I analyze my
samples alone or together?", GATK documentation, `broadinstitute/gatk-docs`).

Donors are not identical. Teosinte and maize carry standing variation, so each donor shares a different part of its
genome with B73, and a site that is informative in one cross is uninformative in another. In a 217-sample teosinte panel
(Grzybowski et al. 2023), a donor plant carries the B73 allele at about 60 % of the panel's variant sites, and the gamete
it passes to the cross at about 70 % ([zealhmm: SNP50K genotype identifiability, §2.3](https://sawers-rellan-labs.github.io/zealhmm/analysis/snp50k_genotype_identifiability.html#panel-data)).
Discovery finds each donor's sites from that donor's reads alone. Genotyping every donor at the union of all donors'
sites brings three benefits:

1. **A clear difference between a B73 allele and missing data.** A donor without a record at a site is either identical
   to B73 there (uninformative) or not covered. Only a call for every donor at every site of the union tells the two
   apart.
2. **Greater sensitivity for weakly supported donor alleles.** A donor allele backed by only a few ALT reads can be
   rescued when the same site is variant elsewhere in the population (other donors, the NIL lines).
3. **Greater ability to remove false positives.** A donor ALT call made on little evidence, at a site with no sign of
   variation anywhere in the population, is likely an error and is set to missing.

References:

- Grzybowski MW, Mural RV, Xu G, Turkus J, Yang J, Schnable JC (2023). A common resequencing-based genetic marker data
  set for global maize diversity. The Plant Journal 113(6):1109-1121. doi:10.1111/tpj.16123.
- Van der Auwera G. Should I analyze my samples alone or together? GATK documentation (GATK 3 FAQs,
  github.com/broadinstitute/gatk-docs).

## Scope

Gap filling step 1 of the math supplement (Text S5, Eq. `eb`): the donor's own BC1 reads, with a prior raised by the
other donors. Step 2 (evidence from the lines, Eq. `step2`) needs each line's ancestry, so it comes after
`CRAM_ANCESTRY_RTIGER` as its own row (Not in this milestone).

## Inputs

- From `CRAM_VARIANT_DISCOVERY_CRISP`, per donor: its high-confidence (tier-A) sites, and the B73 controls (check pool,
  ERR3288215) as merged CRAMs; the subworkflow emits both (new emits).
- Per donor: its BC1 CRAMs (`role` = bc1_sample, the coverage filter already applied).
- `--fasta`, `--region` as in Milestone 7.

## Outputs

Per chromosome, in `genotype/union/`:

- `<chr>.union.vcf.gz` + `.tbi`: the union sites (biallelic SNPs, no samples).
- `<chr>.donor_alleles.vcf.gz` + `.tbi`: one sample per donor; `GT` = `1` (ALT), `0` (REF) or `.` (missing); `FORMAT`
  `LLR` (donor's reads), `PRIOR`, `PALT` (posterior probability of ALT; `PP` is reserved in VCF for genotype posteriors), `SRC` (`own` or `gap`).

## Processes

Stage `SITES_UNION_GAPFILL`, one union per chromosome over all donors:

1. `POOLED_LIKELIHOOD_TIERS` (Milestone 7) also writes the donor's tier-A sites as a sites-only VCF (`--tier-a-vcf`).
2. `BCFTOOLS_MERGE` (nf-core, `-m none`, sites only) -> `BCFTOOLS_NORM` (nf-core, `-m +snps`: different ALTs at one
   position become one record) -> `BCFTOOLS_VIEW` (nf-core, `-m2 -M2 -v snps`: drops them, Text S5) = `MARKER_UNION`.
3. `BCFTOOLS_MPILEUP` (nf-core) as `COUNT_UNION`: each donor's BC1 CRAMs and each B73 control at every union site,
   `-I -a AD -q 20 -Q 20` (duplicates skipped by default), one task per donor and per control.
4. `POOLED_LIKELIHOOD_TIERS` as `UNION_TIERS`: each donor scored at every union site from those counts (new input mode
   `--bc1-vcf`: per-sample `AD` from mpileup instead of CRISP's pools; no witness veto, Text S5).
5. `FILL_DONOR_ALLELES` (local module, own tool `bin/fill_donor_alleles.py`): all donors' union tables in, the donor
   alleles out, by Eq. `eb`: prior `pi = (w mu_d + k) / (w + m)` from the other donors (`k` with ALT, `m` with a call),
   `w = 2`, `mu_d` the donor's sharing rate; ALT at posterior >= 0.999, REF at tier `ref`, else missing; sites flagged
   too deep or over half variant reads are never promoted to ALT. Values in `conf/modules.config` (`ext.args`).

## Choices this spec settles (yours to confirm)

- **Step 1 only; step 2 after ancestry, one pass** (user). Ancestry comes from the donors' own sites; filled sites never
  go back into RTIGER. Rejected: step 2 here (it needs ancestry); iterating ancestry and gap filling (circular).
- **Own sites re-scored with the population prior** (benefit 3): an own tier-A site whose posterior falls below 0.999
  becomes missing. Rejected: setting it to REF (its reads give no evidence for B73); not re-scoring own sites
  (zealbc1, Text S5 as written; S5 is updated if this is confirmed).
- **Prior from all other donors.** Rejected: other donors of the same taxon only (zealbc1's option); the pilot donors
  are both mexicana, so the two agree until other taxa are added.
- **Counted once with mpileup at every union site, own sites included.** Rejected: CRISP's counts for own sites and
  mpileup for gaps (two counting rules in one table).
- **Positions with different ALT alleles in different donors dropped** (Text S5). Rejected: keeping multi-allelic
  sites, which the ancestry-times-allele projection cannot use.
- **Union with nf-core bcftools modules; own tool only for Eq. `eb`**, which no established tool computes.

## Not in this milestone

- Step 2, evidence from the lines: a new row after `CRAM_ANCESTRY_RTIGER` in `docs/structure.md`.
- PHG (later, the comparison method): its union founder takes the step-1 alleles only, so PHG stays independent of
  RTIGER's ancestry (user, 2026-10-05).

## Tests

1. **Tool** (laptop): `fill_donor_alleles.py` on small fixtures with hand-computed priors and posteriors; reference
   answers from zealbc1's `dhd_bayes.py` on the chr10 pilot (`ZEAL/results/union_zx0540_zx0570_chr10/counts/`) on a
   few hundred sites. `score_pooled_likelihood.py --bc1-vcf` against its CRISP mode on the same counts.
2. **Wiring** (laptop, stubs, seconds): two donors, one union per chromosome, one count task per donor and control, the
   DAG.
3. **Slice** (laptop, real data, <= 15 min): both pilot donors, chr10:1-5 Mb, Docker.
4. **Cluster** (hazel, `hpc_dev`, < 30 min): `-stub-run`, then both pilot donors on chr10:1-20 Mb for the resource
   profile. A bug check; the whole chr10 against zealbc1's gap filling (§3.2 of its notebook 06) is a run plan.

## Done when

- Tool, stub and slice tests pass; `nf-core pipelines lint` has no failures.
- The hazel run on chr10:1-20 Mb wrote the union and the donor alleles; resources are in config.
- `docs/structure.md`: this row "built (milestone 8)", the step-2 row added; Text S5 matches the choices confirmed.
