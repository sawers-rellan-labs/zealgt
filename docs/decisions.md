# Decisions

One entry per decision, newest last. Terms as in `TERMINOLOGY.md`.

## 2026-10-02 Workflows
`ALIGNMENT` takes raw reads to one CRAM per sample and stops there; `GENOTYPE` reads those CRAMs.

## 2026-10-02 `--head N`
First N read pairs per library, before demultiplexing; test runs only. Not called `--subsample`, which means coverage
downsampling in genotyping.

## 2026-10-02 Read processing, both kits
- Demultiplexing: `fgbio DemuxFastqs` as the Twist guides say.
  - 96-Plex (BC2S3 batch 1): `--read-structures 8B12S+T 8S+T`, fgbio's default mismatches (the guide sets none).
  - FlexPrep (BC1, BC2S3 batch 2): `--read-structures 6B2S+T 6B2S+T --max-mismatches 1 --min-mismatch-delta 2`.
- No adapter trimming, as both guides say. Twist publishes no adapter sequences; none are needed.
- After alignment: `fgbio ClipBam --clip-bases-past-mate`, both kits.
  - Removes read-through into the mate's barcode, random bases and adapter: clips at the insert end in 94-97 % of reads.
  - Differs from the 96-Plex guide's `--clip-overlapping-reads` (the FlexPrep guide has no clipping): that option keeps
    one mate's half of the overlap by position, often the lower-quality base; past-mate leaves the overlap to mpileup,
    which keeps the better base. At `-Q 20` past-mate keeps 0.3 % (FlexPrep) / 0.9 % (96-Plex) more counted bases.
  - Both options together equal overlapping alone; not used.
- Open: the base quality of read-through bases, i.e. whether `-Q 20` alone would drop them.

## 2026-10-02 Allele counting
`bcftools mpileup -I -a AD -q 20 -Q 20`, default depth cap (250), default mate-overlap removal.
- `-Q 20`: bcftools' default minimum base quality is 1; about two thirds of non-reference observations were bases below
  Q20 (the lowest bins: Q9 NovaSeq X, Q11 NovaSeq 6000).
- No `-d 10000`: samples are 0.9-5.5x (48 BC1 samples); >= 250x covers at most 0.008 % of the genome, i.e. repeats.
- Open: CRISP discovery sets no base-quality threshold (`--mbq` default 10 keeps batch 1's Q11 bases); `--mbq 20`
  proposed, not measured.

## 2026-10-02 Samplesheet column `kit`
`kit` = `twist_flexprep` | `twist_96plex` names the library preparation kit and selects the read structure and
mismatches. Replaces `barcode_layout` (`symmetric` | `r1_only`), which described a consequence, not the kit.

## 2026-10-02 Container images on `/share`
`apptainer.cacheDir` = `/share/maize/frodrig4/apptainer/cache`; images are pulled there by an xfer job and pulled again
when the 30-day scratch purge removes them. Not `/rsstu`: slower (seen when building conda envs there).
