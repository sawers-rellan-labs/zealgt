#!/usr/bin/env python3
"""Each donor's allele at every union site (math supplement, Text S5, Eq. eb: gap filling, step 1).

Per donor d and site s, from the donor's site table at the union (score_pooled_likelihood.py --bc1-vcf):
  k = other donors with s among their own tier-A sites, m = k + other donors with s a gap scored tier 'ref'
  pi = (w mu_d + k) / (w + m), mu_d = (A + 0.5) / (A + R + 1) with A, R the tier-A and tier-ref sites among d's gaps
  PP = sigmoid(LLR + logit pi)
  GT = 0 at tier 'ref'; 1 at PP >= --alt with reads at s and neither hidepth nor af_gt_half; else missing.
Own sites (s in d's tier-A set) are re-scored the same way: an own site under --alt becomes missing.
Writes a bgzipped, tabix-indexed VCF with one haploid sample per donor: GT, LLR, PRIOR, PP, SRC (own or gap), with pysam.
"""
import argparse
import gzip
import logging
import math
import sys
import time

import pysam

LOG = logging.getLogger("fill_donor_alleles")
NEVER_ALT = {"hidepth", "af_gt_half"}
NO_ROW = (".", 0, 0.0, ".")
FORMAT = [
    ("GT", 1, "String", "Donor allele: 1 ALT, 0 REF, . missing"),
    ("LLR", 1, "Float", "Pooled likelihood ratio of the donor's BC1 reads"),
    ("PRIOR", 1, "Float", "Prior of ALT from the other donors (Eq. eb)"),
    ("PP", 1, "Float", "Posterior of ALT"),
    ("SRC", 1, "String", "own: among the donor's tier-A sites; gap: discovered in other donors"),
]


