"""Unit tests for bin/score_pooled_likelihood.py: hand-computed likelihoods, flags and tiers, and zealbc1's step-4 table.

The zealbc1 reference (fixtures/genotype/score/zealbc1_Zx.0540_P3.sites.tsv) is the output of zealbc1's
PHG/bin/pilot_step4_postfilter_llr.py (commit 3d0f6c5) on the same fixture VCFs: witness W as its own group, the two B73
controls as one group (`--extra-counts`), BC1 pools S_A, S_B, S_C as donor Zx.0540_P3.
"""
import csv
import gzip
import importlib.util
import math
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
FIX = ROOT / "tests" / "fixtures" / "genotype" / "score"
spec = importlib.util.spec_from_file_location("score", ROOT / "bin" / "score_pooled_likelihood.py")
score = importlib.util.module_from_spec(spec)
spec.loader.exec_module(score)

# zealbc1's step-4 values, as conf/modules.config passes them
SETTINGS = ("--plants 6 --eps0 0.005 --eps-floor 0.001 --zero-class-llr -3 --zero-class-min-reads 20 --llr-a 6.9 "
            "--llr-b 4.6 --llr-c 2.2 --llr-ref -4 --ref-min-depth 12 --a-min-pools-alt 2 --hidepth-factor 2 "
            "--af-gt-half-min-depth 4 --af-gt-half-p 0.01 --inconsistent-min-alt 3 --inconsistent-min-depth 10").split()
FLAGS = {"hidepth", "af_gt_half", "inconsistent"}


def args(extra=()):
    return score.parse_args(["--vcf", "x", "--witness", "W", "--out", "x"] + SETTINGS + list(extra))


def hand_llr(n, a, eps, plants=6):
    """log L1 - log L0 written out with math.comb: carriers j ~ Bin(P, 1/2), ALT share j/2P with error eps."""
    l1 = sum(math.comb(plants, j) / 2 ** plants * (p := j / (2 * plants) * (1 - eps) + (1 - j / (2 * plants)) * eps) ** a
             * (1 - p) ** (n - a) for j in range(plants + 1))
    return math.log(l1) - math.log(eps ** a * (1 - eps) ** (n - a))


@pytest.mark.parametrize("n,a,eps", [(10, 0, 0.005), (12, 3, 0.005), (20, 1, 0.01), (6, 6, 0.001), (30, 4, 0.02)])
def test_llr_pool_matches_hand_computation(n, a, eps):
    got = score.llr_pool(n, a, eps, 6, score.log_weights(6))
    assert got == pytest.approx(hand_llr(n, a, eps), abs=1e-9)


def test_llr_pool_no_reads_is_zero():
    assert score.llr_pool(0, 0, 0.005, 6, score.log_weights(6)) == 0.0


def test_binom_sf_half():
    assert score.binom_sf_half(4, 4) == pytest.approx(1 / 16)
    assert score.binom_sf_half(10, 0) == pytest.approx(1.0)


@pytest.mark.parametrize("llr,n,npa,flags,tier", [
    (7.0, 20, 2, [], "A"),
    (7.0, 20, 1, [], "B"),                  # ALT reads in one pool only
    (7.0, 20, 2, ["inconsistent"], "B"),    # inconsistent blocks tier A only
    (7.0, 20, 2, ["hidepth"], "C"),
    (5.0, 20, 2, ["af_gt_half"], "C"),
    (2.2, 20, 2, [], "C"),
    (-4.0, 12, 0, [], "ref"),
    (-4.0, 11, 0, [], "."),                 # too few reads for ref
    (0.0, 20, 0, [], "."),
])
def test_tiers(llr, n, npa, flags, tier):
    assert score.tier_of(llr, n, npa, flags, args()) == tier


def rec(pos, counts):
    """One record: witness (n, a) first, then the BC1 pools."""
    return ("chr10", pos, "A", "C", counts)


