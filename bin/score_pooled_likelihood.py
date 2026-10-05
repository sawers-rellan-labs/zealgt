#!/usr/bin/env python3
"""Pooled likelihood ratio, flags and tiers per site for one donor (math supplement, "Per-donor variant discovery").

Flags: hidepth (all pools' depth > --hidepth-factor x the median), af_gt_half (BC1 ALT share > 1/2, binomial test),
inconsistent (one BC1 pool with >= --inconsistent-min-alt ALT reads while another has >= --inconsistent-min-depth reads
and none ALT). Tier A: LLR >= --llr-a, ALT reads in >= --a-min-pools-alt pools, no flag; B: LLR >= --llr-b, neither
hidepth nor af_gt_half; C: LLR >= --llr-c; ref: LLR <= --llr-ref with >= --ref-min-depth reads; else ".".
Reads the witness-vetoed CRISP VCF (BC1 pools and the witness; per-pool counts in ADf, ADr, ADb as 'ref,alt') and the
B73 control VCFs from bcftools mpileup (AD), and writes one row per biallelic SNP record. Pool groups: the donor's BC1
pools, the witness, the B73 controls together. With --bc1-vcf instead (the union, Text S5): one row per --sites record,
the BC1 pools counted by bcftools mpileup (AD, one VCF per pool), no witness. --tier-a-vcf also writes the tier-A sites
as a sites-only VCF. Model, per BC1 pool i with n_i reads, a_i ALT:
  L1_i = sum_j C(P,j) 2^-P Bin(a_i; n_i, p_j), p_j = j/2P (1-eps) + (1 - j/2P) eps;  L0_i = Bin(a_i; n_i, eps)
  LLR = sum_i log L1_i - log L0_i
eps per site: the reads of the groups with LLR < --zero-class-llr at --eps0, when they hold >= --zero-class-min-reads,
eps = max((a0 + 0.5) / (n0 + 1), --eps-floor); else --eps0. VCF input and output with pysam.
"""
import argparse
import gzip
import logging
import math
import statistics
import sys
import time

import pysam

LOG = logging.getLogger("score_pooled_likelihood")
COLUMNS = ["chrom", "pos", "ref", "alt", "n", "a", "n_pools_alt", "eps", "LLR", "tier", "flags", "pool_counts"]


