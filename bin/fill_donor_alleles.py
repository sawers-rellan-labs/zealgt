#!/usr/bin/env python3
"""Each donor's allele at every union site (math supplement, Text S5, Eq. eb: gap filling, step 1).

Per donor d and site s, from the donor's site table at the union (score_pooled_likelihood.py --bc1-vcf):
  k = other donors with s among their own tier-A sites, m = k + other donors with s a gap scored tier 'ref'
  pi = (w mu_d + k) / (w + m), mu_d = (A + 0.5) / (A + R + 1) with A, R the tier-A and tier-ref sites among d's gaps
  PALT = sigmoid(LLR + logit pi)
  GT = 0 at tier 'ref' (gaps only); 1 at PALT >= --alt with reads at s and neither hidepth nor af_gt_half; else missing.
Own sites (s in d's tier-A set) are re-scored the same way, but never REF: an own site under --alt becomes missing,
also at tier 'ref' (discovery and the union count disagree; user, 2026-10-05).

Two modes, so that no step holds all donors at once:
  counts: per union site, K = donors with s among their own tier-A sites, R = donors with s a gap scored tier 'ref';
          reads one donor at a time; writes a gzipped TSV (chrom, pos, K, R) in union order.
  fill:   one donor; k and m are K and R less the donor's own share (k = K - [own], m = k + R - [ref gap]);
          writes a bgzipped, tabix-indexed VCF with the donor as one haploid sample: GT, LLR, PRIOR, PALT, SRC (own or
          gap), with pysam. bcftools merge joins the donors into the one-step file.
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
    ("PALT", 1, "Float", "Posterior probability that the donor allele is ALT (Eq. eb)"),
    ("SRC", 1, "String", "own: among the donor's tier-A sites; gap: discovered in other donors"),
]
DONOR = dict(nargs=3, metavar=("NAME", "TIER_A_VCF", "TABLE"))


def parse_args(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="mode", required=True)
    c = sub.add_parser("counts", help="K and R per union site, over all donors")
    c.add_argument("--union", required=True, help="union sites VCF (.vcf or .vcf.gz)")
    c.add_argument("--donor", action="append", required=True, **DONOR,
                   help="a donor, its tier-A sites VCF and its site table at the union; once per donor")
    c.add_argument("--out", required=True, help="site counts (.tsv.gz)")
    f = sub.add_parser("fill", help="one donor's allele at every union site")
    f.add_argument("--union", required=True, help="union sites VCF (.vcf or .vcf.gz)")
    f.add_argument("--donor", required=True, **DONOR, help="the donor, its tier-A sites VCF and its site table at the union")
    f.add_argument("--counts", required=True, help="site counts of all donors (counts mode)")
    f.add_argument("--out", required=True, help="output VCF (.vcf.gz; the .tbi is written next to it)")
    req = f.add_argument_group("model settings (values in conf/modules.config)")
    req.add_argument("--w", type=float, required=True, help="prior weight of the donor's sharing rate")
    req.add_argument("--alt", type=float, required=True, help="posterior of ALT at which ALT is called")
    a = ap.parse_args(argv)
    if a.mode == "counts":
        if not a.out.endswith(".tsv.gz"):
            ap.error("--out must end in .tsv.gz")
        if len({d[0] for d in a.donor}) != len(a.donor):
            ap.error("donor names must differ")
    else:
        if a.w <= 0 or not 0.5 < a.alt < 1:
            ap.error("need w > 0 and 0.5 < alt < 1")
        if not a.out.endswith(".vcf.gz"):
            ap.error("--out must end in .vcf.gz")
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


def read_counts(path, sites):
    """Site counts -> [(K, R)] in union order; the file must list the union's sites in that order."""
    with open_text(path) as fh:
        fh.readline()
        rows = [line.rstrip("\n").split("\t") for line in fh]
    if [(x[0], int(x[1])) for x in rows] != [(s[0], s[1]) for s in sites]:
        sys.exit(f"{path}: sites differ from the union's")
    return [(int(x[2]), int(x[3])) for x in rows]


def sigmoid(z):
    return 1 / (1 + math.exp(-z)) if z >= 0 else math.exp(z) / (1 + math.exp(z))