@pytest.mark.parametrize("bc1,flag", [
    ([(12, 3), (10, 0)], True),    # one pool with 3 ALT reads, another with 10 reads and none ALT
    ([(12, 2), (10, 0)], False),   # 2 ALT reads: under the cut
    ([(12, 3), (9, 0)], False),    # 9 reads: under the depth cut
    ([(12, 3), (10, 1)], False),   # the other pool has an ALT read
])
def test_inconsistent_flag(bc1, flag):
    rows = list(score.score(["W", "P1", "P2"], [rec(100, [(20, 1)] + bc1)], "W", [], args()))
    assert ("inconsistent" in rows[0][10].split(",")) == flag


def test_af_gt_half_flag():
    rows = list(score.score(["W", "P1", "P2"], [rec(100, [(20, 1), (10, 9), (10, 9)])], "W", [], args()))
    assert "af_gt_half" in rows[0][10]


def test_witness_must_be_a_vcf_sample():
    with pytest.raises(SystemExit):
        list(score.score(["P1", "P2"], [rec(100, [(1, 0), (1, 0)])], "W", [], args()))


@pytest.fixture(scope="module")
def ours(tmp_path_factory):
    out = tmp_path_factory.mktemp("score") / "Zx.0540_P3.chr10.sites.tsv.gz"
    score.main(["--vcf", str(FIX / "crisp_vetoed.vcf"), "--witness", "W", "--controls",
                str(FIX / "B73_checks.vcf"), str(FIX / "B73_ERR3288215.vcf"), "--out", str(out)] + SETTINGS)
    with gzip.open(out, "rt") as fh:
        return {int(r["pos"]): r for r in csv.DictReader(fh, delimiter="\t")}


@pytest.fixture(scope="module")
def zealbc1():
    with open(FIX / "zealbc1_Zx.0540_P3.sites.tsv") as fh:
        return {int(r["pos"]): r for r in csv.DictReader(fh, delimiter="\t")}


def test_one_row_per_biallelic_snp(ours):
    assert len(ours) == 320   # 322 records less one indel and one multi-allelic SNP


def test_rows_zealbc1_skips_have_no_reads(ours, zealbc1):
    extra = [r for p, r in ours.items() if p not in zealbc1]
    assert extra and all(r["n"] == "0" and r["tier"] == "." for r in extra)


def test_matches_zealbc1_step4(ours, zealbc1):
    for pos, z in zealbc1.items():
        o = ours[pos]
        assert (o["n"], o["a"], o["n_pools_alt"], o["pool_counts"]) == (z["n"], z["a"], z["n_pools_alt"], z["pool_counts"])
        assert float(o["eps"]) == pytest.approx(float(z["eps"]), abs=5.1e-5)  # zealbc1 rounds to 4 decimals
        assert float(o["LLR"]) == pytest.approx(float(z["LLR"]), abs=5.1e-3)  # zealbc1 rounds to 2 decimals
        assert set(o["flags"].split(",")) & FLAGS == set(z["flags"].split(",")) & FLAGS
        assert o["tier"] == ("." if z["tier"] == "-" else z["tier"]), pos


def test_zealbc1_reference_covers_every_tier_and_flag(zealbc1):
    assert {r["tier"] for r in zealbc1.values()} == {"A", "B", "C", "ref", "-"}
    assert set().union(*(r["flags"].split(",") for r in zealbc1.values())) >= FLAGS


