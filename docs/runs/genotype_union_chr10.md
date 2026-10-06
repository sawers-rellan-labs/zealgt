# Run plan: GENOTYPE sites union and gap filling, pilot donors, whole chr10

## Why

User, 2026-10-05: run the union and gap filling (Milestone 8) on the whole chromosome before the full population; the
20 Mb runs of Milestone 8 checked for bugs only. The Milestone 8 spec leaves this run, against zealbc1's gap filling
(§3.2 of its notebook 06), to a run plan.

## Inputs and outputs

- The pilot's inputs, unchanged (`genotype_pilot_chr10.md`): `docs/runs/genotype_pilot_chr10/samplesheet.csv` (106
  rows; Zx.0540_P3 and Zx.0570_P2, 5 BC1 samples each, their lines, the 12 batch-1 B73 checks), `b73_controls.csv`
  (`B73_ERR3288215`), `ZEAL/reference/lowcopy_chr10.bed`, `HQ_BZEA.vcf.gz`, `--region chr10`. Only these two donors'
  BC1 samples are aligned; the full population waits for their alignment.
- Outputs, `--outdir /share/maize/frodrig4/nf_work/zealgt_dev/genotype_union_chr10/results`: `genotype/discovery/` as
  in the pilot, and `genotype/union/chr10.union.vcf.gz` and `chr10.donor_alleles.vcf.gz` (each with `.tbi`).

## Settings

- `hpc_dev`, launch directory `nf_work/zealgt_dev`, `work/` kept, outputs hard-linked on `/share`.
- Code: `dev` at 42116ef (Milestone 8 merged); the hazel checkout `ZEAL/zealgt` switched back to `dev` and pulled.
- Prior of Eq. `eb` from all other donors (flat); with two mexicana donors the PCA-cluster groups would give the same.
- `-resume aa121700-7d24-4221-9259-d477dd4f82df` (the pilot run, job 1108956, same inputs and region): CRISP, the pools and the B73 checks come
  from its cache; `POOLED_LIKELIHOOD_TIERS` (new container and output) and the union steps run.
- Command (from `ZEAL/zealgt`):

```
sbatch scripts/submit_head_job.sbatch hpc_dev --step genotype \
  --input /rsstu/users/r/rrellan/BZea/ZEAL/zealgt/docs/runs/genotype_pilot_chr10/samplesheet.csv \
  --b73_controls /rsstu/users/r/rrellan/BZea/ZEAL/zealgt/docs/runs/genotype_pilot_chr10/b73_controls.csv \
  --lowcopy_bed /rsstu/users/r/rrellan/BZea/ZEAL/reference/lowcopy_chr10.bed \
  --check_sites /rsstu/users/r/rrellan/BZea/bzeaseq/nilhmm/vcf/HQ_BZEA.vcf.gz \
  --region chr10 --outdir /share/maize/frodrig4/nf_work/zealgt_dev/genotype_union_chr10/results \
  -resume aa121700-7d24-4221-9259-d477dd4f82df
```

## Size

- chr10:1-20 Mb (job 1111002): union steps under 7 s and 250 MB each; whole chr10 is 7.6 times longer, so
  `COUNT_UNION` about 1 min per sample, the rest seconds. Placeholders (1 cpu, 1 GB, 1 h) cover it.
- Union sites: about 8,000 on 20 Mb; whole chr10 about 60,000 (zealbc1: 82,706 from its larger tier-A sets).
- Wall time about 10-20 min with queueing; `/share` well under 1 GB.

## Expected

- Two donors, one union, 12 `COUNT_UNION` tasks (10 BC1 samples, 2 B73 controls), one `FILL_DONOR_ALLELES`.
- μ_d per donor inside the panel range for mexicana (Text S5, Eq. `panelprior`): between d = 0.31 and c = 0.66; on
  20 Mb 0.52 and 0.44.

## Checks after the run (bugs, not accuracy)

- Counts per donor of own ALT / own missing / gap ALT / gap REF / gap missing, as on 20 Mb.
- Against zealbc1 (`ZEAL/results/union_zx0540_zx0570_chr10/counts/bayes/dhd_bayes_chr10.tsv.gz`), on the union sites
  both hold: agreement of the donor allele per donor, and the cross-table of disagreements. Known difference: our
  discovery tier A matches zealbc1's at Jaccard 0.60 (duplicates marked, `genotype_pilot_chr10.md`), so the unions
  differ; own sites without support are missing here and ALT in zealbc1.

## Done when

- The run succeeded; the four union files are published; the counts, μ_d and the zealbc1 comparison are in Attempts.

## Attempts

- 2026-10-05 20:19, head job 1111642 (dev 42116ef): **succeeded** in 26 min. The short session id `aa121700` did not
  resolve to the pilot (Nextflow took the last session), so discovery ran again (CRISP 12 min); the full id is in the
  command above. 70,210 union sites (zealbc1 82,706; 60,174 shared).
  - Zx.0540_P3: 32,750 own sites, μ_d 0.572; own ALT 29,009, missing 3,686; gap ALT 15,771, REF 10,361, missing 11,383.
  - Zx.0570_P2: 48,251 own sites, μ_d 0.364; own ALT 41,292, missing 6,904; gap ALT 5,700, REF 8,612, missing 7,702.
  - μ_d of both inside the mexicana panel range [0.31, 0.66].
  - Against zealbc1 on shared sites: the same call at 0.904 and 0.885 of the sites. Where both call, 22 and 18 ALT/REF
    conflicts in about 47,000 sites; most disagreements are ours missing where zealbc1 says ALT (own sites without
    support: 2,484 and 4,684). Union processes under 40 s and 250 MB each.
