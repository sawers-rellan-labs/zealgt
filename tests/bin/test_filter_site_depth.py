"""Unit tests for bin/filter_site_depth.py: hand-computed expected reads and ratios on two donors.

Donor D1: lines a, b; 4 markers; count records at 100, 200, 300 (400 has no reads).
  a: 2 + 1 + 1 = 4 reads -> lambda 1;  b: 0 + 0 + 2 = 2 reads -> lambda 0.5;  E_D1 = 1.5
Donor D2: line c; 2 markers; count records at 200, 500.
  c: 3 + 1 = 4 reads -> lambda 2;  E_D2 = 2
Sites: 100: 2 / 1.5 = 1.33; 200: (1 + 0) + 3 = 4 / (1.5 + 2) = 1.14; 300: 3 / 1.5 = 2 (kept at the upper bound);
       500: 1 / 2 = 0.5 (kept at the lower bound). 400: no record, not a candidate, so dropped from D1's markers.
Line b at 300 shows '.' in AD for the ALT, counted as 0.
Run: python3 tests/bin/test_filter_site_depth.py (or pytest).
"""
import importlib.util
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("fsd", ROOT / "bin" / "filter_site_depth.py")
fsd = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fsd)

HEAD = "##fileformat=VCFv4.2\n##FORMAT=<ID=AD,Number=R,Type=Integer,Description=\"AD\">\n"


def vcf(path, samples, rows):
    """A VCF with GT:AD cells; rows = (pos, [AD per sample])."""
    cols = "#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO" + ("\tFORMAT\t" + "\t".join(samples) if samples else "")
    body = "".join(
        f"chrA\t{pos}\t.\tA\tG\t.\t.\t." + ("\tGT:AD\t" + "\t".join(f"0:{ad}" for ad in ads) if samples else "") + "\n"
        for pos, ads in rows
    )
    path.write_text(HEAD + cols + "\n" + body)
    return str(path)


def run(tmp, min_ratio=0.5, max_ratio=2.0):
    d1c = vcf(tmp / "D1.counts.vcf", ["a", "b"], [(100, ["2,0", "0,0"]), (200, ["1,0", "0,0"]), (300, ["0,1", "2,."])])
    d1m = vcf(tmp / "D1.markers.vcf", [], [(p, []) for p in (100, 200, 300, 400)])
    d2c = vcf(tmp / "D2.counts.vcf", ["c"], [(200, ["1,2"]), (500, ["0,1"])])
    d2m = vcf(tmp / "D2.markers.vcf", [], [(p, []) for p in (200, 500)])
    o1, o2 = tmp / "D1.kept.vcf", tmp / "D2.kept.vcf"
    fsd.main(["--donor", d1c, d1m, str(o1), "--donor", d2c, d2m, str(o2), "--min-ratio", str(min_ratio),
              "--max-ratio", str(max_ratio)])
    assert o1.read_text().startswith(HEAD)
    return [[f"{c[0]}:{c[1]}" for c in (r.split("\t") for r in o.read_text().splitlines()) if not c[0].startswith("#")]
            for o in (o1, o2)]


def test_site_reads():
    with tempfile.TemporaryDirectory() as t:
        p = vcf(Path(t) / "x.vcf", ["a", "b"], [(100, ["2,0", "0,0"]), (300, ["0,1", "2,."])])
        sites, per_line = fsd.site_reads(p)
    assert sites == {("chrA", 100): 2, ("chrA", 300): 3}
    assert per_line == [3, 2]


def test_ratios_kept():
    with tempfile.TemporaryDirectory() as t:
        assert run(Path(t)) == [["chrA:100", "chrA:200", "chrA:300"], ["chrA:200", "chrA:500"]]


def test_ratio_bounds():
    with tempfile.TemporaryDirectory() as t:
        assert run(Path(t), min_ratio=0.6) == [["chrA:100", "chrA:200", "chrA:300"], ["chrA:200"]]
    with tempfile.TemporaryDirectory() as t:
        assert run(Path(t), max_ratio=1.2) == [["chrA:200"], ["chrA:200", "chrA:500"]]


if __name__ == "__main__":
    for name, f in list(globals().items()):
        if name.startswith("test_"):
            f()
            print(f"ok {name}")