def sharing_rate(sites, own, table):
    """mu_d: tier A over tier A + ref among the donor's gaps, with a half count added to A and one to the total."""
    tiers = [table.get(s, NO_ROW)[0] for s in sites if s not in own]
    return (tiers.count("A") + 0.5) / (tiers.count("A") + tiers.count("ref") + 1)


def call(row, pi, alt, own):
    """(GT, PALT) of one donor at one site; own: the site is among the donor's tier-A sites."""
    tier, n, llr, flags = row
    pp = sigmoid(llr + math.log(pi / (1 - pi)))
    if tier == "ref":
        return ("." if own else "0"), pp
    if n > 0 and pp >= alt and not set(flags.split(",")) & NEVER_ALT:
        return "1", pp
    return ".", pp


def site_counts(sites, donors):
    """[K], [R] per union site; donors: (name, own sites, table), one at a time."""
    K, R = [0] * len(sites), [0] * len(sites)
    for name, own, table in donors:
        for i, s in enumerate(sites):
            if s in own:
                K[i] += 1
            elif table.get(s, NO_ROW)[0] == "ref":
                R[i] += 1
        LOG.info("%s: %d own sites counted", name, len(own))
    return K, R


def fill(sites, own, table, counts, w, alt):
    """Yield (site, (GT, LLR, PRIOR, PALT, SRC)) of one donor at every union site; counts: (K, R) per site."""
    mu = sharing_rate(sites, own, table)
    LOG.info("%d own sites, mu = %.4f", len(own), mu)
    t0 = last = time.monotonic()
    for done, (s, (K, R)) in enumerate(zip(sites, counts), 1):
        carrier = s in own
        row = table.get(s, NO_ROW)
        k = K - carrier
        m = k + R - (not carrier and row[0] == "ref")
        pi = min(max((w * mu + k) / (w + m), 1e-6), 1 - 1e-6)
        gt, pp = call(row, pi, alt, carrier)
        yield s, (gt, row[2], pi, pp, "own" if carrier else "gap")
        now = time.monotonic()
        if now - last >= 60:
            last = now
            LOG.info("%d/%d sites filled, %.1f min", done, len(sites), (now - t0) / 60)


def write_counts(a, sites):
    # a generator, so one donor's sites and table are in memory at a time
    K, R = site_counts(sites, ((n, set(read_vcf_sites(v)[1]), read_table(t)) for n, v, t in a.donor))
    with gzip.open(a.out, "wt") as out:
        out.write("chrom\tpos\tK\tR\n")
        for (chrom, pos, _, _), k, r in zip(sites, K, R):
            out.write(f"{chrom}\t{pos}\t{k}\t{r}\n")


def write_alleles(a, contigs, sites):
    name, vcf, path = a.donor
    own = set(read_vcf_sites(vcf)[1])
    table = read_table(path)
    counts = read_counts(a.counts, sites)
    header = pysam.VariantHeader()
    for chrom, length in contigs:
        header.contigs.add(chrom, length=length)
    for fid, number, kind, desc in FORMAT:
        header.formats.add(fid, number, kind, desc)
    header.add_sample(name)
    tally = {}
    with pysam.VariantFile(a.out, "wz", header=header) as out:
        for (chrom, pos, ref, alt), (gt, llr, pi, pp, src) in fill(sites, own, table, counts, a.w, a.alt):
            rec = out.new_record(contig=chrom, start=pos - 1, alleles=(ref, alt))
            cell = rec.samples[name]
            cell["GT"] = (None,) if gt == "." else (int(gt),)
            cell["LLR"], cell["PRIOR"], cell["PALT"], cell["SRC"] = llr, pi, pp, src
            tally[(src, gt)] = tally.get((src, gt), 0) + 1
            out.write(rec)
    pysam.tabix_index(a.out, preset="vcf", force=True)
    LOG.info("%s: %s", name, " ".join(f"{src} {gt} {c}" for (src, gt), c in sorted(tally.items())))


def main(argv=None):
    logging.basicConfig(stream=sys.stderr, level=logging.INFO, format="%(asctime)s %(message)s",
                        datefmt="%Y-%m-%d %H:%M:%S")
    a = parse_args(argv)
    contigs, sites = read_vcf_sites(a.union)
    LOG.info("%s: %d union sites", a.union, len(sites))
    if a.mode == "counts":
        write_counts(a, sites)
    else:
        write_alleles(a, contigs, sites)


if __name__ == "__main__":
    main()
