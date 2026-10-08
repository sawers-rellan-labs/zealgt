# Run plan: union and gap filling over four mexicana donors, chr10 (scaling test)

DRAFT, not approved.

## Why

User, 2026-10-06: measure the union step before any full-population run ("we need to measure the union step"; "select
another two mexicana donors with a lot of lines"). The union and gap filling step 1 grow with the number of donors:
`FILL_DONOR_ALLELES` is one task per chromosome over every union site and every donor (Section 5.2, Eq. 10), and the
union counts (`COUNT_UNION`) cover every BC1 pool at every union site. Only two donors have been run (chr10: 70,210 union
sites; `FILL_DONOR_ALLELES` < 1 s, 11 MB).

## Donors

- Pilot (aligned): Zx.0540_P3 (40 lines, 5 BC1 pools, 44x), Zx.0570_P2 (44 lines, 5 pools, 39x).
- New: **Zx.0580_P2** (50 lines, 5 pools, 38x) and **Zx.0550_P4** (43 lines, 4 pools, 34x), _mexicana_, batch-1 lines,
  from two accessions (Zx.0580_P3, 50 lines, is the other parent of Zx.0580 and likely shares many alleles with
  Zx.0580_P2).

## Stages

1. **Alignment of the two new donors** (`hpc_prod`, as `alignment_pilot.md`): their 9 BC1 pools and 93 lines from the
   demultiplexing sheets; the batch-1 B73 checks are already aligned. About 0.2 TB of raw reads, like the pilot:
   ~3.5 h, `work/` peak <= 1.5 TB. Head job 16 GB, heap capped at 12 GB.
2. **GENOTYPE on chr10, four donors** (`hpc_dev`, launch directory `nf_work/zealgt_dev`): discovery for the two new
   donors (the pilot donors' from the cache of session `05f75070-...`), the union of four, `COUNT_UNION`,
   `UNION_TIERS`, `FILL_DONOR_ALLELES`, ancestry for all four. Head job on the short QOS (one chromosome).

## Measurements (the point of the run)

- Union sites with 2, 3 and 4 donors (the 3-donor union from `bcftools merge` of the tier-A files, outside the pipeline).
- Per process: realtime and peak RSS of `COUNT_UNION`, `UNION_TIERS`, `FILL_DONOR_ALLELES` at 2 and 4 donors.
- Extrapolation to 95 donors: union size from the growth from 2 to 4 donors (and zealgt-old's rarefaction simulation,
  `docs/notebooks/01_union_rarefaction.qmd` there), and `FILL_DONOR_ALLELES` memory and time per donor x site.

## Checks (bugs, not accuracy)

- Per donor: tier-A sites, union sites, step-1 ALT / REF / missing, μ_d inside the mexicana panel range.
- The pilot donors' calls at the 2-donor union sites, against job 1111642.

## Open

- The witness veto (notebook `02_witness_veto`): kept as in the pipeline for this test unless decided otherwise.
- The donor pair (Zx.0580_P2 + Zx.0550_P4, or both Zx.0580 parents).
