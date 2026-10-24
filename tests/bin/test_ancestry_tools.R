# Unit tests for bin/call_ancestry.R and bin/write_ancestry_grid.R, each run as a command in the module's container.
#
# Run: Rscript -e 'testthat::test_file("tests/bin/test_ancestry_tools.R")' (laptop R with
# nilHMM, simcross, qtl, data.table, testthat; bcftools and Docker on PATH). Truth: nilHMM's simulate_nil, BC2S2.
suppressPackageStartupMessages({
  library(data.table)
  library(testthat)
})

# testthat runs a test file from its own folder, tests/bin
root <- normalizePath(file.path("..", ".."))
image <- sub(".*container '([^']+)'.*", "\\1", grep("container '", readLines(
  file.path(root, "modules", "local", "call_ancestry", "main.nf")
), value = TRUE))

# a tool from bin/ run in the module's container, in directory `dir`
run_tool <- function(tool, args, dir) {
  out <- system2("docker", c(
    "run", "--rm", "--platform", "linux/amd64", "-v", paste0(root, ":", root), "-v", paste0(dir, ":", dir),
    "-w", dir, image, "Rscript", file.path(root, "bin", tool), args
  ), stdout = TRUE, stderr = TRUE)
  status <- attr(out, "status")
  list(status = if (is.null(status)) 0L else status, log = out)
}

write_sites_vcf <- function(sites, path, chrom = "chr10") {
  writeLines(c(
    "##fileformat=VCFv4.2", sprintf("##contig=<ID=%s,length=152435371>", chrom),
    "#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO"
  ), path)
  fwrite(sites[, .(CHROM = chrom, POS = pos, ID = ".", REF = ref, ALT = alt, ".", ".", ".")], path,
    sep = "\t", col.names = FALSE, append = TRUE
  )
}

# a line's counts as bcftools mpileup | call -m -A writes them: no record without reads; without ALT reads ALT '.',
# FORMAT GT:AD and one depth; with ALT reads GT:PL:AD, the donor ALT first or second among the ALT alleles
write_counts_vcf <- function(obs, sites, line, path, chrom = "chr10") {
  name <- line
  o <- obs[obs$name == line][sites, on = "pos"][n_ref + n_alt > 0]
  swap <- o$pos %% 3L == 0L
  o[, alt_field := fifelse(n_alt == 0L, ".", fifelse(swap, paste0("T,", alt), alt))]
  o[, fmt := fifelse(n_alt == 0L, "GT:AD", "GT:PL:AD")]
  o[, cell := fifelse(
    n_alt == 0L, sprintf("0/0:%d", n_ref),
    fifelse(swap, sprintf("0/1:0,3,30,9,40,50:%d,0,%d", n_ref, n_alt), sprintf("0/1:30,0,30:%d,%d", n_ref, n_alt))
  )]
  writeLines(c(
    "##fileformat=VCFv4.2", sprintf("##contig=<ID=%s,length=152435371>", chrom),
    "##FORMAT=<ID=AD,Number=R,Type=Integer,Description=\"Allelic depths\">",
    paste0("#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO\tFORMAT\t", name)
  ), path)
  fwrite(o[, .(chrom, pos, ".", ref, alt_field, ".", ".", ".", fmt, cell)], path,
    sep = "\t", col.names = FALSE, append = TRUE
  )
}

