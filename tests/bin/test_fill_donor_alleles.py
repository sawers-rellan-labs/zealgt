"""Unit tests for bin/fill_donor_alleles.py: hand-computed priors and posteriors, and zealbc1's gap calls.

The zealbc1 reference (fixtures/genotype/fill/zealbc1_dhd_bayes.tsv) is the output of zealbc1's PHG/bin/dhd_bayes.py
(w 2, alt 0.999) on 300 sites of its chr10 pilot union (Zx.0540_P3, Zx.0570_P2; agent script build_fill_fixture.py):
the union, each donor's tier-A sites and its step-4 table at the union, as in this folder.
"""
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


def test_sharing_rate_counts_gaps_only():
    table = {S1: ("A", 10, 9.0, "."), S2: ("ref", 20, -6.0, "."), S3: ("A", 10, 8.0, ".")}
    # S3 is own: gaps S1 (A) and S2 (ref) -> (1 + 0.5) / (2 + 1)
    assert fill.sharing_rate([S1, S2, S3], {S3}, table) == pytest.approx(0.5)


def test_prior_and_posterior_by_hand():
    # donors X, Y, Z; S1 own in Y, tier ref in Z: for X, k = 1, m = 2
    tables = {"X": {S1: ("B", 10, 5.0, ".")}, "Y": {S1: ("A", 10, 9.0, ".")}, "Z": {S1: ("ref", 20, -6.0, ".")}}
    own = {"X": set(), "Y": {S1}, "Z": set()}
    (_, cells), = fill.fill([S1], ["X", "Y", "Z"], own, tables, 2.0, 0.999)
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
    assert fill.call(row, pi, 0.999)[0] == gt


def test_own_site_without_support_is_missing():
    # an own site whose reads at the union give LLR 1: posterior well under 0.999 -> missing, not REF
    tables = {"X": {S1: ("C", 15, 1.0, ".")}, "Y": {S1: (".", 3, 0.0, ".")}}
    (_, cells), = fill.fill([S1], ["X", "Y"], {"X": {S1}, "Y": set()}, tables, 2.0, 0.999)
    assert cells[0][0] == "." and cells[0][4] == "own"


@pytest.fixture(scope="module")
def ours(tmp_path_factory):
    out = tmp_path_factory.mktemp("fill") / "donor_alleles.vcf.gz"
    argv = ["--union", str(FIX / "union.vcf"), "--out", str(out), "--w", "2", "--alt", "0.999"]
    for d in DONORS:
        argv += ["--donor", d, str(FIX / f"{d}.tier_a.vcf"), str(FIX / f"{d}.sites.tsv")]
    fill.main(argv)
    rows = {}
    gt = {(1,): "1", (0,): "0", (None,): "."}
    with pysam.VariantFile(str(out)) as vcf:
        assert list(vcf.header.samples) == DONORS
        assert vcf.fetch("chr10")  # the .tbi is there
        for rec in vcf:
            assert list(rec.format) == ["GT", "LLR", "PRIOR", "PP", "SRC"]
            rows[str(rec.pos)] = [dict(GT=gt[c["GT"]], LLR=c["LLR"], PRIOR=c["PRIOR"], PP=c["PP"], SRC=c["SRC"])
                                  for c in rec.samples.values()]
    return rows


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
            assert float(o["PP"]) == pytest.approx(float(z[f"{d}_posterior"]), abs=1e-3)
            assert o["GT"] == {"1": "1", "0": "0", "NA": "."}[z[f"{d}_state_bayes"]], (pos, d)


def test_own_sites_rescored(ours, zealbc1):
    # zealbc1 keeps every own site ALT; here an own site is ALT only at posterior >= 0.999
    own = [(o, z) for pos, z in zealbc1.items() for d, o in zip(DONORS, ours[pos]) if o["SRC"] == "own"]
    assert all(float(o["PP"]) >= 0.999 for o, _ in own if o["GT"] == "1")
    assert {o["GT"] for o, _ in own} == {"1", ".", "0"}


def test_reference_covers_every_gap_state(zealbc1):
    assert {z[f"{d}_state_bayes"] for z in zealbc1.values() for d in DONORS if z[f"{d}_src"] == "gap"} == {"1", "0", "NA"}