def parse_args(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--vcf", help="witness-vetoed CRISP VCF (.vcf or .vcf.gz)")
    ap.add_argument("--witness", help="the witness pool's sample name in the VCF")
    ap.add_argument("--bc1-vcf", nargs="+", help="instead of --vcf: the BC1 pools' VCFs from bcftools mpileup (AD)")
    ap.add_argument("--sites", help="with --bc1-vcf: the sites to score (VCF; biallelic SNPs)")
    ap.add_argument("--tier-a-vcf", help="also write the tier-A sites here (sites-only VCF)")
    ap.add_argument("--controls", nargs="*", default=[], help="B73 control VCFs from bcftools mpileup (AD)")
    ap.add_argument("--out", required=True, help="output site table (.tsv.gz)")
    req = ap.add_argument_group("model settings (values in conf/modules.config)")
    for name, kind in [
        ("plants", int), ("eps0", float), ("eps-floor", float), ("zero-class-llr", float),
        ("zero-class-min-reads", int), ("llr-a", float), ("llr-b", float), ("llr-c", float), ("llr-ref", float),
        ("ref-min-depth", int), ("a-min-pools-alt", int), ("hidepth-factor", float),
        ("af-gt-half-min-depth", int), ("af-gt-half-p", float), ("inconsistent-min-alt", int),
        ("inconsistent-min-depth", int),
    ]:
        req.add_argument(f"--{name}", type=kind, required=True)
    a = ap.parse_args(argv)
    if bool(a.vcf or a.witness) == bool(a.bc1_vcf or a.sites) or not (a.vcf and a.witness or a.bc1_vcf and a.sites):
        ap.error("need either --vcf and --witness, or --bc1-vcf and --sites")
    if a.plants < 1 or not 0 < a.eps0 < 0.5 or not 0 < a.eps_floor < 0.5:
        ap.error("need plants >= 1 and 0 < eps0, eps-floor < 0.5")
    return a


def is_snp(ref, alt):
    return len(ref) == 1 and len(alt) == 1 and ref in "ACGTN" and alt in "ACGT" and ref != alt


def log_weights(plants):
    """log C(P, j) 2^-P for j = 0..P: the number of carrier plants in a pool, Bin(P, 1/2)."""
    return [math.lgamma(plants + 1) - math.lgamma(j + 1) - math.lgamma(plants - j + 1) - plants * math.log(2)
            for j in range(plants + 1)]


def llr_pool(n, a, eps, plants, logw):
    """log L1 - log L0 for one pool; the binomial coefficient cancels."""
    if n == 0:
        return 0.0
    hap = 2 * plants
    terms = []
    for j, lw in enumerate(logw):
        p = j / hap * (1 - eps) + (1 - j / hap) * eps
        terms.append(lw + a * math.log(p) + (n - a) * math.log1p(-p))
    m = max(terms)
    return m + math.log(sum(math.exp(t - m) for t in terms)) - (a * math.log(eps) + (n - a) * math.log1p(-eps))


def binom_sf_half(n, a):
    """P(X >= a) for X ~ Bin(n, 1/2)."""
    return sum(math.exp(math.lgamma(n + 1) - math.lgamma(k + 1) - math.lgamma(n - k + 1) - n * math.log(2))
               for k in range(a, n + 1))


def snp_alleles(rec):
    """(ref, alt) of a biallelic SNP record, else None."""
    if rec.alts is None or len(rec.alts) != 1 or not is_snp(rec.ref, rec.alts[0]):
        return None
    return rec.ref, rec.alts[0]


def read_crisp(path):
    """CRISP VCF -> (pool names, [(chrom, pos, ref, alt, [(n, a) per pool])]) for biallelic SNPs; n = ref + alt reads."""
    recs, skipped = [], 0
    with pysam.VariantFile(path) as vcf:
        pools = list(vcf.header.samples)
        for rec in vcf:
            snp = snp_alleles(rec)
            if snp is None:
                skipped += 1
                continue
            cnt = []
            for call in rec.samples.values():
                r = k = 0
                for key in ("ADf", "ADr", "ADb"):
                    q = call.get(key) or ()
                    if len(q) >= 2:
                        r += q[0] or 0
                        k += q[1] or 0
                cnt.append((r + k, k))
            recs.append((rec.chrom, rec.pos, *snp, cnt))
    LOG.info("%s: %d biallelic SNP records, %d other records skipped", path, len(recs), skipped)
    return pools, recs


def read_sites(path):
    """Sites VCF -> [(chrom, pos, ref, alt)] for biallelic SNPs."""
    with pysam.VariantFile(path) as vcf:
        sites = [(rec.chrom, rec.pos, *snp) for rec in vcf if (snp := snp_alleles(rec))]
    LOG.info("%s: %d biallelic SNP sites", path, len(sites))
    return sites


def read_bc1(paths, sites):
    """mpileup VCFs, one per BC1 pool -> (pool names, [(chrom, pos, ref, alt, [(n, a) per pool])]) at every site."""
    pools, counts = [], []
    for path in paths:
        with pysam.VariantFile(path) as vcf:
            pools.append(",".join(vcf.header.samples))
        counts.append(read_control(path))
    return pools, [(c, p, r, k, [control_counts(t, c, p, r, k) for t in counts]) for c, p, r, k in sites]


def read_control(path):
    """mpileup VCF -> {(chrom, pos): (ref, [alleles], [AD summed over samples])}."""
    rows = {}
    with pysam.VariantFile(path) as vcf:
        for rec in vcf:
            if "AD" not in rec.format:
                continue
            alleles = [rec.ref] + [x for x in rec.alts or () if x != "."]
            ad = [0] * len(alleles)
            for call in rec.samples.values():
                for i, c in enumerate(call["AD"] or ()):
                    if i < len(ad) and c is not None:
                        ad[i] += c
            rows[(rec.chrom, rec.pos)] = (rec.ref, alleles, ad)
    return rows


def control_counts(rows, chrom, pos, ref, alt):
    """(n, a) of one control at a site: REF + site-ALT reads, site-ALT reads; (0, 0) if absent or another REF."""
    e = rows.get((chrom, pos))
    if e is None or e[0] != ref:
        return 0, 0
    _, alleles, ad = e
    k = ad[alleles.index(alt)] if alt in alleles else 0
    return ad[0] + k, k


def tier_of(llr, n, n_pools_alt, flags, a):
    """Tier A: no flag at all; tier B: none of the depth flags (inconsistent blocks A only)."""
    if llr >= a.llr_a and n_pools_alt >= a.a_min_pools_alt and not flags:
        return "A"
    if llr >= a.llr_b and not set(flags) & {"hidepth", "af_gt_half"}:
        return "B"
    if llr >= a.llr_c:
        return "C"
    if llr <= a.llr_ref and n >= a.ref_min_depth:
        return "ref"
    return "."


def score(pools, recs, witness, controls, a):
    """Yield one output row per record; witness None: no witness group (--bc1-vcf)."""
    if witness is not None and witness not in pools:
        sys.exit(f"witness {witness} not among the VCF samples {pools}")
    w = pools.index(witness) if witness is not None else None
    bc1 = [i for i in range(len(pools)) if i != w]
    logw = log_weights(a.plants)
    rows = []
    for chrom, pos, ref, alt, cnt in recs:
        b73 = [control_counts(c, chrom, pos, ref, alt) for c in controls]
        groups = [[cnt[i] for i in bc1]] + ([[cnt[w]]] if w is not None else []) + [b73]
        rows.append((chrom, pos, ref, alt, cnt, groups, sum(n for g in groups for n, _ in g)))
    med = statistics.median(r[6] for r in rows) if rows else 0
    t0 = last = time.monotonic()
    for done, (chrom, pos, ref, alt, cnt, groups, total) in enumerate(rows, 1):
        zero = [g for g in groups if sum(llr_pool(n, k, a.eps0, a.plants, logw) for n, k in g) < a.zero_class_llr]
        n0 = sum(n for g in zero for n, _ in g)
        a0 = sum(k for g in zero for _, k in g)
        eps = max((a0 + 0.5) / (n0 + 1), a.eps_floor) if n0 >= a.zero_class_min_reads else a.eps0
        bc1_cnt = groups[0]
        n = sum(c[0] for c in bc1_cnt)
        k = sum(c[1] for c in bc1_cnt)
        llr = sum(llr_pool(ni, ki, eps, a.plants, logw) for ni, ki in bc1_cnt)
        flags = []
        if total > a.hidepth_factor * med:
            flags.append("hidepth")
        if n >= a.af_gt_half_min_depth and 2 * k > n and binom_sf_half(n, k) < a.af_gt_half_p:
            flags.append("af_gt_half")
        if any(c[1] >= a.inconsistent_min_alt for c in bc1_cnt) and \
                any(c[0] >= a.inconsistent_min_depth and c[1] == 0 for c in bc1_cnt):
            flags.append("inconsistent")
        npa = sum(1 for c in bc1_cnt if c[1] > 0)
        counts = ";".join(f"{pools[i]}:{cnt[i][1]}/{cnt[i][0]}" for i in range(len(pools)) if i != w)
        yield [chrom, pos, ref, alt, n, k, npa, f"{eps:.6g}", f"{llr:.4f}", tier_of(llr, n, npa, flags, a),
               ",".join(flags) or ".", counts]
        now = time.monotonic()
        if now - last >= 60:
            last = now
            LOG.info("%d/%d sites scored, %.1f min", done, len(rows), (now - t0) / 60)


def write_sites(path, template, recs, sites):
    """Sites-only VCF; contigs from the template's header, else from the records (CRISP writes none, and bcftools merge
    of unindexed VCFs needs them)."""
    header = pysam.VariantHeader()
    with pysam.VariantFile(template) as vcf:
        contigs = [(c.name, c.length) for c in vcf.header.contigs.values()]
    for name, length in contigs or [(c, None) for c in dict.fromkeys(r[0] for r in recs)]:
        header.contigs.add(name, length=length)
    with pysam.VariantFile(path, "w", header=header) as out:
        for chrom, pos, ref, alt in sites:
            out.write(out.new_record(contig=chrom, start=pos - 1, alleles=(ref, alt)))


def main(argv=None):
    logging.basicConfig(stream=sys.stderr, level=logging.INFO, format="%(asctime)s %(message)s",
                        datefmt="%Y-%m-%d %H:%M:%S")
    a = parse_args(argv)
    pools, recs = read_crisp(a.vcf) if a.vcf else read_bc1(a.bc1_vcf, read_sites(a.sites))
    controls = [read_control(p) for p in a.controls]
    tiers, tier_a = {}, []
    with gzip.open(a.out, "wt") as out:
        out.write("\t".join(COLUMNS) + "\n")
        for row in score(pools, recs, a.witness, controls, a):
            out.write("\t".join(str(v) for v in row) + "\n")
            tiers[row[9]] = tiers.get(row[9], 0) + 1
            if row[9] == "A":
                tier_a.append(row[:4])
    if a.tier_a_vcf:
        write_sites(a.tier_a_vcf, a.vcf or a.sites, recs, tier_a)
    LOG.info("%s: %d sites; tiers %s", a.out, len(recs), " ".join(f"{t} {c}" for t, c in sorted(tiers.items())))


if __name__ == "__main__":
    main()
