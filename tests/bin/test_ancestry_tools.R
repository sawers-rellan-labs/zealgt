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

write_sites_vcf <- function(sites, path) {
  writeLines(c(
    "##fileformat=VCFv4.2", "##contig=<ID=chr10,length=152435371>",
    "#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO"
  ), path)
  fwrite(sites[, .(CHROM = "chr10", POS = pos, ID = ".", REF = ref, ALT = alt, ".", ".", ".")], path,
    sep = "\t", col.names = FALSE, append = TRUE
  )
}

# a line's counts as bcftools mpileup | call -m -A writes them: no record without reads; without ALT reads ALT '.',
# FORMAT GT:AD and one depth; with ALT reads GT:PL:AD, the donor ALT first or second among the ALT alleles
write_counts_vcf <- function(obs, sites, line, path) {
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
    "##fileformat=VCFv4.2", "##contig=<ID=chr10,length=152435371>",
    "##FORMAT=<ID=AD,Number=R,Type=Integer,Description=\"Allelic depths\">",
    paste0("#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO\tFORMAT\t", name)
  ), path)
  fwrite(o[, .("chr10", pos, ".", ref, alt_field, ".", ".", ".", fmt, cell)], path,
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
write_sites_vcf(sites, file.path(dir, "tier_a.vcf"))
counts <- vapply(lines, function(l) {
  p <- file.path(dir, paste0(l, ".vcf"))
  write_counts_vcf(obs, sites, l, p)
  system2("gzip", p)
  paste0(p, ".gz")
}, "")
rigidity <- max(1L, round(0.005 * nrow(sites)))
res <- run_tool("call_ancestry.R", c(
  "--tier-a", file.path(dir, "tier_a.vcf"), "--counts", counts, "--rigidity-fraction", "0.005",
  "--segments", file.path(dir, "D.bed"), "--dropped", file.path(dir, "D.dropped.tsv")
), dir)

test_that("call_ancestry.R runs and logs with timestamps", {
  expect_equal(res$status, 0L, info = paste(res$log, collapse = "\n"))
  expect_match(res$log[1], "^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9:]{8} INFO call_ancestry: ")
})

test_that("each line's REF and donor-ALT counts are read back exactly, whatever the record's FORMAT", {
  tool <- new.env()
  sys.source(file.path(root, "bin", "call_ancestry.R"), envir = tool)
  tier <- tool$read_vcf(file.path(dir, "tier_a.vcf"))[, .(CHROM, POS, REF, ALT)]
  for (l in lines[2:4]) {
    got <- tool$read_line_counts(counts[[l]], tier)
    want <- obs[name == l][order(pos)]
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
  data.table("chrA", c(999L, 1249L, 999L), c(1000L, 1500L, 1500L), c("L1", "L1", "L2"), c(0L, 2L, 1L)),
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
