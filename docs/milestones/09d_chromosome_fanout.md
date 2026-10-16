# Milestone 9d: GENOTYPE over several chromosomes in one run

Approved by the user, 2026-10-16 ("approve").

`GENOTYPE` takes a list of regions instead of one `--region`; every per-region step runs once per region, all regions
side by side in one run. Outputs per region are unchanged.

## Why

User, 2026-10-16: "now I want to run the genotype on full genomes". Today the pipeline takes one `--region`, and the
unions are per taxon, so a whole genome is 5 taxa x 10 chromosomes = 50 runs, each with its own head job, cache and
logs. With the fan-out it is one run per taxon (agreed in the same conversation, "write the spec").

## What changes

1. **`--regions`** (string, comma-separated, e.g. `chr1,chr2,...,chr10`; `nextflow_schema.json` pattern) replaces
   `--region`. One value gives today's run. In `workflows/genotype.nf`: `channel.fromList(regions.tokenize(','))`.
2. **The region joins each item's `meta`** (`meta.region`) where the per-region work starts, by `combine` with the
   regions channel:
   - `CRAM_VARIANT_DISCOVERY_CRISP`: the witness and check pools (`SAMTOOLS_MERGE -R`), `CRISP`, `BED_CLIP`,
     `WITNESS_VETO`, `BCFTOOLS_MPILEUP` (B73 controls), `POOLED_LIKELIHOOD_TIERS`: per donor (or control) x region;
   - `SITES_UNION_GAPFILL`: the union (`BCFTOOLS_MERGE` -> `BCFTOOLS_NORM` -> `BIALLELIC_UNION`) per region, grouped
     by `meta.region` (`groupTuple`); `COUNT_UNION`, `UNION_TIERS`, `UNION_SITE_COUNTS`, `FILL_DONOR_ALLELES`,
     `DONOR_ALLELES_MERGE` per region (x pool or donor as now);
   - `CRAM_ANCESTRY_RTIGER`: per donor x region; `ANCESTRY_GRID` and `ANCESTRY_VCF_INDEX` per region.
     Joins that today key on the donor (or sample) key on donor + region.
3. **`conf/modules.config`**: every `params.region` in `ext.args` and `ext.prefix` becomes `meta.region` (CRISP,
   BED_CLIP, WITNESS_VETO, the tiers, the union's three steps, COUNT_UNION, COUNT_LINES, UNION_TIERS, the ancestry
   steps). File names stay `<id>.<region>.*`.
4. **Once per sample, not per region** (unchanged): the coverage filter and the B73 check filter (`CHECK_COUNTS`,
   `CHECK_ALT_RATE` at the check sites).
5. **Run settings for a genome run** (run plan, not code): head job on the normal QOS (`--time=2-00:00:00`), tasks on
   the short QOS as now; one run per taxon.

No new process and no Groovy function: `combine`, `map`, `groupTuple` and `join` on `meta.region`.

## Choices

- **Tasks per donor x chromosome**, not per donor x genome. Genome-wide tasks would be ~14x longer (low-copy space
  367 Mb vs chr10's 26 Mb): CRISP ~3 h per donor instead of ~12 min, past the short QOS's 2 h, onto the normal QOS and
  its queue waits; `UNION_SITE_COUNTS` and gap filling 14x larger per task.
- **One run per taxon over all regions**, not one run per taxon x chromosome (50 runs) and not one run for all taxa
  (the unions are per taxon, `docs/decisions.md`).
- **`--regions` replaces `--region`**, not both: one parameter, one value for today's behaviour; the run plans'
  commands change from `--region chr10` to `--regions chr10`.
- **RTIGER per donor x chromosome** as now (rigidity 0.5 % of the donor's markers per chromosome, `decisions.md`),
  not one fit per donor over the genome.
- **The R/qtl grid per region** as now; a genome-wide cross file (all chromosomes in one csvr) is left for later.

## Tests

1. Tools: none change.
2. Wiring (laptop, stub, seconds): `--regions chrA:1-N,chrA:N-M` on the GENOTYPE fixtures gives every per-region
   output twice with the region in its name; `--regions chrA` matches today's snapshot (`tests/genotype.nf.test`).
   Channel-level DAG.
3. Hazel setup: `scripts/run_hazel_tests.sbatch` (the 12 GENOTYPE process tests; `tests/hazel` gets `meta.region`
   where `ext.args` read it) and `-preview`.
4. Review: CodeRabbit on the milestone's commits, beside step 3.
5. Slice (laptop, real data, <= 15 min): the two pilot donors, `--regions chr9:1-5000000,chr10:1-5000000`.
6. Hazel regression: diploperennis with `--regions chr10` (sheet of run 1270808, ~2 h): donor alleles, segments and
   line checks identical to run 1270808's.

## Done when

- The six tests pass; the chr10 regression is identical.
- `structure.md` GENOTYPE rows say "per region", both metro maps show the regions channel, `docs/running.md` and the
  genotype run plans use `--regions`.
- The genome-wide run is a run plan in `docs/runs/` (per taxon, head job on normal QOS), not part of this milestone.
