"""Unit tests for bin/fill_donor_alleles.py: hand-computed site counts, priors and posteriors, zealbc1's gap calls, and
Milestone 8's one-step output.

The zealbc1 reference (fixtures/genotype/fill/zealbc1_dhd_bayes.tsv) is the output of zealbc1's PHG/bin/dhd_bayes.py
(w 2, alt 0.999) on 300 sites of its chr10 pilot union (Zx.0540_P3, Zx.0570_P2; agent script build_fill_fixture.py):
the union, each donor's tier-A sites and its step-4 table at the union, as in this folder.
The Milestone 8 reference (fixtures/genotype/fill/m8_donor_alleles.vcf) is the one-step tool (dev ef72df1) on the same
files with three donors: Zx.0540_P3, its files again as Zx.0540_twin, and Zx.0570_P2.
"""
import gzip
import csv
import importlib.util
import math
from pathlib import Path

import pysam
import pytest

ROOT = Path(__file__).resolve().parents[2]
FIX = ROOT / "tests" / "fixtures" / "genotype" / "fill"
DONORS = ["Zx.0540_P3", "Zx.0570_P2"]
spec = importlib.util.spec_from_file_location("fill", ROOT / "bin" / "fill_donor_alleles.py")
fill = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fill)

S1, S2, S3 = ("c", 1, "A", "G"), ("c", 2, "C", "T"), ("c", 3, "G", "A")


def two_step(sites, donors, own, tables, w=2.0, alt=0.999):
    """Cells of all donors per site: the site counts over all donors, then each donor alone."""
    K, R = fill.site_counts(sites, ((d, own[d], tables[d]) for d in donors))
    cols = [[c for _, c in fill.fill(sites, own[d], tables[d], list(zip(K, R)), w, alt)] for d in donors]
    return list(zip(*cols))


def test_site_counts_by_hand():
    # S1 own in Y, ref in Z; S2 own in X and Y, ref in Z; S3 own in X (scored ref: own, so not in R), ref in Y, no row in Z
    own = {"X": {S2, S3}, "Y": {S1, S2}, "Z": set()}
    tables = {"X": {S1: ("B", 10, 5.0, "."), S2: ("A", 10, 9.0, "."), S3: ("ref", 20, -6.0, ".")},
              "Y": {S1: ("A", 10, 9.0, "."), S2: ("A", 10, 9.0, "."), S3: ("ref", 20, -6.0, ".")},
              "Z": {S1: ("ref", 20, -6.0, "."), S2: ("ref", 20, -6.0, ".")}}
    K, R = fill.site_counts([S1, S2, S3], ((d, own[d], tables[d]) for d in "XYZ"))
    assert (K, R) == ([1, 2, 1], [1, 1, 1])
    # leave-one-out at S3: X own (k 0, m 1), Y ref gap (k 1, m 1), Z no row (k 1, m 2); mu: X 0.5/1, Y 0.5/2, Z 0.5/3
    priors = [c[2] for c in two_step([S1, S2, S3], "XYZ", own, tables)[2]]
    assert priors == pytest.approx([(2 * 0.5 + 0) / 3, (2 * 0.25 + 1) / 3, (2 * 0.5 / 3 + 1) / 4])


def test_sharing_rate_counts_gaps_only():
    table = {S1: ("A", 10, 9.0, "."), S2: ("ref", 20, -6.0, "."), S3: ("A", 10, 8.0, ".")}
    # S3 is own: gaps S1 (A) and S2 (ref) -> (1 + 0.5) / (2 + 1)
    assert fill.sharing_rate([S1, S2, S3], {S3}, table) == pytest.approx(0.5)


def test_prior_and_posterior_by_hand():
    # donors X, Y, Z; S1 own in Y, tier ref in Z: for X, k = 1, m = 2
    tables = {"X": {S1: ("B", 10, 5.0, ".")}, "Y": {S1: ("A", 10, 9.0, ".")}, "Z": {S1: ("ref", 20, -6.0, ".")}}
    own = {"X": set(), "Y": {S1}, "Z": set()}
    cells, = two_step([S1], ["X", "Y", "Z"], own, tables)
    mu_x = 0.5 / 1   # X has one gap, tier B: (0 + 0.5) / (0 + 0 + 1)
    pi = (2 * mu_x + 1) / (2 + 2)
    pp = 1 / (1 + math.exp(-(5.0 + math.log(pi / (1 - pi)))))
    gt, llr, prior, post, src = cells[0]
    assert (gt, llr, src) == (".", 5.0, "gap") and prior == pytest.approx(pi) and post == pytest.approx(pp)
    assert pp < 0.999
    # Y's own site: k = 0 (X has no call), m = 1 (Z ref); Z: tier ref -> REF whatever the prior
    assert cells[1][0] == "1" and cells[1][4] == "own" and cells[2][0] == "0"


@pytest.mark.parametrize("row,pi,gt", [
    (("A", 20, 9.0, "."), 0.5, "1"),             # posterior 0.99988
    (("A", 20, 6.0, "."), 0.5, "."),             # posterior 0.9975: under the cut
    (("A", 20, 6.0, "."), 0.9, "1"),             # the prior lifts it
    (("A", 20, 9.0, "hidepth"), 0.5, "."),       # never promoted
    (("B", 20, 9.0, "af_gt_half,x"), 0.5, "."),
    (("B", 20, 9.0, "inconsistent"), 0.5, "1"),  # blocks tier A only, not the posterior
    (("ref", 20, -6.0, "."), 1 - 1e-6, "0"),     # tier ref: REF from the donor's own reads
    ((".", 0, 0.0, "."), 1 - 1e-6, "."),         # no reads: never ALT from the prior alone
])
def test_call(row, pi, gt):
    assert fill.call(row, pi, 0.999, False)[0] == gt


