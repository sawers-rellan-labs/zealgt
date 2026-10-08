# Run plan: union over six mexicana donors from four races, chr10

DRAFT, not approved.

## Why

User, 2026-10-07: the union model needs the donors' population structure ("our donor accessions come from
sanchezgonzalez2018 and the genetics is described in chen2022"; "check which Mesa Central and Chalco donors are aligned";
"write the run plan"). The four-donor test (`genotype_union_4donors_chr10.md`) sampled two races only, Durango
(Zx.0540, Zx.0550) and Nobogame (Zx.0570, Zx.0580), two sites each in Durango and Chihuahua. Mexicana races are
"geographical populations spatially isolated by the topography" (Sánchez-González et al. 2018), and mexicana splits into
K = 2 clusters (Chen et al. 2022). If each race brings a block of private alleles, adding Mesa Central and Chalco donors
pushes the union above both curves fitted to four donors (math supplement Section 5.6, Eqs. 21 and 23; notebook
`03_union_rarefaction.qmd`), whose ~250-300 thousand sites at 10 donors hold only for Durango/Nobogame-like donors. In the
passport table (`meta/accessions.csv`) Mesa Central has 16 mexicana accessions and Chalco 14, against 3 and 2 for Durango
and Nobogame.

## Donors

None of the 21 Mesa Central or 14 Chalco donors is aligned. One per race, the one with the most lines (as for the
four-donor test):

| Race         | Donor          | BC1 pools | Lines (batch 1 + batch 2) | Runner-up                      |
| ------------ | -------------- | --------- | ------------------------- | ------------------------------ |
| Mesa Central | **Zx.0500_P2** | 5         | 22 (11 + 11)              | Zx.0440_P2 (4 pools, 21 lines) |
| Chalco       | **Zx.0090_P2** | 5         | 23 (12 + 11)              | Zx.0150_P2 (3 pools, 21 lines) |

All 55 samples are in the demultiplexing sheets (`demultiplex_02`, `03`, `06`, `07`).

## Stages

1. **Alignment of the two new donors and the batch-2 B73 checks** (`hpc_prod`, frozen worktree `ZEAL/zealgt_prod`, outdir
   `ZEAL/alignment`, as stage 1 of the four-donor test): 10 BC1 pools and 45 lines, plus the 6 batch-2 B73 checks not yet
   aligned (P4107, P4187, P4180, P4119, P4251, P4376; the other 5, plate BZeaV2_1, are aligned). Stage 1 of the four-donor test (9 pools, 93 lines, 165 GB raw)
   took 3 h 05 min with a `/share` peak of 1.35 TB (work/raw 8.2x); the pools dominate the raw size, so expect about the
   same: ~3 h, peak <= 1.5 TB. Head job 16 GB with `NXF_OPTS="-Xms1g -Xmx12g"`, normal QOS, 24 h limit.
