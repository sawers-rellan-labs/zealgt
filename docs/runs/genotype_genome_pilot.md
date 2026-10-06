# Run plan: GENOTYPE discovery, union and gap filling, pilot donors, whole genome

## Why

User, 2026-10-05: preliminary whole-genome results for the two pilot donors by the next morning, after the chr10 run
(`genotype_union_chr10.md`); one run per chromosome, since the pipeline takes one `--region` (a per-chromosome fan-out
in one run is a milestone, not done).

## Inputs and outputs

- The pilot's inputs (`genotype_pilot_chr10.md`): `docs/runs/genotype_pilot_chr10/samplesheet.csv` (106 rows),
  `b73_controls.csv`, `HQ_BZEA.vcf.gz`.
- `--lowcopy_bed ZEAL/reference/lowcopy_chr1-10.bed`: the chr10 BED's recipe on chr1-chr10 (genes ± 500 bp union TE
  complement, merged at 200 bp, ranges ≥ 500 bp; `agent/m8/genome/build_lowcopy_genome.sbatch`, job 1111677); its chr10
  ranges equal `lowcopy_chr10.bed`; 112,812 ranges, 367 Mb (chr1 16,912 ranges and 55.7 Mb to chr10 8,084 and
  26.1 Mb); sha256 `6c30d8d1…` in the `.sha256` next to it.
- Outputs per chromosome, `--outdir /share/maize/frodrig4/nf_work/zealgt_dev/genotype_genome/<chr>/results`:
  `genotype/discovery/` and `genotype/union/<chr>.{union,donor_alleles}.vcf.gz` (+ `.tbi`).
- chr10 is the run of `genotype_union_chr10.md` (job 1111642); not repeated.

## Settings

- `hpc_dev`, launch directory `nf_work/zealgt_dev`, code `dev` (checkout `ZEAL/zealgt`), prior from all other donors.
- Nine head jobs, chr1-chr9, the first after the chr10 run (job 1111642), each starting after the previous one ends (`--dependency=afterany`: one launch directory
  holds one run at a time; a failed chromosome does not stop the others). No `-resume` (new regions).
- Command (from `ZEAL/zealgt`):

```
prev=
for chr in chr1 chr2 chr3 chr4 chr5 chr6 chr7 chr8 chr9; do
  prev=$(sbatch --parsable ${prev:+--dependency=afterany:$prev} scripts/submit_head_job.sbatch hpc_dev --step genotype \
    --input /rsstu/users/r/rrellan/BZea/ZEAL/zealgt/docs/runs/genotype_pilot_chr10/samplesheet.csv \
    --b73_controls /rsstu/users/r/rrellan/BZea/ZEAL/zealgt/docs/runs/genotype_pilot_chr10/b73_controls.csv \
    --lowcopy_bed /rsstu/users/r/rrellan/BZea/ZEAL/reference/lowcopy_chr1-10.bed \
    --check_sites /rsstu/users/r/rrellan/BZea/bzeaseq/nilhmm/vcf/HQ_BZEA.vcf.gz \
    --region $chr --outdir /share/maize/frodrig4/nf_work/zealgt_dev/genotype_genome/$chr/results)
  echo "$chr $prev"
done
```

## Size

- chr10 (152 Mb): the pilot discovery took 21 min (CRISP 12 min, 379 MB); the union steps a few minutes. Per
  chromosome about 20-40 min (chr1, 308 Mb, the longest), so about 4-6 h for the nine, in sequence.
- Head jobs within the short QOS's 2 h; tasks within the `hpc_dev` placeholders (CRISP 16 GB, 2 h).
- `/share`: under 10 GB per chromosome in `work/` (chr10 pilot), outputs a few MB.

## Expected

- Per chromosome as for chr10: two discovery tasks, one union, 12 `COUNT_UNION` tasks, one `FILL_DONOR_ALLELES`.
- μ_d per donor and chromosome inside the mexicana panel range [0.31, 0.66] (Text S5, Eq. `panelprior`).

## Checks after the run (bugs, not accuracy)

- Every chromosome succeeded; per chromosome and donor: tier-A sites, union sites, and own/gap ALT, REF, missing.
- μ_d per chromosome and donor; a chromosome far from the others is flagged.

## Done when

- The nine runs succeeded and the counts per chromosome are in Attempts.

## Attempts