# all lines in one VCF, as bcftools mpileup | call -m -A writes a donor's lines: a record where any line has reads;
# ALT '.' and GT:AD where no line has ALT reads, else GT:PL:AD; a line without reads at a record has AD 0
write_multi_counts_vcf <- function(obs, sites, path, chrom = "chr10") {
  o <- obs[sites, on = "pos"]
  o[, `:=`(reads = sum(n_ref + n_alt), any_alt = sum(n_alt) > 0L), by = pos]
  o <- o[reads > 0L]
  o[, swap := pos %% 3L == 0L]
  o[, cell := fifelse(
    !any_alt, sprintf("0/0:%d", n_ref),
    fifelse(swap, sprintf("0/1:0,3,30,9,40,50:%d,0,%d", n_ref, n_alt), sprintf("0/1:30,0,30:%d,%d", n_ref, n_alt))
  )]
  w <- dcast(o, pos + ref + alt + any_alt + swap ~ name, value.var = "cell")
  names <- setdiff(names(w), c("pos", "ref", "alt", "any_alt", "swap"))
  w[, `:=`(
    alt_field = fifelse(!any_alt, ".", fifelse(swap, paste0("T,", alt), alt)),
    fmt = fifelse(!any_alt, "GT:AD", "GT:PL:AD")
  )]
  writeLines(c(
    "##fileformat=VCFv4.2", sprintf("##contig=<ID=%s,length=152435371>", chrom),
    "##FORMAT=<ID=AD,Number=R,Type=Integer,Description=\"Allelic depths\">",
    paste0("#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO\tFORMAT\t", paste(names, collapse = "\t"))
  ), path)
  fwrite(cbind(w[, .(chrom, pos, ".", ref, alt_field, ".", ".", ".", fmt)], w[, ..names]), path,
    sep = "\t", col.names = FALSE, append = TRUE
  )
}

state_at <- function(seg, pos) {
  s <- seg[order(start)]
  i <- findInterval(pos, s$start + 1L)
  ifelse(i >= 1L & pos <= s$end[pmax(i, 1L)], s$state[pmax(i, 1L)], NA_integer_)
}

dir <- normalizePath(tempfile("ancestry_"), mustWork = FALSE)
dir.create(dir)

set.seed(7)
truth <- as.data.table(nilHMM::simulate_nil("BC2S2", n = 12, chr = 10L, n_markers = 4000L, seed = 7))
truth <- truth[!duplicated(truth[, .(name, pos)])]
obs <- as.data.table(nilHMM::simulate_counts(truth, depth = 2, error = 0.01, seed = 7))
sites <- unique(truth[, .(pos)])[, `:=`(ref = "A", alt = "G")]
lines <- sort(unique(truth$name))
# a line with reads at 10 markers only, under the cut 2r = 2 x round(0.005 x sites)
obs[name == lines[1] & !pos %in% sites$pos[seq(1, by = 7, length.out = 10)], `:=`(n_ref = 0L, n_alt = 0L)]
write_sites_vcf(sites, file.path(dir, "markers.vcf"))
counts <- vapply(lines, function(l) {
  p <- file.path(dir, paste0(l, ".vcf"))
  write_counts_vcf(obs, sites, l, p)
  system2("gzip", p)
  paste0(p, ".gz")
}, "")
# the rigidity call_ancestry.R derives from a 1 Mb window: the median line's covered markers per Mb of the markers' span
r_of <- function(o, s, mb) {
  span_mb <- sum(s[, diff(range(pos)), by = chrom]$V1) / 1e6
  per_mb <- median(o[, .(n = sum(n_ref + n_alt > 0L)), by = name]$n) / span_mb
  max(1L, as.integer(round(mb * per_mb)))
}
rigidity <- r_of(obs, sites[, .(chrom = "chr10", pos)], 1)
res <- run_tool("call_ancestry.R", c(
  "--markers", file.path(dir, "markers.vcf"), "--counts", counts, "--rigidity-mb", "1",
  "--segments", file.path(dir, "D.bed"), "--dropped", file.path(dir, "D.dropped.tsv"),
  "--line-checks", file.path(dir, "D.line_checks.tsv"), "--markers-per-chrom", file.path(dir, "D.per_chrom.tsv")
), dir)

test_that("call_ancestry.R runs and logs with timestamps", {
  expect_equal(res$status, 0L, info = paste(res$log, collapse = "\n"))
  expect_match(res$log[1], "^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9:]{8} INFO call_ancestry: ")
})

test_that("each line's REF and donor-ALT counts at its records are read back exactly, whatever the record's FORMAT", {
  tool <- new.env()
  sys.source(file.path(root, "bin", "call_ancestry.R"), envir = tool)
  markers <- tool$read_vcf(file.path(dir, "markers.vcf"))[, .(CHROM, POS, REF, ALT)]
  for (l in lines[2:4]) {
    got <- tool$read_counts(counts[[l]], markers)$counts
    want <- obs[name == l & n_ref + n_alt > 0L][order(pos)]
    expect_equal(got[order(pos)]$n_ref, want$n_ref)
    expect_equal(got[order(pos)]$n_alt, want$n_alt)
  }
})

