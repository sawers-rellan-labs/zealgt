# fqtk vs cutadapt for demultiplexing

Test of 2026-10-03 on hazel (Milestone 5, test 5): which demultiplexer is better, fqtk (current `DEMULTIPLEX`) or
cutadapt (zealgt-old `DEMUX`)? To decide before demultiplexing all libraries.

## Setup

- Input: the first 5,000,000 read pairs of one lane per kit, cut and re-compressed with `gzip -1` as `EXTRACT_LANE`
  does. Both tools read the same head files.
  - FlexPrep: library 1A, lane L5 (`BC1_1Ar_WKDL260013245-1A_255FKVLT4_L5_{1,2}.fq.gz`), 2 x 150 bp, 12 samples.
  - 96-Plex: library BZea5, lane L001 (batch-1 tar members `BZea5_S5_L001_R{1,2}_001.fastq.gz`), 2 x 151 bp, 96 samples.
- Barcodes: every row of the library in `meta/samples.csv`, as the pipeline does. Neither library has an excluded well.
- fqtk 0.4.0, the `FQTK` module's image, `--threads 5`, as `FASTQ_DEMULTIPLEX_FQTK` and `conf/modules.config` run it:
  - FlexPrep: `6B2S+T 6B2S+T`, barcode = `barcode_r1` + `barcode_r2`, `--max-mismatches 1 --min-mismatch-delta 2`.
  - 96-Plex: `8B12S+T 8S+T`, barcode = `barcode_r1`, default mismatches. fqtk's defaults are the same as above (`fqtk
demux --help`: `--max-mismatches` "[default: 1]", `--min-mismatch-delta` "[default: 2]"), so both kits allow one
    mismatch.
  - An observed N matches only an expected N (`fqtk demux --help`), so it counts as a mismatch.
- cutadapt 4.9, the zealgt-old `DEMUX` image, `-j 5`, its `demux_args` `-e 0 --no-indels --discard-untrimmed -Z`:
  - FlexPrep: `-g ^file:r1.fa -G ^file:r2.fa --pair-adapters`, patterns `<barcode_r1>NN` and `<barcode_r2>NN`.
  - 96-Plex: `-g ^file:r1.fa -U 8`, pattern `<barcode_r1>` + 12 N.
  - One simplification: cutadapt writes plain `.fastq` files instead of zealgt-old's FIFOs drained by `pigz`, which were
    there only to bound memory. The assignments do not change; the memory below is not zealgt-old's.
- Comparison by read name (comment and `/1` `/2` stripped), every output pair against the raw head: R1/R2 names in step
  in every output file, no pair in two samples. Barcode distances (Hamming) are from the raw reads.
- Slurm: compute_partners / short, 6 CPUs, 16 GB, node c207n13; job 1066376 (16 min 30 s, mostly the comparison).
  Scripts: `agent/demux_split/fqtk_vs_cutadapt/`.

## Result

Every pair cutadapt assigns, fqtk assigns to the same sample. No pair goes to different samples, and no pair is assigned
by cutadapt only. fqtk additionally assigns the pairs one mismatch from one barcode and three or more from every other.

| Pairs (of 5,000,000)        | 1A L5 (FlexPrep)    | BZea5 L001 (96-Plex) |
| --------------------------- | ------------------- | -------------------- |
| Assigned by fqtk            | 4,886,924 (97.74 %) | 4,716,629 (94.33 %)  |
| Assigned by cutadapt        | 4,751,048 (95.02 %) | 4,621,272 (92.43 %)  |
| Same sample by both         | 4,751,048           | 4,621,272            |
| Different samples           | 0                   | 0                    |
| fqtk only (1 mismatch)      | 135,876 (2.72 %)    | 95,357 (1.91 %)      |
| - of which with an N        | 7,258               | 2,061                |
| cutadapt only               | 0                   | 0                    |
| Unmatched by both           | 113,076 (2.26 %)    | 283,371 (5.67 %)     |
| - 1 mismatch, but ambiguous | 0                   | 57,343 (1.15 %)      |

- FlexPrep, fqtk only: the mismatch is in the R1 barcode in 89,253 pairs, in the R2 barcode in 46,623. The 12-base
  barcodes of 1A are at least 4 apart; every unmatched pair is 2 or more from its nearest barcode.
- 96-Plex: 86 of the 4,560 pairs of BZea5 barcodes are only 2 apart. The ambiguous unmatched pairs are 1 from one
  barcode and 1 (18,821) or 2 (38,522) from another; fqtk's delta rule rejects them, as cutadapt does.
- Per sample, the 1-mismatch pairs are 1.7-5.4 % (median 2.7 %) of fqtk's pairs in 1A, 0.2-7.6 % (median 1.9 %) in
  BZea5. The largest relative gain is BZea5's near-empty well PN5_SID390: 99 pairs by fqtk, 71 by cutadapt.
- Read lengths after barcode removal are identical, every pair, both tools: 1A 142 / 142 (150 minus 6B2S); BZea5 R1
  131 (151 minus 8B12S) and R2 143 (151 minus 8S).

| Run             | Wall time | Max RSS, one process | CPU   |
| --------------- | --------- | -------------------- | ----- |
| fqtk, 1A        | 20.0 s    | 1.64 GB              | 325 % |
| cutadapt, 1A    | 20.1 s    | 0.44 GB              | 375 % |
| fqtk, BZea5     | 23.4 s    | 1.57 GB              | 319 % |
| cutadapt, BZea5 | 42.9 s    | 3.12 GB              | 464 % |

cutadapt's 96 barcodes with N wildcards cost twice fqtk's time; its memory here is the plain-file output's (zealgt-old
measured 0.53 GB with FIFOs on a full lane).

## The mismatch setting

fqtk allows one mismatch on both kits (the Twist FlexPrep guide's fgbio `--max-mismatches 1 --min-mismatch-delta 2`;
fqtk's defaults for 96-Plex); cutadapt allows none (`-e 0`).

- Gain: 2.72 % (FlexPrep) and 1.91 % (96-Plex) more pairs, in every sample.
- Cost: a 1-mismatch pair goes to the wrong sample only if its true barcode has 3 or more errors (the other barcodes are
  at least 3 away from it under the delta rule). With the observed single-error rate, ~0.23 % per base, and independent
  errors, 3 or more errors occur in ~0.7 (8 bases) to ~2.7 (12 bases) pairs per million, and only some of those land 1
  from another barcode: at most a few wrong pairs per million, against 19,000-27,000 gained. An exact match from a
  2-error read of a neighbouring 96-Plex barcode (2 apart) goes to the wrong sample under both tools alike.

## Recommendation

Keep fqtk: it assigns the same sample as cutadapt to every pair cutadapt assigns, sends no pair to a different sample,
recovers 1.9-2.7 % more pairs per lane at an estimated misassignment cost of at most a few pairs per million, leaves
identical read lengths, and is as fast or twice as fast. Decision (user, 2026-10-03): keep fqtk.
