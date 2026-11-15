#!/usr/bin/env python3
"""Flag a taxon's marker sites in one region (depth 0.5-2x, MQ > 40, line share >= 0.05, wideseq) and write their union."""
import argparse
import sys
import time
from collections import defaultdict

import pysam


def log(msg):
    print(f"{time.strftime('%F %T')} {msg}", file=sys.stderr, flush=True)


def reads(ad):
    return sum(a for a in (ad or ()) if a is not None)


def expected_reads(path):
    # each line's reads per record in the source run's count VCF
    with pysam.VariantFile(path) as vcf:
        names = list(vcf.header.samples)
        total, records = dict.fromkeys(names, 0), 0
        for rec in vcf:
            records += 1
            for s in names:
                total[s] += reads(rec.samples[s].get("AD"))
    return {s: total[s] / records if records else 0 for s in names}


def site_rows(path, lam):
    # per recounted site: INFO/MQ, lines, their reads, their expected reads, lines with an ALT read
    with pysam.VariantFile(path) as vcf:
        names = list(vcf.header.samples)
        expected = sum(lam.get(s, 0) for s in names)
        for rec in vcf:
            ads = [rec.samples[s].get("AD") or () for s in names]
            alt = sum(1 for ad in ads if len(ad) > 1 and ad[1] is not None and ad[1] > 0)
            yield rec.pos, rec.info.get("MQ", 0) or 0, len(names), sum(reads(ad) for ad in ads), expected, alt


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--region", required=True)
    p.add_argument("--known-sites", required=True, help="wideseq VCF (indexed)")
    p.add_argument("--donor", action="append", required=True)
    p.add_argument("--recount", action="append", required=True)
    p.add_argument("--markers", action="append", required=True)
    p.add_argument("--counts", action="append", required=True)
    p.add_argument("--prefix", required=True)
    a = p.parse_args()
    pysam.set_verbosity(0)  # no htslib notes about the unindexed count VCFs
    donors = sorted(zip(a.donor, a.recount, a.markers, a.counts))

    # step B: sums per position over the donors' recounts
    s = defaultdict(lambda: [0, 0, 0.0, 0, 0.0])  # lines, reads, expected reads, ALT lines, MQ x reads
    for donor, recount, _markers, counts in donors:
        for pos, mq, n, dp, e, alt in site_rows(recount, expected_reads(counts)):
            s[pos] = [x + y for x, y in zip(s[pos], (n, dp, e, alt, mq * dp))]
        log(f"{a.region} {donor}: {len(s)} positions so far")
    flags = {}
    for pos, (n, dp, e, alt, mqw) in s.items():
        r = dp / e if e > 0 else 0
        flags[pos] = (0.5 <= r <= 2, dp > 0 and mqw / dp > 40, n > 0 and alt / n >= 0.05)
    with open(f"{a.prefix}.flags.tsv", "w") as f:
        f.write("pos\tdepth\tmq\tline_share\n")
        for pos in sorted(flags):
            f.write(f"{pos}\t" + "\t".join(str(int(x)) for x in flags[pos]) + "\n")

    # wideseq sites only at the donors' marker positions
    wanted = set()
    for _donor, _recount, markers, _counts in donors:
        with open(markers) as m:
            wanted.update(int(line.split("\t", 2)[1]) for line in m if not line.startswith("#"))
    with pysam.VariantFile(a.known_sites) as ws:
        known = {(r.pos, r.ref, ",".join(r.alts or ())) for r in ws.fetch(a.region.split(":")[0]) if r.pos in wanted}
    log(f"{a.region}: {len(flags)} flagged positions, {len(known)} wideseq sites")

    # each donor's markers through depth, MQ, wideseq, line share (row 2's order); the union keeps the first per position
    union = {}
    with open(donors[0][2]) as m:
        header = [line for line in m if line.startswith("#")]
    with open(f"{a.prefix}.marker_counts.tsv", "w") as mc:
        mc.write("donor\tchrom\tmarkers\trecounted\tdepth\tdepth_mq\tdepth_mq_wideseq\tdepth_mq_wideseq_maf\n")
        for donor, _recount, markers, _counts in donors:
            c = [0] * 6
            with open(markers) as m:
                for line in m:
                    if line.startswith("#"):
                        continue
                    col = line.split("\t", 5)
                    pos = int(col[1])
                    fl = flags.get(pos)
                    steps = (fl is not None, fl and fl[0], fl and fl[1], (pos, col[3], col[4]) in known, fl and fl[2])
                    c[0] += 1
                    for i, ok in enumerate(steps):
                        if not ok:
                            break
                        c[i + 1] += 1
                    else:
                        union.setdefault(pos, line)
            mc.write(f"{donor}\t{a.region}\t" + "\t".join(map(str, c)) + "\n")
            log(f"{a.region} {donor}: {c[0]} markers -> {c[5]} kept")
    with open(f"{a.prefix}.union_markers.vcf", "w") as out:
        out.writelines(header)
        out.writelines(union[pos] for pos in sorted(union))
    log(f"{a.region}: union {len(union)} positions")


if __name__ == "__main__":
    main()