test_that("the line under 2r covered markers is dropped and listed", {
  dropped <- fread(file.path(dir, "D.dropped.tsv"))
  expect_equal(dropped$line, lines[1])
  expect_equal(dropped$covered_markers, 10L)
  expect_equal(dropped$cut, 2L * rigidity)
})

test_that("the mosaic matches the simulated truth", {
  seg <- fread(file.path(dir, "D.bed"))
  setnames(seg, "#chrom", "chrom")
  expect_setequal(unique(seg$line), lines[-1])
  expect_true(all(seg$chrom == "chr10") && all(seg$state %in% 0:2) && all(seg$start < seg$end))
  called <- truth[name != lines[1]][, .(called = state_at(seg[line == .BY$name], pos), state), by = name]
  expect_gt(mean(called$called == called$state, na.rm = TRUE), 0.97)
  expect_lt(mean(is.na(called$called)), 0.05)
})

test_that("the line checks list every called line, and their reads are the counts inside its segments", {
  checks <- fread(file.path(dir, "D.line_checks.tsv"), na.strings = ".")
  expect_setequal(checks$line, lines[-1])
  total <- obs[name != lines[1], .(reads = sum(n_ref + n_alt)), by = name]
  inside <- checks[, .(line, reads = ref_reads + het_reads + alt_reads)][total, on = .(line = name)]
  # segments run from each line's first marker to its last, so every read falls inside one
  expect_equal(inside$reads, inside$i.reads)
})

# the same lines in one multi-sample count VCF, as COUNT_LINES writes a donor's lines per region
write_multi_counts_vcf(obs, sites, file.path(dir, "D.chr10.counts.vcf"))
system2("gzip", file.path(dir, "D.chr10.counts.vcf"))
res_multi <- run_tool("call_ancestry.R", c(
  "--markers", file.path(dir, "markers.vcf"), "--counts", file.path(dir, "D.chr10.counts.vcf.gz"), "--rigidity-mb", "1",
  "--segments", file.path(dir, "M.bed"), "--dropped", file.path(dir, "M.dropped.tsv"),
  "--line-checks", file.path(dir, "M.line_checks.tsv"), "--markers-per-chrom", file.path(dir, "M.per_chrom.tsv")
), dir)

test_that("one multi-sample count VCF gives the segments, dropped lines and line checks of one file per line", {
  expect_equal(res_multi$status, 0L, info = paste(res_multi$log, collapse = "\n"))
  for (f in c("bed", "dropped.tsv", "line_checks.tsv")) {
    expect_identical(readLines(file.path(dir, paste0("M.", f))), readLines(file.path(dir, paste0("D.", f))), info = f)
  }
})

# two chromosomes in one fit, as --ancestry_fit genome: chr9 is a second simulation, each chromosome its own markers
# file and count files; lines[1] covered at 10 markers on chr9 only, so dropped on its least covered chromosome
truth9 <- as.data.table(nilHMM::simulate_nil("BC2S2", n = 12, chr = 10L, n_markers = 4000L, seed = 9))
truth9 <- truth9[!duplicated(truth9[, .(name, pos)])]
obs9 <- as.data.table(nilHMM::simulate_counts(truth9, depth = 2, error = 0.01, seed = 9))
sites9 <- unique(truth9[, .(pos)])[, `:=`(ref = "A", alt = "G")]
obs10 <- as.data.table(nilHMM::simulate_counts(truth, depth = 2, error = 0.01, seed = 7))
obs9[name == lines[1] & !pos %in% sites9$pos[seq(1, by = 7, length.out = 10)], `:=`(n_ref = 0L, n_alt = 0L)]
write_sites_vcf(sites9, file.path(dir, "markers9.vcf"), "chr9")
counts9 <- vapply(lines, function(l) {
  p <- file.path(dir, paste0(l, ".chr9.vcf"))
  write_counts_vcf(obs9, sites9, l, p, "chr9")
  system2("gzip", p)
  paste0(p, ".gz")
}, "")
counts10 <- vapply(lines, function(l) {
  p <- file.path(dir, paste0(l, ".chr10.full.vcf"))
  write_counts_vcf(obs10, sites, l, p)
  system2("gzip", p)
  paste0(p, ".gz")
}, "")
res2 <- run_tool("call_ancestry.R", c(
  "--markers", file.path(dir, "markers9.vcf"), file.path(dir, "markers.vcf"), "--counts", counts9, counts10,
  "--rigidity-mb", "1", "--segments", file.path(dir, "G.bed"), "--dropped", file.path(dir, "G.dropped.tsv"),
  "--line-checks", file.path(dir, "G.line_checks.tsv"), "--markers-per-chrom", file.path(dir, "G.per_chrom.tsv")
), dir)