def parse_args(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--union", required=True, help="union sites VCF (.vcf or .vcf.gz)")
    ap.add_argument("--donor", nargs=3, action="append", required=True, metavar=("NAME", "TIER_A_VCF", "TABLE"),
                    help="a donor, its tier-A sites VCF and its site table at the union; once per donor")
    ap.add_argument("--out", required=True, help="output VCF (.vcf.gz; the .tbi is written next to it)")
    req = ap.add_argument_group("model settings (values in conf/modules.config)")
    req.add_argument("--w", type=float, required=True, help="prior weight of the donor's sharing rate")
    req.add_argument("--alt", type=float, required=True, help="posterior of ALT at which ALT is called")
    a = ap.parse_args(argv)
    if a.w <= 0 or not 0.5 < a.alt < 1:
        ap.error("need w > 0 and 0.5 < alt < 1")
    if not a.out.endswith(".vcf.gz"):
        ap.error("--out must end in .vcf.gz")
    if len({d[0] for d in a.donor}) != len(a.donor):
        ap.error("donor names must differ")
    return a


def open_text(path):
    with open(path, "rb") as fh:
        gz = fh.read(2) == b"\x1f\x8b"
    return gzip.open(path, "rt") if gz else open(path)


def read_vcf_sites(path):
    """VCF -> (header contigs as (name, length), [(chrom, pos, ref, alt)])."""
    with pysam.VariantFile(path) as vcf:
        sites = [(rec.chrom, rec.pos, rec.ref, rec.alts[0]) for rec in vcf]
        contigs = [(c.name, c.length) for c in vcf.header.contigs.values()]
    return contigs, sites


def read_table(path):
    """Site table -> {(chrom, pos, ref, alt): (tier, n, LLR, flags)}."""
    rows = {}
    with open_text(path) as fh:
        col = {k: i for i, k in enumerate(fh.readline().rstrip("\n").split("\t"))}
        for line in fh:
            x = line.rstrip("\n").split("\t")
            rows[(x[col["chrom"]], int(x[col["pos"]]), x[col["ref"]], x[col["alt"]])] = (
                x[col["tier"]], int(x[col["n"]]), float(x[col["LLR"]]), x[col["flags"]])
    return rows


def sigmoid(z):
    return 1 / (1 + math.exp(-z)) if z >= 0 else math.exp(z) / (1 + math.exp(z))


def sharing_rate(sites, own, table):
    """mu_d: tier A over tier A + ref among the donor's gaps, with a half count added to A and one to the total."""
    tiers = [table.get(s, NO_ROW)[0] for s in sites if s not in own]
    return (tiers.count("A") + 0.5) / (tiers.count("A") + tiers.count("ref") + 1)


def call(row, pi, alt):
    """(GT, PP) of one donor at one site."""
    tier, n, llr, flags = row
    pp = sigmoid(llr + math.log(pi / (1 - pi)))
    if tier == "ref":
        return "0", pp
    if n > 0 and pp >= alt and not set(flags.split(",")) & NEVER_ALT:
        return "1", pp
    return ".", pp


def fill(sites, donors, own, tables, w, alt):
    """Yield (site, [(GT, LLR, PRIOR, PP, SRC) per donor]) for every union site."""
    mu = {d: sharing_rate(sites, own[d], tables[d]) for d in donors}
    for d in donors:
        LOG.info("%s: %d own sites, mu = %.4f", d, len(own[d]), mu[d])
    t0 = last = time.monotonic()
    for done, s in enumerate(sites, 1):
        carriers = {d for d in donors if s in own[d]}
        ref = {d for d in donors if d not in carriers and tables[d].get(s, NO_ROW)[0] == "ref"}
        cells = []
        for d in donors:
            k = len(carriers - {d})
            m = k + len(ref - {d})
            pi = min(max((w * mu[d] + k) / (w + m), 1e-6), 1 - 1e-6)
            row = tables[d].get(s, NO_ROW)
            gt, pp = call(row, pi, alt)
            cells.append((gt, row[2], pi, pp, "own" if d in carriers else "gap"))
        yield s, cells
        now = time.monotonic()
        if now - last >= 60:
            last = now
            LOG.info("%d/%d sites filled, %.1f min", done, len(sites), (now - t0) / 60)


def main(argv=None):
    logging.basicConfig(stream=sys.stderr, level=logging.INFO, format="%(asctime)s %(message)s",
                        datefmt="%Y-%m-%d %H:%M:%S")
    a = parse_args(argv)
    contigs, sites = read_vcf_sites(a.union)
    LOG.info("%s: %d union sites", a.union, len(sites))
    donors = [d[0] for d in a.donor]
    own = {d: set(read_vcf_sites(v)[1]) for d, v, _ in a.donor}
    tables = {d: read_table(t) for d, _, t in a.donor}
    header = pysam.VariantHeader()
    for name, length in contigs:
        header.contigs.add(name, length=length)
    for fid, number, kind, desc in FORMAT:
        header.formats.add(fid, number, kind, desc)
    for d in donors:
        header.add_sample(d)
    counts = {d: {} for d in donors}
    with pysam.VariantFile(a.out, "wz", header=header) as out:
        for (chrom, pos, ref, alt), cells in fill(sites, donors, own, tables, a.w, a.alt):
            rec = out.new_record(contig=chrom, start=pos - 1, alleles=(ref, alt))
            for d, (gt, llr, pi, pp, src) in zip(donors, cells):
                call = rec.samples[d]
                call["GT"] = (None,) if gt == "." else (int(gt),)
                call["LLR"], call["PRIOR"], call["PP"], call["SRC"] = llr, pi, pp, src
                counts[d][(src, gt)] = counts[d].get((src, gt), 0) + 1
            out.write(rec)
    pysam.tabix_index(a.out, preset="vcf", force=True)
    for d in donors:
        LOG.info("%s: %s", d, " ".join(f"{src} {gt} {c}" for (src, gt), c in sorted(counts[d].items())))


if __name__ == "__main__":
    main()
