# Run plan: GENOTYPE chr10, every diploperennis donor

DRAFT, 2026-10-14.

## Why

User, 2026-10-14:

- a run for all the diploperennis donors, in parallel with the mexicana run (`genotype_mexicana_chr10.md`);
- one union per taxon, all donors in it, with accounting and QC of the union sites afterwards;
- results copied to `ZEAL/genotype`.

## Inputs

- `docs/runs/genotype_diploperennis_chr10/samplesheet.csv` (written by `agent/genochr10/write_sheets.py` from
  `meta/samples.csv`):
  - every not-excluded diploperennis `bc1_sample` and `nil`: 281 samples of 6 donors (25 BC1 pools, 256 lines);
  - the same 23 B73 checks.
- All 281 aligned by the diploperennis chain (`alignment_diploperennis.md`). Every CRAM, index and CollectWgsMetrics
  file is in `ZEAL/alignment/cram/` (checked on hazel 2026-10-14).
- `b73_controls.csv`: `B73_ERR3288215`.

## Before the run

The two changes on branch `runs-genotype-chr10-taxa` (`genotype_mexicana_chr10.md`, "Before the run"): 4 GB for the
three union processes, and `ZEALGT_LAUNCH` for `hpc_dev`.

Then a `-stub-run` of this sheet in this run's launch directory (minutes).

## Run

A new run from the same hazel checkout, beside the mexicana run, in its own launch directory `nf_work/zealgt_dev_dip`
(user, 2026-10-14): its own `.nextflow.log`, cache and `work/`. The 23 B73 checks' tasks run again here (another cache).

```
cd /rsstu/users/r/rrellan/BZea/ZEAL/zealgt
B=/rsstu/users/r/rrellan/BZea
S=/rsstu/users/r/rrellan/BZea/ZEAL/zealgt/docs/runs/genotype_diploperennis_chr10
sbatch --parsable --partition=compute --qos=normal --time=12:00:00 --mem=16G \
  --export=ALL,ZEALGT_LAUNCH=/share/maize/frodrig4/nf_work/zealgt_dev_dip,NXF_OPTS="-Xms1g -Xmx12g" \
  scripts/submit_head_job.sbatch hpc_dev --step genotype \
  --input $S/samplesheet.csv --b73_controls $S/b73_controls.csv \
  --lowcopy_bed $B/ZEAL/reference/lowcopy_chr10.bed \
  --check_sites $B/bzeaseq/nilhmm/vcf/HQ_BZEA.vcf.gz \
  --region chr10 --outdir /share/maize/frodrig4/nf_work/zealgt_dev_dip/genotype_diploperennis_chr10/results
```

Estimate: six donors and 304 samples, about as attempt 1 of the union test (six donors); ~1-2 h. The two runs together
use 80 jobs at most (`queueSize` 40 each), small tasks, beside the parviglumis alignment chain. Tasks past the QOS's
1,024 CPUs queue; they do not fail.

## After the run

1. **Copy** `results/` to `/rsstu/users/r/rrellan/BZea/ZEAL/genotype/diploperennis_chr10/` (a `cp -r` in a short Slurm
   job).
2. **Accounting of the union**, as the mexicana run: union sites; per donor tier-A, private and shared sites; per donor
   union-ALT markers split into own tier-A and gap-filled sites.
3. **Problem-family screen** of the six donors, as the mexicana run.
4. **QC of the union sites**, as the mexicana run, with two changes:
   - the baseline is the private sites of the donors the screen passes;
   - the assembly check uses Gigi's chr10 alignment (`phg_pilot/chr10/maf/`).
5. **User decision** on Milestone 9b for this taxon, from the screen and the QC.

## Checks (bugs, not accuracy)

- First diploperennis donors through GENOTYPE: per donor tier-A sites, union-ALT markers, `line_checks.tsv`, next to the
  mexicana donors' ranges.
- Fewer tier-A sites per donor than mexicana are expected from mapping bias alone: Gigi's simulated chr10 reads kept
  20 % at MAPQ >= 20, TIL18's 35 % (`math_supplement.tex`, Text S5).
- The B73 checks free of donor segments.

## Done when

- The run succeeds.
- A results note here: the accounting, the screen, the QC and the user's decision on 9b.
- Time and peak per process in `docs/RESOURCES.md`.
- Results copied to `ZEAL/genotype/diploperennis_chr10/`.
- `nf_work/zealgt_dev_dip` on the user's cleanup list once results are kept.