test_that("two chromosomes: one fit, rigidity from both spans, the cut on the least covered chromosome", {
  expect_equal(res2$status, 0L, info = paste(res2$log, collapse = "\n"))
  r2 <- r_of(rbind(obs9, obs10), rbind(sites9[, .(chrom = "chr9", pos)], sites[, .(chrom = "chr10", pos)]), 1)
  expect_match(paste(res2$log, collapse = "\n"), sprintf("on 2 chromosome\\(s\\).*rigidity %d \\(1 Mb\\)", r2))
  dropped <- fread(file.path(dir, "G.dropped.tsv"))
  expect_equal(dropped$line, lines[1])
  # its covered markers on chr9, the least covered chromosome (the 10 kept markers, less those simulated without reads)
  expect_equal(dropped$covered_markers, obs9[name == lines[1], sum(n_ref + n_alt > 0L)])
})

test_that("two chromosomes: each chromosome's mosaic matches its truth", {
  seg <- fread(file.path(dir, "G.bed"))
  setnames(seg, "#chrom", "chrom")
  expect_setequal(unique(seg$chrom), c("chr9", "chr10"))
  # chromosomes in the markers' order within each line
  expect_true(all(seg[, all(diff(match(chrom, c("chr9", "chr10"))) >= 0), by = line]$V1))
  for (k in list(list("chr9", truth9), list("chr10", truth))) {
    s <- seg[chrom == k[[1]]]
    called <- k[[2]][name != lines[1]][, .(called = state_at(s[line == .BY$name], pos), state), by = name]
    expect_gt(mean(called$called == called$state, na.rm = TRUE), 0.97)
  }
})

test_that("two chromosomes: a line's donor segments are counted per chromosome", {
  tool <- new.env()
  sys.source(file.path(root, "bin", "call_ancestry.R"), envir = tool)
  # HET at the end of chr9 and at the start of chr10: two segments, not one run across the chromosomes
  bed <- data.table(
    chrom = c("chr9", "chr9", "chr10", "chr10"), start = c(0L, 100L, 0L, 100L), end = c(100L, 200L, 100L, 200L),
    line = "L1", state = c(0L, 1L, 1L, 0L)
  )
  counts <- data.table(
    name = "L1", chrom = c("chr9", "chr10"), pos = c(150L, 50L), n_ref = c(5L, 5L), n_alt = c(5L, 5L)
  )
  got <- tool$check_lines(bed, counts)
  expect_equal(got$n_donor_segments, 2L)
  expect_equal(got$donor_bp, 200L)
  expect_equal(got$het_reads, 20L)
})

