#!/usr/bin/env python3
"""The markers of one region whose reads fit the lines that count them (decisions.md 2026-10-24, Milestone 9h).

Per donor d: its count VCF (its lines at its markers, AD per line) and its markers VCF.
  lambda_l = line l's reads at d's markers / d's markers    (the line's mean reads per marker)
  E_d      = sum of lambda_l over d's lines                 (the reads expected at one of d's markers)
Per site s, over the donors with a record at s in their count VCF:
  ratio_s = sum of the lines' reads at s / sum of E_d
A site is kept where --min-ratio <= ratio_s <= --max-ratio. Writes each donor's markers VCF with its kept sites only
(plain VCF, the input's header and record order).
"""
import argparse
import gzip
import logging
import sys
import time

LOG = logging.getLogger("filter_site_depth")


def parse_args(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--donor", action="append", required=True, nargs=3, metavar=("COUNTS_VCF", "MARKERS_VCF", "OUT"),
                    help="a donor's count VCF, its markers VCF (.vcf or .vcf.gz) and its kept markers (.vcf); once per donor")
    ap.add_argument("--min-ratio", type=float, required=True, help="smallest reads / expected reads kept")
    ap.add_argument("--max-ratio", type=float, required=True, help="largest reads / expected reads kept")
    return ap.parse_args(argv)


def open_text(path):
    return gzip.open(path, "rt") if path.endswith(".gz") else open(path)


def count_markers(path):
    """Records in a VCF."""
    with open_text(path) as f:
        return sum(1 for line in f if not line.startswith("#"))


def write_kept(path, out, kept):
    """The VCF's header and its records at the kept sites; the number written."""
    n = 0
    with open_text(path) as f, open(out, "w") as o:
        for line in f:
            if line.startswith("#"):
                o.write(line)
                continue
            col = line.split("\t", 2)
            if (col[0], int(col[1])) in kept:
                o.write(line)
                n += 1
    return n


def site_reads(path):
    """Per record (chrom, pos): the reads summed over the samples (AD, '.' as 0); and each sample's reads summed."""
    sites, per_line = {}, None
    with open_text(path) as f:
        for line in f:
            if line.startswith("##"):
                continue
            col = line.rstrip("\n").split("\t")
            if line.startswith("#"):
                per_line = [0] * (len(col) - 9)
                continue
            ad = col[8].split(":").index("AD")
            total = 0
            for i, cell in enumerate(col[9:]):
                parts = cell.split(":")
                n = sum(int(x) for x in parts[ad].split(",") if x != ".") if ad < len(parts) else 0
                per_line[i] += n
                total += n
            sites[(col[0], int(col[1]))] = total
    return sites, per_line or []


def main(argv=None):
    logging.basicConfig(stream=sys.stderr, level=logging.INFO, format="%(asctime)s %(message)s",
                        datefmt="%Y-%m-%d %H:%M:%S")
    a = parse_args(argv)
    reads, expected = {}, {}
    t0 = last = time.time()
    for k, (counts, markers, _out) in enumerate(a.donor, 1):
        sites, per_line = site_reads(counts)
        n = count_markers(markers)
        e = sum(r / n for r in per_line) if n else 0.0
        for s, r in sites.items():
            reads[s] = reads.get(s, 0) + r
            expected[s] = expected.get(s, 0.0) + e
        LOG.info("%s: %d lines, %d markers, %d records, %.2f expected reads per marker", counts, len(per_line), n,
                 len(sites), e)
        if time.time() - last >= 60:
            last = time.time()
            LOG.info("%d/%d donors read, %.1f min", k, len(a.donor), (last - t0) / 60)
    kept = {s for s in reads if expected[s] > 0 and a.min_ratio <= reads[s] / expected[s] <= a.max_ratio}
    LOG.info("%d of %d sites kept (reads / expected in [%g, %g])", len(kept), len(reads), a.min_ratio, a.max_ratio)
    for _counts, markers, out in a.donor:
        LOG.info("%s: %d markers kept", out, write_kept(markers, out, kept))


if __name__ == "__main__":
    main()
