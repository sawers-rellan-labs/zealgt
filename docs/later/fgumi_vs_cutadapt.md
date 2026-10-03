# Later: fgumi clipping vs cutadapt trimming

Checks the 2026-10-02 decision "No adapter trimming" (`../decisions.md`, "Read processing, both kits"): reads go
untrimmed to minibwa, then `fgumi clip --clipping-mode soft --clip-bases-past-mate true` removes read-through.

## What the old repository did

cutadapt 5.2 on every demultiplexed pair, before alignment (old `modules.config:59`, `REQUIREMENTS.md:36`):
`-a <TruSeq R1> -A <TruSeq R2> --nextseq-trim=15 -m 36 --compression-level 4`.

So cutadapt did three things fgumi does not:

- removed adapter in every read, also unmapped, singleton and discordant ones;
- quality-trimmed 3' ends at Q15 (`--nextseq-trim`, two-color chemistry);
- dropped pairs with a read shorter than 36 bp.

## Why the decision should hold

- Adapter enters a read only when the insert is shorter than the read. In a mapped FR pair that is the part past the
  mate's end, which fgumi soft-clips (94-97 % of reads clipped at the insert end).
- Outside FR pairs, minibwa soft-clips non-matching tails, and `mpileup` ignores soft clips.
- Low-quality 3' bases are dropped by `mpileup -Q 20` instead of by trimming.

## Test

Inputs: S_1A_6 and PN2_SID141 (one per kit), `--head 4000000`, the Milestone 3 run's demultiplexed reads.

1. Arm A: the CRAMs as the pipeline makes them.
2. Arm B: cutadapt with the old settings on the same reads, then the same chain (`FASTQ_ALIGN_MINIBWA`, fgumi included).
3. Compare per sample:
   - samtools stats: reads mapped %, properly paired %, error rate, soft-clipped bases, insert size;
   - CollectWgsMetrics: `MEAN_COVERAGE`, `PCT_EXC_BASEQ`, `PCT_EXC_OVERLAP`, `PCT_EXC_TOTAL`;
   - `bcftools mpileup -a AD -q 20 -Q 20` on one chromosome: ref / alt counts per site, and alt alleles seen in one arm
     only.

## Decision rule

The decision holds if arm A loses no usable depth against arm B and has no alt alleles that arm B lacks beyond noise.
Accuracy proper is judged in GENOTYPE: zealbc1 matching and rigidity on a full chromosome.