test_that("line checks on a hand-made pair of lines", {
  tool <- new.env()
  sys.source(file.path(root, "bin", "call_ancestry.R"), envir = tool)
  # L1: REF 0-100, HET 100-200, ALT 200-300, REF 300-400, HET 400-500: two donor segments, 300 bp
  # L2: REF over all: no donor segment
  bed <- data.table(
    chrom = "chr10", start = c(0L, 100L, 200L, 300L, 400L, 0L), end = c(100L, 200L, 300L, 400L, 500L, 500L),
    line = c(rep("L1", 5), "L2"), state = c(0L, 1L, 2L, 0L, 1L, 0L)
  )
  # markers at 50 (REF), 150 (HET), 250 (ALT), 450 (HET) and 100 (the REF segment's end, BED start < pos <= end)
  counts <- data.table(
    name = c(rep("L1", 5), rep("L2", 2)), chrom = "chr10", pos = c(50L, 100L, 150L, 250L, 450L, 50L, 450L),
    n_ref = c(9L, 1L, 3L, 1L, 1L, 10L, 4L), n_alt = c(1L, 0L, 3L, 9L, 3L, 0L, 0L)
  )
  got <- tool$check_lines(bed, counts)
  expect_equal(got$line, c("L1", "L2"))
  expect_equal(got$n_donor_segments, c(2L, 0L))
  expect_equal(got$donor_bp, c(300L, 0L))
  expect_equal(got$ref_reads, c(11L, 14L))
  expect_equal(got$ref_alt_pct, c(9.1, 0))
  expect_equal(got$het_reads, c(10L, 0L))
  expect_equal(got$het_alt_pct, c(60, NA))
  expect_equal(got$alt_reads, c(10L, 0L))
  expect_equal(got$alt_alt_pct, c(90, NA))
})

test_that("the two donor views keep exactly the sites called ALT for the donor", {
  bcf_image <- sub(".*: '([^']+)'.*", "\\1", grep("community.wave", readLines(
    file.path(root, "modules", "nf-core", "bcftools", "view", "main.nf")
  ), value = TRUE))
  v <- file.path(dir, "donor_alleles.vcf")
  writeLines(c(
    "##fileformat=VCFv4.2", "##contig=<ID=chr10,length=152435371>",
    "##FORMAT=<ID=GT,Number=1,Type=String,Description=\"Genotype\">",
    "#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO\tFORMAT\tX\tY\tZ",
    "chr10\t100\t.\tA\tG\t.\t.\t.\tGT\t1\t0\t.",
    "chr10\t200\t.\tC\tT\t.\t.\t.\tGT\t0\t1\t1",
    "chr10\t300\t.\tG\tA\t.\t.\t.\tGT\t.\t1\t0",
    "chr10\t400\t.\tT\tC\t.\t.\t.\tGT\t1\t1\t1"
  ), v)
  # the commands DONOR_SUBSET and DONOR_ALT_SITES run (conf/modules.config)
  sites_of <- function(donor) {
    out <- system2("docker", c(
      "run", "--rm", "--platform", "linux/amd64", "-v", paste0(dir, ":", dir), "-w", dir, bcf_image, "bash", "-c",
      shQuote(sprintf(
        "bcftools view -s %s -Oz -o %s.col.vcf.gz %s && bcftools view -i 'GT=\"1\"' -G -Ov %s.col.vcf.gz",
        donor, donor, v, donor
      ))
    ), stdout = TRUE, stderr = TRUE)
    as.integer(sapply(strsplit(grep("^chr10", out, value = TRUE), "\t"), `[`, 2))
  }
  expect_equal(sites_of("X"), c(100L, 400L))
  expect_equal(sites_of("Y"), c(200L, 300L, 400L))
  expect_equal(sites_of("Z"), c(200L, 400L))
})

test_that("nilHMM's RTIGER stops on a line under 2r covered markers", {
  short <- file.path(dir, "short.R")
  writeLines(c(
    "d <- data.frame(name = 'L', chr = 1L, pos = 1:5 * 1000L, n_ref = 3L, n_alt = 0L)",
    "nilHMM::call_ancestry(d, caller = 'rtiger', rigidity = 3L)"
  ), short)
  out <- suppressWarnings(system2("docker", c(
    "run", "--rm", "--platform", "linux/amd64", "-v", paste0(dir, ":", dir), image, "Rscript", short
  ), stdout = TRUE, stderr = TRUE))
  expect_false(is.null(attr(out, "status")))
  expect_match(paste(out, collapse = "\n"), "below 2\\*rigidity = 6 covered markers")
})

