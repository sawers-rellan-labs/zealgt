# Later: identity QC of the lines (labelling and pollination errors)

Added after the main GENOTYPE pipeline works (user, 2026-10-04). Assumes no errors at the BC1 stage (user).

## Panel: WSGENE50K

- Wideseq sites (Schnable 2023 teosinte-vs-B73 SNPs, `bzeaseq/wideseq_ref/wideseq_chr*.vcf.gz`, 27.6 M) inside B73 v5
  `gene` features (`Zm-B73-REFERENCE-NAM-5.0_Zm00001eb.1.gff3`, merged: 36,391 intervals, 173 Mb): 2,960,128 sites.
- `bcftools +prune -n 1 -N 1st -w 4500bp` per chromosome: **49,722** sites. Windows 40, 20, 15, 10, 5, 4 kb gave 19,034,
  24,288, 27,020, 32,126, 46,573, 53,636 (hazel jobs 1090853, 1090944, 1090964).
- Built once outside the pipeline; the pipeline takes it as an input SNP set.
- Expected per line at about 0.4x: about 70 % of sites missing (SNP50K batch 1: median 69 %, about 15,000 covered sites;
  floor model rpubs.com/faustovrz/1337797).

## What the PCA test showed (batch 1, SNP50K, PCAngsd 1.36.4)

- Input: `50K/results/joint/cohort.vcf.gz` PL -> ANGSD 0.940 `-vcf-pl -doGlf 2` -> PCAngsd `--maf 0.05`; Purple checks
  excluded; anchors TIL11, TIL25, RIL003, RIMH001, Ame2317 (zealbc1 `nilhmm/docs/reference_anchors.md`) and the panel
  B73 added from panel GT. Results: `/rsstu/users/r/rrellan/BZea/ZEAL/zealgt_qc/`.
- A simulated BC2S3 population (`nilHMM::simulate_nil`, real depths, genotype = ancestry x donor allele) gives the same
  pattern, apart from a tilted B73-teosinte axis in the real data. The genome-wide PCA describes structure; it does not
  flag individual lines. Found: B73 check PN5_SID468 contaminated, PN3_SID236 borderline.
- Cohort MAF >= 0.05 keeps 13 % of SNP50K sites; for WSGENE50K's genic pool, panel frequency >= 0.4 (cohort about
  panel / 8) keeps 507,674 of 2,960,128.

## Proposed checks, per line

Before discovery (keep wrong lines out of the witness and discovery):

1. Allele sharing with the own donor, leave-one-out: pool the other lines of the donor at the panel sites; a line's alt
   reads should fall where its own donor group has alts more than where any other donor group has them.
2. Donor content: share of alt reads against 12.5 %; near 0 = B73 seed or selfed check, well above = missed backcross
   or outcross.

After discovery and RTIGER (the donor haplotype H_d is known):

3. Concordance with H_d inside the line's teosinte segments: alt at the donor's ALT sites, none at sites where the donor
   is REF and other donors are ALT ("foreign" alleles = another donor or its pollen).
4. Teosinte and het fractions against BC2S3 expectations (12.5 % donor allele, 3.1 % het, 10.9 % homozygous donor), with
   the spread taken from the simulation.

Scratch scripts of the test: `agent/panel_test/` (not tracked).
