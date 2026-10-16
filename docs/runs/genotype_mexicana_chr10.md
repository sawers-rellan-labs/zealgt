# Run plan: GENOTYPE chr10, every mexicana donor

DRAFT, 2026-10-14.

## Why

User, 2026-10-11: chr10 for all mexicana donors at union-ALT markers, once the eight aligned donors had settled the rule
(Milestone 9a, merged). User, 2026-10-14:

- resume the mexicana run, with genotypes before noon;
- one union per taxon (diploperennis: `genotype_diploperennis_chr10.md`, in parallel);
- all donors in the union for now, with accounting and QC of the union sites afterwards; the problem families may be
  left out of the union later (Milestone 9b), depending on that QC;
- results copied to `ZEAL/genotype`.

## Inputs

- `docs/runs/genotype_mexicana_chr10/samplesheet.csv` (written by `agent/genochr10/write_sheets.py` from
  `meta/samples.csv`):
  - every not-excluded mexicana `bc1_sample` and `nil`: 885 samples of 42 donors (163 BC1 pools, 722 lines);
  - the 23 B73 checks of attempt 3 (12 `B73-bulk`, 11 `B73`).
- The 312 rows of attempt 3 (eight donors and the checks) are byte-identical to its sheet, so their discovery comes
  from the cache.
- Every CRAM, index and CollectWgsMetrics file the sheet names is in `ZEAL/alignment/cram/` (checked on hazel
  2026-10-14).
- Left out: `Zx.0390_P1` (one line, `PN17_SID1574`, no BC1 pool: no discovery). Kept: `Zx.0520_P4`, the first donor
  with a single BC1 pool.
- `b73_controls.csv`: `B73_ERR3288215`.

## Before the run

On branch `runs-genotype-chr10-taxa`:

- `conf/hpc_dev.config`: `UNION_SITE_COUNTS`, `UNION_TIERS`, `FILL_DONOR_ALLELES` 4 GB (user, 2026-10-14; was 1 GB).
  The union grows from 8 to 42 donors. Resources do not invalidate the cache.
- `scripts/submit_head_job.sbatch`: `ZEALGT_LAUNCH` also sets `hpc_dev`'s launch directory, for the diploperennis run.
  Without it set, `hpc_dev` keeps `nf_work/zealgt_dev`.

Then a CodeRabbit review of the diff, a push, and on hazel `git -C /rsstu/users/r/rrellan/BZea/ZEAL/zealgt pull`. The
checkout is on `dev` at `8570cbd`, 33 commits behind, and gets this branch checked out until the merge.

## Run

`hpc_dev`, launch directory `nf_work/zealgt_dev`, resuming attempt 3's session (as Milestone 9a test 4, job 1200045).
Head job normal QOS, 12 h, 16 GB, heap 12 GB:

```
cd /rsstu/users/r/rrellan/BZea/ZEAL/zealgt
B=/rsstu/users/r/rrellan/BZea
S=/rsstu/users/r/rrellan/BZea/ZEAL/zealgt/docs/runs/genotype_mexicana_chr10
sbatch --parsable --partition=compute --qos=normal --time=12:00:00 --mem=16G \
  --export=ALL,NXF_OPTS="-Xms1g -Xmx12g" \
  scripts/submit_head_job.sbatch hpc_dev --step genotype \
  --input $S/samplesheet.csv --b73_controls $S/b73_controls.csv \
  --lowcopy_bed $B/ZEAL/reference/lowcopy_chr10.bed \
  --check_sites $B/bzeaseq/nilhmm/vcf/HQ_BZEA.vcf.gz \
  --regions chr10 --outdir /share/maize/frodrig4/nf_work/zealgt_dev/genotype_mexicana_chr10/results \
  -resume 05f75070-d26e-4647-943a-e7e45a898bae
```

What reruns:

- discovery for the 34 new donors;
- the union of 42 donors and everything after it (`COUNT_UNION` for every BC1 sample, since the site list changes);
- `COUNT_LINES` and `CALL_ANCESTRY` for all donors, whose markers change with the union.

Estimate: about 2-4 h (attempt 3, two new donors: 32 min; test 4, ancestry of eight donors: 24 min), set by discovery
and `COUNT_LINES` at 40 tasks at a time. Launched by ~08:30, done ~10:30-12:30.

## After the run

1. **Copy** `results/` to `/rsstu/users/r/rrellan/BZea/ZEAL/genotype/mexicana_chr10/` (a `cp -r` in a short Slurm job;
   `/share` and `/rsstu` are separate file systems, so hard links do not cross).
2. **Accounting of the union**, from each donor's tier-A VCF and the union:
   - union sites in all;
   - per donor: tier-A sites, sites private to it, sites shared with others;
   - per donor: union-ALT markers (`donor_alleles` GT=1), split into its own tier-A sites, sites gap filling adds, and
     sites private to a problem family.
3. **Problem-family screen** of the 34 new donors, as in attempt 3:
   - the veto gain (clean +20 %, problem families +204-206 %);
   - the background of the donor's own private alleles in lines SNP50K calls B73 on chr10 (clean 0.6-2.4 %, problem
     1.6-10 %);
   - donor segments per line on chr10 next to SNP50K.
4. **QC of the union sites**, the sites private to a problem family against the sites private to one clean donor
   (baseline). The first pass on attempt 3's union is running (`agent/genochr10/qc/`).
   1. leakage: their share of each clean donor's union-ALT markers;
   2. ALT reads in the B73 checks and `B73_ERR3288215`;
   3. ALT read fraction in clean-family lines that SNP50K calls REF on the whole chr10;
   4. ALT allele in the TIL18 chr10 assembly (`phg_pilot/chr10/maf/`);
   5. ALT fraction in the donor's own BC1 pools.
5. **User decision**: if the QC shows the problem families' private sites are mostly false and leak into clean donors'
   markers, Milestone 9b (`--union_exclude`) and a run resumed from this one with the flagged donors named. Discovery
   comes from the cache; the union and everything after it rerun (~1 h).

## Checks (bugs, not accuracy)

- Per donor: tier-A sites, union-ALT markers, `line_checks.tsv` (segments per line, dosage bands), as test 4.
- The eight donors' tier-A sets unchanged (cached).
- The B73 checks free of donor segments.
- `Zx.0520_P4` (one pool) reported on its own.

## Done when

- The run succeeds.
- A results note here: the accounting, the screen, the QC and the user's decision on 9b.
- Time and peak per process in `docs/RESOURCES.md`.
- Results copied to `ZEAL/genotype/mexicana_chr10/`.
- Superseded `work/` of attempt 3 and test 4 on the user's cleanup list.