def mpileup_vcfs(tmp, crisp):
    """The CRISP fixture's BC1 counts as one mpileup-style VCF per pool (AD), its sites as a sites VCF, and the CRISP
    VCF with the witness's counts set to zero; only biallelic SNPs."""
    lines = [x.rstrip("\n").split("\t") for x in open(crisp) if not x.startswith("##")]
    head, recs = lines[0], [x for x in lines[1:] if score.is_snp(x[3], x[4])]
    zero = tmp / "crisp_no_witness.vcf"
    with open(zero, "w") as fh:
        fh.write("\t".join(head) + "\n")
        for x in recs:
            fh.write("\t".join(x[:9] + ["0:9:0:0,0:0,0:0,0"] + x[10:]) + "\n")
    sites = tmp / "sites.vcf"
    sites.write_text("##fileformat=VCFv4.2\n##contig=<ID=chr10>\n#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO\n"
                     + "".join(f"{x[0]}\t{x[1]}\t.\t{x[3]}\t{x[4]}\t.\t.\t.\n" for x in recs))
    pools = []
    for j, name in enumerate(head[10:], start=10):
        p = tmp / f"{name}.vcf"
        with open(p, "w") as fh:
            fh.write(f"##fileformat=VCFv4.2\n#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO\tFORMAT\t{name}\n")
            for x in recs:
                fmt, v = x[8].split(":"), x[j].split(":")
                r = sum(int(v[fmt.index(k)].split(",")[0]) for k in ("ADf", "ADr", "ADb"))
                a = sum(int(v[fmt.index(k)].split(",")[1]) for k in ("ADf", "ADr", "ADb"))
                fh.write(f"{x[0]}\t{x[1]}\t.\t{x[3]}\t{x[4]}\t.\t.\t.\tGT:AD\t0/1:{r},{a}\n")
        pools.append(str(p))
    return zero, sites, pools


def read_table(path):
    with gzip.open(path, "rt") as fh:
        return list(csv.DictReader(fh, delimiter="\t"))


def test_bc1_vcf_matches_crisp_mode(tmp_path):
    # the same counts, read from mpileup VCFs at the given sites or from CRISP with a witness without reads
    zero, sites, pools = mpileup_vcfs(tmp_path, FIX / "crisp_vetoed.vcf")
    controls = [str(FIX / "B73_checks.vcf"), str(FIX / "B73_ERR3288215.vcf")]
    score.main(["--vcf", str(zero), "--witness", "W", "--controls"] + controls + ["--out", str(tmp_path / "c.tsv.gz")] + SETTINGS)
    score.main(["--bc1-vcf"] + pools + ["--sites", str(sites), "--controls"] + controls
               + ["--out", str(tmp_path / "u.tsv.gz"), "--tier-a-vcf", str(tmp_path / "u.tier_a.vcf")] + SETTINGS)
    crisp, union = read_table(tmp_path / "c.tsv.gz"), read_table(tmp_path / "u.tsv.gz")
    assert len(union) == 320 and union == crisp
    assert {r["tier"] for r in union} >= {"A", "ref"}


def test_bc1_vcf_site_without_counts(tmp_path):
    # a site no pool VCF has a record for: no reads, tier "."
    sites = tmp_path / "sites.vcf"
    sites.write_text("#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO\nchr10\t5\t.\tA\tC\t.\t.\t.\n")
    pool = tmp_path / "P1.vcf"
    pool.write_text("#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO\tFORMAT\tP1\n")
    score.main(["--bc1-vcf", str(pool), "--sites", str(sites), "--out", str(tmp_path / "u.tsv.gz")] + SETTINGS)
    (row,) = read_table(tmp_path / "u.tsv.gz")
    assert (row["n"], row["tier"], row["pool_counts"]) == ("0", ".", "P1:0/0")


def test_tier_a_vcf(tmp_path, ours):
    out = tmp_path / "a.vcf"
    score.main(["--vcf", str(FIX / "crisp_vetoed.vcf"), "--witness", "W", "--controls", str(FIX / "B73_checks.vcf"),
                str(FIX / "B73_ERR3288215.vcf"), "--out", str(tmp_path / "s.tsv.gz"), "--tier-a-vcf", str(out)] + SETTINGS)
    lines = out.read_text().splitlines()
    # the fixture has no ##contig lines: one per chromosome of its records
    assert lines[:3] == ["##fileformat=VCFv4.2", "##contig=<ID=chr10>", "#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO"]
    assert [int(x.split("\t")[1]) for x in lines[3:]] == sorted(p for p, r in ours.items() if r["tier"] == "A")


@pytest.mark.parametrize("extra", [[], ["--vcf", "x"], ["--vcf", "x", "--witness", "W", "--bc1-vcf", "y", "--sites", "z"],
                                   ["--bc1-vcf", "y"]])
def test_input_modes_exclusive(extra):
    with pytest.raises(SystemExit):
        score.parse_args(["--out", "x"] + SETTINGS + extra)