# grid: union sites on a hand-made map for chrA (1 cM per 1000 bp), two donors' hand-made segments
# no markers: a markers VCF without records and its lines' count VCF without records, as COUNT_LINES writes it
write_sites_vcf(sites[0], file.path(dir, "markers0.vcf"))
writeLines(c(
  "##fileformat=VCFv4.2", "##contig=<ID=chr10,length=152435371>",
  "##FORMAT=<ID=AD,Number=R,Type=Integer,Description=\"Allelic depths\">",
  paste0("#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO\tFORMAT\t", paste(lines, collapse = "\t"))
), file.path(dir, "Z.chr10.counts.vcf"))
system2("gzip", file.path(dir, "Z.chr10.counts.vcf"))
res_zero <- run_tool("call_ancestry.R", c(
  "--markers", file.path(dir, "markers0.vcf"), "--counts", file.path(dir, "Z.chr10.counts.vcf.gz"),
  "--regions", "chr10", "--rigidity-mb", "1", "--segments", file.path(dir, "Z.bed"),
  "--dropped", file.path(dir, "Z.dropped.tsv"), "--line-checks", file.path(dir, "Z.line_checks.tsv"),
  "--markers-per-chrom", file.path(dir, "Z.per_chrom.tsv")
), dir)

test_that("no markers: no error, no RTIGER call, header-only outputs, 0 markers on the chromosome", {
  expect_equal(res_zero$status, 0L, info = paste(res_zero$log, collapse = "\n"))
  expect_false(any(grepl("RTIGER on", res_zero$log)))
  expect_match(paste(res_zero$log, collapse = "\n"), "chr10: 0 markers")
  expect_equal(readLines(file.path(dir, "Z.bed")), "#chrom\tstart\tend\tline\tstate")
  expect_equal(nrow(fread(file.path(dir, "Z.dropped.tsv"))), 0L)
  per_chrom <- fread(file.path(dir, "Z.per_chrom.tsv"))
  expect_equal(per_chrom$chrom, "chr10")
  expect_equal(per_chrom$markers, 0L)
})

# a genome fit with a chromosome without markers: chr9's markers VCF without records, chr10 as before
write_sites_vcf(sites[0], file.path(dir, "markers9_0.vcf"), chrom = "chr9")
res_gap <- run_tool("call_ancestry.R", c(
  "--markers", file.path(dir, "markers9_0.vcf"), file.path(dir, "markers.vcf"), "--counts", counts,
  "--regions", "chr9", "chr10", "--rigidity-mb", "1", "--segments", file.path(dir, "Y.bed"),
  "--dropped", file.path(dir, "Y.dropped.tsv"), "--line-checks", file.path(dir, "Y.line_checks.tsv"),
  "--markers-per-chrom", file.path(dir, "Y.per_chrom.tsv")
), dir)

test_that("a chromosome without markers in a genome fit: 0 markers there, the other chromosome called as alone", {
  expect_equal(res_gap$status, 0L, info = paste(res_gap$log, collapse = "\n"))
  per_chrom <- fread(file.path(dir, "Y.per_chrom.tsv"))
  expect_equal(per_chrom$chrom, c("chr9", "chr10"))
  expect_equal(per_chrom$markers, c(0L, nrow(sites)))
  expect_equal(fread(file.path(dir, "Y.dropped.tsv"))$line, fread(file.path(dir, "D.dropped.tsv"))$line)
  expect_equal(fread(file.path(dir, "Y.bed")), fread(file.path(dir, "D.bed")))
})

test_that("markers per chromosome: the markers and the median line's covered markers", {
  per_chrom <- fread(file.path(dir, "G.per_chrom.tsv"))
  expect_equal(per_chrom$chrom, c("chr9", "chr10"))
  expect_equal(per_chrom$markers, c(nrow(sites9), nrow(sites)))
  expect_equal(per_chrom$median_line_covered[2], median(obs10[, .(n = sum(n_ref + n_alt > 0L)), by = name]$n))
})

