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
   variation anywhere in the population, is likely an error and is set back to REF.

References:

- Grzybowski MW, Mural RV, Xu G, Turkus J, Yang J, Schnable JC (2023). A common resequencing-based genetic marker data
  set for global maize diversity. The Plant Journal 113(6):1109-1121. doi:10.1111/tpj.16123.
- Van der Auwera G. Should I analyze my samples alone or together? GATK documentation (GATK 3 FAQs,
  github.com/broadinstitute/gatk-docs).