2. **GENOTYPE on chr10, six donors** (`hpc_dev`, launch directory `nf_work/zealgt_dev`, `-resume
05f75070-d26e-4647-943a-e7e45a898bae`): discovery for the two new donors (the other four from the cache), the union of
   six, `COUNT_UNION`, `UNION_TIERS`, `FILL_DONOR_ALLELES`, ancestry for the new donors. Checks: the 12 batch-1 B73 bulks
   and the 11 batch-2 B73 checks (half of each new donor's lines are batch 2). Outdir
   `nf_work/zealgt_dev/union6_chr10/results`. Head job normal QOS, 12 h, 16 GB (stage 2 of the four-donor test: 38 min,
   head 0.8 GB).
3. **Sharing patterns** (one short Slurm job, as job 1143239): which of the six donors' tier-A sets contain each union
   site, 63 patterns, into `docs/notebooks/union_rarefaction/` next to the four-donor file.

The sheets are written by a script in `agent/union6/` from `meta/samples.csv` and the demultiplexing sheets (as
`agent/union4/write_sheets.py`) into `docs/runs/genotype_union_6donors_races_chr10/`; the GENOTYPE sheet is the
four-donor one plus the new rows.

## Measurements (the point of the run)

- Union sites at 5 and 6 donors (pipeline) and, from the patterns, every subset: the rarefaction curve to $n = 6$ and the
  stratified one (within race, then across races).
- Whether a new race adds more private sites than a new donor of a sampled race: the sites found only in Zx.0500_P2 or
  only in Zx.0090_P2, against the private sites of Zx.0550_P4 and Zx.0580_P2 relative to their race-mates, scaled by
  each donor's own sites.
- The 5- and 6-donor unions against the four-donor fits (Eqs. 21 and 23) predicted at 5 and 6 donors.
- Per process at 6 vs 4 donors: realtime and peak RSS of `COUNT_UNION`, `UNION_TIERS`, `FILL_DONOR_ALLELES`
  (`FILL_DONOR_ALLELES` 15.5 s / 309 MB at 4 donors).

## Checks (bugs, not accuracy)

- Per new donor: tier-A sites, BC1 pool and line coverage, μ_d inside the range of the other four.
- The four donors' tier-A sets unchanged (cached tasks), unless the added batch-2 checks change their inputs; if they do,
  their discovery reruns and the change is reported per donor.
- The batch-2 B73 checks free of donor segments, as the batch-1 ones.

## Decisions (user, 2026-10-07)

- B73 checks: "add batch2 B73 check through the pipeline": the 6 unaligned batch-2 B73 checks go into stage 1 and all 11
  into the GENOTYPE sheet.
- Head job memory for stage 1: "keep 16GB".
- Witness veto: kept, "mostly for keeping the variant count more manageable".

## Attempt 2: batch-1-only rerun for the two new donors (prepared 2026-10-07)

Why: Zx.0500_P2 and Zx.0090_P2 find 4-10x fewer tier-A sites than the other four donors (9,060 and 7,482), and RTIGER
fragments their lines (22-32 segments per line on chr10 against 1-3). They are the only donors with batch-2 lines; the
in-silico line pool (CRISP, veto) and RTIGER's fit are shared by all of a donor's lines, so batch-2 lines could corrupt
the batch-1 lines' results too (user: "I do not understand why you do not discard the batch 2 problem").

What: the six-donor GENOTYPE run with the 22 batch-2 lines of those two donors removed
(`genotype_union_6donors_races_chr10/batch1_only/samplesheet.csv`, 252 rows, written by
`agent/union6/write_batch1_only_sheet.py`); same session (`-resume 05f75070-...`), so only the two donors' discovery and
ancestry, the union and gap filling rerun. Outdir `nf_work/zealgt_dev/union6_b1only_chr10/results`.

Read: if tier-A counts rise toward the others' and RTIGER's segments per line fall to a few, batch 2 is the cause; if not,
the BC1 pools are (user's suspicion). Read together with the per-sample private-site counts (job 1147456).

Attempt 2 status: not run; superseded by the per-line checks below and by attempt 3. Zx.0090_P2's batch-1 lines carry the
same background as its batch-2 lines, so a batch-1-only rerun would not fix that donor.

## Findings from attempt 1 (2026-10-07)

- Zx.0090_P2 and Zx.0500_P2 find few tier-A sites (7,482 and 9,060) and RTIGER fragments their lines (17 and 14 donor
  segments per line on chr10; SNP50K RTIGER on the same batch-1 lines: 2.5 and 4).
- Their BC1 pools are normal (each highest at its own donor's private sites; CRISP on BC1 pools alone: 6,903 for
  Zx.0500_P2 against 8,099 for Zx.0540_P3). Their lines carry a background of their own donor's alleles, 4-10 %
  (Zx.0090_P2) and 1-3 % (Zx.0500_P2), in lines that SNP50K calls B73 on chr10, in both sequencing batches; B73 checks and
  the WGS control are clean at those sites (0.07 %). User: a problem in the cross or seed from the wrong ear in the
  planted packet. Both are kept in the union as problem families, flagged, until the user decides.
- The in-silico line pool and the veto make RTIGER's markers clean for the other donors: RTIGER on BC1-only markers gives
  8-10.5 donor segments per line on chr10 for three of the four good donors. Details:
  `agent/notes_discovery_bc1_rescue_20261007.md`.

## Attempt 3: two donors with the first set's layout (written 2026-10-07)

Why: the rarefaction curve needs donors from the two new races with healthy discovery (user: "try another set of donors";
"I wanted the union rarefaction curve to be completed"). The first set's lines are batch-1 only, 40-50 per donor, plates
BZea5-9; the problem families have batch-1 lines on plates 3-4 plus batch 2.

| Race         | Donor          | BC1 pools | Lines                  | Plates        |
| ------------ | -------------- | --------- | ---------------------- | ------------- |
| Mesa Central | **Zx.0470_P2** | 3         | 13 batch-1             | BZea17        |
| Chalco       | **Zx.0160_P2** | 5         | 14 batch-1 + 3 batch-2 | BZea3, V23A-C |

No Chalco donor avoids plates 3-4; Zx.0160_P2 has the most batch-1 lines and little batch 2. Both families have a third
of the first set's lines. Neither donor is aligned.

Stages, as attempt 1:

1. Alignment of 8 BC1 pools and 30 lines (`hpc_prod`, worktree `ZEAL/zealgt_prod`, outdir `ZEAL/alignment`), head job
   16 GB, heap 12 GB, normal QOS; ~2.5 h (attempt 1: 10 pools + 45 lines + 6 checks in 2 h 43 min).
2. GENOTYPE chr10 with eight donors (`hpc_dev`, `-resume 05f75070-...`), outdir `nf_work/zealgt_dev/union8_chr10/results`:
   the six of attempt 1 from the cache plus the two new; sheet = attempt 1's plus the new rows, in
   `genotype_union_6donors_races_chr10/attempt3/`.
3. Sharing patterns over the eight donors (255 patterns) into `docs/notebooks/union_rarefaction/patterns_8donors.tsv`.

Checks before the curve: for each new donor, tier-A sites, CRISP calls with and without the veto, and its lines' background
at its own private sites (the per-line count of attempt 1); RTIGER donor segments per line on chr10 next to SNP50K where the
lines have SNP50K calls. A new donor that shows the background is reported, not used for the curve.

Read: the rarefaction curve from the six good-layout donors (four first-set + two new; the patterns allow any subset),
with the problem families shown separately; whether a donor from a new race adds more private sites than a race-mate.