union <- data.table(pos = c(1000L, 1050L, 1100L, 1120L, 1250L, 1300L, 1500L), ref = "C", alt = "T")
writeLines(
  c("##fileformat=VCFv4.2", "##contig=<ID=chrA,length=5000>", "#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO"),
  file.path(dir, "union.vcf")
)
fwrite(union[, .("chrA", pos, ".", ref, alt, ".", ".", ".")], file.path(dir, "union.vcf"),
  sep = "\t", col.names = FALSE, append = TRUE
)
fwrite(data.table(chr = "A", bp = c(0L, 5000L), cm = c(0, 5)), file.path(dir, "map.tsv"), sep = "\t")
bed <- function(rows, path) {
  writeLines("#chrom\tstart\tend\tline\tstate", path)
  fwrite(rows, path, sep = "\t", col.names = FALSE, append = TRUE)
}
# L1: 0 at 1000, 2 over 1250-1500; the grid marker 1100 lies between the two. L2: 1 over all.
bed(
  # chrB's segments (a genome-wide fit) overlap chrA's positions and must not be read at chrA's grid
  data.table(
    c("chrA", "chrA", "chrA", "chrB", "chrB"), c(999L, 1249L, 999L, 0L, 0L), c(1000L, 1500L, 1500L, 5000L, 5000L),
    c("L1", "L1", "L2", "L1", "L2"), c(0L, 2L, 1L, 1L, 2L)
  ),
  file.path(dir, "X.bed")
)
bed(data.table(character(), integer(), integer(), character(), integer()), file.path(dir, "Y.bed"))
res_grid <- run_tool("write_ancestry_grid.R", c(
  "--union", file.path(dir, "union.vcf"), "--donors", "X", "Y", "--segments", file.path(dir, "X.bed"),
  file.path(dir, "Y.bed"), "--prefix", "chrA", "--min-cm", "0.1", "--map", file.path(dir, "map.tsv")
), dir)

test_that("write_ancestry_grid.R runs", {
  expect_equal(res_grid$status, 0L, info = paste(res_grid$log, collapse = "\n"))
})

test_that("the grid keeps markers >= 0.1 cM apart, the greedy sweep", {
  grid <- fread(file.path(dir, "chrA.grid.tsv"))
  # cM 1.00 kept, 1.05 skipped, 1.10 kept, 1.12 skipped, 1.25 kept, 1.30 skipped, 1.50 kept
  expect_equal(grid$bp, c(1000L, 1100L, 1250L, 1500L))
  expect_equal(grid$marker, sprintf("chrA_%d", grid$bp))
  expect_equal(grid$cM, c(1, 1.1, 1.25, 1.5), tolerance = 1e-6)
})

test_that("the R/qtl file reads back with read.cross, BC2S2", {
  cross <- qtl::read.cross(
    format = "csvr", file = file.path(dir, "X.chrA.rqtl.csv"), genotypes = c("0", "1", "2"),
    na.strings = "NA", crosstype = "bcsft", BC.gen = 2, F.gen = 2, estimate.map = FALSE
  )
  expect_equal(qtl::nind(cross), 2L)
  expect_equal(qtl::totmar(cross), 4L)
  # R/qtl codes AA, AB, BB as 1, 2, 3; L1: 0 at 1000, missing at 1100 (between segments), 2 at 1250 and 1500
  expect_equal(unname(qtl::pull.geno(cross)[1, ]), c(1L, NA, 3L, 3L))
  expect_equal(unname(qtl::pull.geno(cross)[2, ]), c(2L, 2L, 2L, 2L))
})

test_that("the VCF holds the ancestry dosage on the union alleles and reads with bcftools", {
  vcf <- file.path(dir, "X.chrA.ancestry.vcf")
  q <- system2("bcftools", c("query", "-f", "'%POS %REF %ALT [%GT ]\\n'", vcf), stdout = TRUE)
  expect_equal(q, c("1000 C T 0/0 0/1 ", "1100 C T ./. 0/1 ", "1250 C T 1/1 0/1 ", "1500 C T 1/1 0/1 "))
  expect_match(paste(readLines(vcf), collapse = "\n"), "not the line's bases")
  # a donor without lines: the markers, no samples
  y <- system2("bcftools", c("query", "-l", file.path(dir, "Y.chrA.ancestry.vcf")), stdout = TRUE)
  expect_length(y, 0L)
  y_pos <- system2("bcftools", c("query", "-f", "'%POS\\n'", file.path(dir, "Y.chrA.ancestry.vcf")), stdout = TRUE)
  expect_length(y_pos, 4L)
})