@pytest.mark.parametrize("row,gt", [
    (("A", 20, 9.0, "."), "1"),
    (("ref", 20, -6.0, "."), "."),   # discovery said ALT, the union count says B73: missing, never REF
    (("C", 15, 1.0, "."), "."),
])
def test_call_own_site(row, gt):
    assert fill.call(row, 0.5, 0.999, True)[0] == gt


def test_own_site_without_support_is_missing():
    # an own site whose reads at the union give LLR 1: posterior well under 0.999 -> missing, not REF
    tables = {"X": {S1: ("C", 15, 1.0, ".")}, "Y": {S1: (".", 3, 0.0, ".")}}
    cells, = two_step([S1], ["X", "Y"], {"X": {S1}, "Y": set()}, tables)
    assert cells[0][0] == "." and cells[0][4] == "own"


def run_two_step(tmp, donors):
    """The command line, both modes: donors as (name, tier-A VCF, table); returns each donor's VCF."""
    union = ["--union", str(FIX / "union.vcf")]
    args = [a for d in donors for a in ["--donor", *map(str, d)]]
    fill.main(["counts", *union, *args, "--out", str(tmp / "site_counts.tsv.gz")])
    out = {}
    for d in donors:
        out[d[0]] = tmp / f"{d[0]}.vcf.gz"
        fill.main(["fill", *union, "--donor", *map(str, d), "--counts", str(tmp / "site_counts.tsv.gz"),
                   "--out", str(out[d[0]]), "--w", "2", "--alt", "0.999"])
    return out


@pytest.fixture(scope="module")
def ours(tmp_path_factory):
    vcfs = run_two_step(tmp_path_factory.mktemp("fill"), [(d, FIX / f"{d}.tier_a.vcf", FIX / f"{d}.sites.tsv") for d in DONORS])
    rows = {}
    gt = {(1,): "1", (0,): "0", (None,): "."}
    for d in DONORS:
        with pysam.VariantFile(str(vcfs[d])) as vcf:
            assert list(vcf.header.samples) == [d]
            assert vcf.fetch("chr10")  # the .tbi is there
            for rec in vcf:
                assert list(rec.format) == ["GT", "LLR", "PRIOR", "PALT", "SRC"]
                c = rec.samples[d]
                rows.setdefault(str(rec.pos), []).append(dict(GT=gt[c["GT"]], LLR=c["LLR"], PRIOR=c["PRIOR"], PALT=c["PALT"],
                                                              SRC=c["SRC"]))
    return rows


def test_equals_milestone_8(tmp_path):
    # three donors (a twin of Zx.0540_P3), so k and m count two other donors; each donor's records as text
    twin = [("Zx.0540_P3", "Zx.0540_P3"), ("Zx.0540_twin", "Zx.0540_P3"), ("Zx.0570_P2", "Zx.0570_P2")]
    vcfs = run_two_step(tmp_path, [(d, FIX / f"{f}.tier_a.vcf", FIX / f"{f}.sites.tsv") for d, f in twin])
    with open(FIX / "m8_donor_alleles.vcf") as fh:
        m8 = [line.rstrip("\n").split("\t") for line in fh if not line.startswith("##")]
    for i, (d, _) in enumerate(twin):
        with gzip.open(vcfs[d], "rt") as fh:
            ours = [line.rstrip("\n").split("\t") for line in fh if not line.startswith("##")]
        assert len(ours) == len(m8) == 301
        assert [r[:9] + [r[9 + i]] for r in m8] == ours, d


@pytest.fixture(scope="module")
def zealbc1():
    with open(FIX / "zealbc1_dhd_bayes.tsv") as fh:
        return {r["pos"]: r for r in csv.DictReader(fh, delimiter="\t")}


def test_one_record_per_union_site(ours, zealbc1):
    assert len(ours) == 300 and set(ours) == set(zealbc1)


def test_gaps_match_zealbc1(ours, zealbc1):
    for pos, z in zealbc1.items():
        for d, o in zip(DONORS, ours[pos]):
            assert o["SRC"] == z[f"{d}_src"]
            if o["SRC"] != "gap":
                continue
            assert float(o["PRIOR"]) == pytest.approx(float(z[f"{d}_prior"]), abs=5.1e-4)  # zealbc1 rounds to 3 decimals
            assert float(o["PALT"]) == pytest.approx(float(z[f"{d}_posterior"]), abs=1e-3)
            assert o["GT"] == {"1": "1", "0": "0", "NA": "."}[z[f"{d}_state_bayes"]], (pos, d)


def test_own_sites_rescored(ours, zealbc1):
    # zealbc1 keeps every own site ALT; here an own site is ALT only at posterior >= 0.999
    own = [(o, z) for pos, z in zealbc1.items() for d, o in zip(DONORS, ours[pos]) if o["SRC"] == "own"]
    assert all(float(o["PALT"]) >= 0.999 for o, _ in own if o["GT"] == "1")
    assert {o["GT"] for o, _ in own} == {"1", "."}


def test_reference_covers_every_gap_state(zealbc1):
    assert {z[f"{d}_state_bayes"] for z in zealbc1.values() for d in DONORS if z[f"{d}_src"] == "gap"} == {"1", "0", "NA"}
