#!/usr/bin/env python3
"""Flag a taxon's marker sites in one region (depth 0.5-2x, MQ > 40, line share >= 0.05, wideseq) and write their union."""
import argparse
import sys
import time
from collections import defaultdict

import pysam


def reads(ad):
    return sum(a for a in (ad or ()) if a is not None)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    for arg in ("--region", "--known-sites", "--prefix"):
        p.add_argument(arg, required=True)
    for arg in ("--donor", "--recount", "--markers", "--counts"):
        p.add_argument(arg, action="append", required=True)
    a = p.parse_args()
    pysam.set_verbosity(0)
    donors = sorted(zip(a.donor, a.recount, a.markers, a.counts))
    log = lambda msg: print(f"{time.strftime('%F %T')} {a.region} {msg}", file=sys.stderr, flush=True)

    # per position over the donors' recounts: lines, reads, expected reads, lines with an ALT read, MQ x reads
    s = defaultdict(lambda: [0, 0, 0.0, 0, 0.0])
    for donor, recount, _markers, counts in donors:
        with pysam.VariantFile(counts) as v:  # expected reads: each line's reads per record in the source run's counts
            names, n_rec, tot = list(v.header.samples), 0, defaultdict(int)
            for rec in v:
                n_rec += 1
                for x in names:
                    tot[x] += reads(rec.samples[x].get("AD"))
        lam = {x: tot[x] / n_rec if n_rec else 0 for x in names}
        with pysam.VariantFile(recount) as v:
            names = list(v.header.samples)
            e = sum(lam.get(x, 0) for x in names)
            for rec in v:
                ads = [rec.samples[x].get("AD") or () for x in names]
                dp = sum(reads(ad) for ad in ads)
                alt = sum(1 for ad in ads if len(ad) > 1 and ad[1] is not None and ad[1] > 0)
                row = (len(names), dp, e, alt, (rec.info.get("MQ", 0) or 0) * dp)
                s[rec.pos] = [x + y for x, y in zip(s[rec.pos], row)]
        log(f"{donor}: {len(s)} positions so far")
    flags = {pos: (0.5 <= (dp / e if e > 0 else 0) <= 2, dp > 0 and mqw / dp > 40, n > 0 and alt / n >= 0.05)
             for pos, (n, dp, e, alt, mqw) in s.items()}
    with open(f"{a.prefix}.flags.tsv", "w") as f:
        f.write("pos\tdepth\tmq\tline_share\n")
        f.writelines(f"{pos}\t" + "\t".join(str(int(x)) for x in flags[pos]) + "\n" for pos in sorted(flags))

    # wideseq sites at the donors' marker positions
    body = lambda m: (l for l in open(m) if not l.startswith("#"))  # noqa: E731
    wanted = {int(l.split("\t", 2)[1]) for _d, _r, m, _c in donors for l in body(m)}
    with pysam.VariantFile(a.known_sites) as ws:
        known = {(r.pos, r.ref, ",".join(r.alts or ())) for r in ws.fetch(a.region.split(":")[0]) if r.pos in wanted}

    # each donor's markers through depth, MQ, wideseq, line share (row 2's order); the union keeps the first per position
    union = {}
    with open(f"{a.prefix}.marker_counts.tsv", "w") as mc:
        mc.write("donor\tchrom\tmarkers\trecounted\tdepth\tdepth_mq\tdepth_mq_wideseq\tdepth_mq_wideseq_maf\n")
        for donor, _recount, markers, _counts in donors:
            c = [0] * 6
            for line in body(markers):
                c[0] += 1
                col = line.split("\t", 5)
                pos, fl = int(col[1]), flags.get(int(col[1]))
                steps = (fl, fl and fl[0], fl and fl[1], (pos, col[3], col[4]) in known, fl and fl[2])
                passed = next((i for i, ok in enumerate(steps) if not ok), 5)
                for i in range(passed):
                    c[i + 1] += 1
                if passed == 5:
                    union.setdefault(pos, line)
            mc.write(f"{donor}\t{a.region}\t" + "\t".join(map(str, c)) + "\n")
            log(f"{donor}: {c[0]} markers -> {c[5]} kept")
    with open(f"{a.prefix}.union_markers.vcf", "w") as out:
        out.writelines(l for l in open(donors[0][2]) if l.startswith("#"))
        out.writelines(union[pos] for pos in sorted(union))
    log(f"union {len(union)} positions")


if __name__ == "__main__":
    main()
