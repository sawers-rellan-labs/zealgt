#!/usr/bin/env python3
"""Pooled likelihood ratio, flags and tiers per site for one donor (math supplement, "Per-donor variant discovery").

Flags: hidepth (all pools' depth > --hidepth-factor x the median), af_gt_half (BC1 ALT share > 1/2, binomial test),
inconsistent (one BC1 pool with >= --inconsistent-min-alt ALT reads while another has >= --inconsistent-min-depth reads
and none ALT). Tier A: LLR >= --llr-a, ALT reads in >= --a-min-pools-alt pools, no flag; B: LLR >= --llr-b, neither
hidepth nor af_gt_half; C: LLR >= --llr-c; ref: LLR <= --llr-ref with >= --ref-min-depth reads; else ".".
Reads the witness-vetoed CRISP VCF (BC1 pools and the witness; per-pool counts in ADf, ADr, ADb as 'ref,alt') and the
B73 control VCFs from bcftools mpileup (AD), and writes one row per biallelic SNP record. Pool groups: the donor's BC1
pools, the witness, the B73 controls together. Model, per BC1 pool i with n_i reads, a_i ALT:
  L1_i = sum_j C(P,j) 2^-P Bin(a_i; n_i, p_j), p_j = j/2P (1-eps) + (1 - j/2P) eps;  L0_i = Bin(a_i; n_i, eps)
  LLR = sum_i log L1_i - log L0_i
eps per site: the reads of the groups with LLR < --zero-class-llr at --eps0, when they hold >= --zero-class-min-reads,
eps = max((a0 + 0.5) / (n0 + 1), --eps-floor); else --eps0. Standard library only.
"""
import argparse
import gzip
import logging
import math
import statistics
import sys
import time

LOG = logging.getLogger("score_pooled_likelihood")
COLUMNS = ["chrom", "pos", "ref", "alt", "n", "a", "n_pools_alt", "eps", "LLR", "tier", "flags", "pool_counts"]


def parse_args(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--vcf", required=True, help="witness-vetoed CRISP VCF (.vcf or .vcf.gz)")
    ap.add_argument("--witness", required=True, help="the witness pool's sample name in the VCF")
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
    if a.plants < 1 or not 0 < a.eps0 < 0.5 or not 0 < a.eps_floor < 0.5:
        ap.error("need plants >= 1 and 0 < eps0, eps-floor < 0.5")
    return a


def open_text(path):
    with open(path, "rb") as fh:
        gz = fh.read(2) == b"\x1f\x8b"
    return gzip.open(path, "rt") if gz else open(path)


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


def read_crisp(path):
    """CRISP VCF -> (pool names, [(chrom, pos, ref, alt, [(n, a) per pool])]) for biallelic SNPs; n = ref + alt reads."""
    pools, recs, skipped = None, [], 0
    with open_text(path) as fh:
        for line in fh:
            if line.startswith("##"):
                continue
            x = line.rstrip("\n").split("\t")
            if line.startswith("#"):
                pools = x[9:]
                continue
            if not is_snp(x[3], x[4]):
                skipped += 1
                continue
            fmt = x[8].split(":")
            idx = [fmt.index(k) for k in ("ADf", "ADr", "ADb") if k in fmt]
            cnt = []
            for cell in x[9:]:
                v = cell.split(":")
                r = k = 0
                for i in idx:
                    q = v[i].split(",") if i < len(v) else []
                    if len(q) >= 2:
                        r += int(q[0]) if q[0].isdigit() else 0
                        k += int(q[1]) if q[1].isdigit() else 0
                cnt.append((r + k, k))
            recs.append((x[0], int(x[1]), x[3], x[4], cnt))
    if pools is None:
        sys.exit(f"{path}: no #CHROM line")
    LOG.info("%s: %d biallelic SNP records, %d other records skipped", path, len(recs), skipped)
    return pools, recs


def read_control(path):
    """mpileup VCF -> {(chrom, pos): (ref, [alleles], [AD summed over samples])}."""
    rows = {}
    with open_text(path) as fh:
        for line in fh:
            if line.startswith("#"):
                continue
            x = line.rstrip("\n").split("\t")
            fmt = x[8].split(":")
            if "AD" not in fmt:
                continue
            i = fmt.index("AD")
            alleles = [x[3]] + [s for s in x[4].split(",") if s != "."]
            ad = [0] * len(alleles)
            for cell in x[9:]:
                v = cell.split(":")
                for k, c in enumerate(v[i].split(",") if i < len(v) else []):
                    if k < len(ad) and c.isdigit():
                        ad[k] += int(c)
            rows[(x[0], int(x[1]))] = (x[3], alleles, ad)
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
    """Yield one output row per record."""
    if witness not in pools:
        sys.exit(f"witness {witness} not among the VCF samples {pools}")
    w = pools.index(witness)
    bc1 = [i for i in range(len(pools)) if i != w]
    logw = log_weights(a.plants)
    rows = []
    for chrom, pos, ref, alt, cnt in recs:
        b73 = [control_counts(c, chrom, pos, ref, alt) for c in controls]
        groups = [[cnt[i] for i in bc1], [cnt[w]], b73]
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


def main(argv=None):
    logging.basicConfig(stream=sys.stderr, level=logging.INFO, format="%(asctime)s %(message)s",
                        datefmt="%Y-%m-%d %H:%M:%S")
    a = parse_args(argv)
    pools, recs = read_crisp(a.vcf)
    controls = [read_control(p) for p in a.controls]
    tiers = {}
    with gzip.open(a.out, "wt") as out:
        out.write("\t".join(COLUMNS) + "\n")
        for row in score(pools, recs, a.witness, controls, a):
            out.write("\t".join(str(v) for v in row) + "\n")
            tiers[row[9]] = tiers.get(row[9], 0) + 1
    LOG.info("%s: %d sites; tiers %s", a.out, len(recs), " ".join(f"{t} {c}" for t, c in sorted(tiers.items())))


if __name__ == "__main__":
    main()
