#!/usr/bin/env Rscript
# The R/qtl marker grid of one chromosome and each donor's mosaic read at it (math supplement, Text S6).
#
# Grid: the union sites placed on the genetic map (nilHMM bp_to_cm, the bundled v5 map unless --map), thinned to
# markers >= --min-cm apart by the greedy sweep (sort by cM, keep the first, skip all within min-cm; exact on a line,
# Jena et al. 2018). Each donor's segments are read at the grid markers (a marker between two segments is missing).
# Per donor: an R/qtl csvr file (0/1/2, NA missing) and a VCF on the union site's REF/ALT whose GT is the ancestry
# dosage, not the line's bases (as zealhmm scripts/zeal_export_release.R).
#
# Usage: write_ancestry_grid.R --union UNION.vcf.gz --donors D1 D2 --segments D1.bed D2.bed --prefix CHR
#        --min-cm 0.1 [--map MAP.tsv]
suppressPackageStartupMessages({
  library(data.table)
  library(nilHMM)
})

# a timestamped line on stderr
log_info <- function(...) {
  message(format(Sys.time(), "%Y-%m-%d %H:%M:%S"), " INFO write_ancestry_grid: ", sprintf(...))
}

parse_args <- function(argv) {
  flags <- grep("^--", argv)
  args <- Map(function(i, j) argv[seq_len(j - i - 1L) + i], flags, c(flags[-1], length(argv) + 1))
  names(args) <- sub("^--", "", argv[flags])
  args
}

# a VCF's ## header lines and its records (CHROM, POS, REF, ALT)
read_sites <- function(path) {
  con <- gzfile(path, "rt")
  on.exit(close(con))
  lines <- readLines(con)
  meta <- lines[startsWith(lines, "##")]
  body <- lines[!startsWith(lines, "#")]
  sites <- if (length(body)) {
    fread(text = body, sep = "\t", header = FALSE, select = c(1, 2, 4, 5), colClasses = "character")
  } else {
    data.table(V1 = character(), V2 = character(), V4 = character(), V5 = character())
  }
  setnames(sites, c("chrom", "bp", "ref", "alt"))
  list(meta = meta, sites = sites[, bp := as.integer(bp)])
}

# markers at least min_cm apart: sort by cM, keep a marker iff it lies min_cm past the last one kept
thin_grid <- function(sites, min_cm) {
  sites <- sites[order(cM, bp)]
  keep <- logical(nrow(sites))
  last <- -Inf
  for (i in seq_len(nrow(sites))) {
    if (sites$cM[i] - last >= min_cm) {
      keep[i] <- TRUE
      last <- sites$cM[i]
    }
  }
  sites[keep]
}

# the state of each line at each grid marker: the segment holding the marker, NA if none
read_at_grid <- function(seg, bp) {
  lines <- sort(unique(seg$line))
  states <- vapply(lines, function(l) {
    s <- seg[line == l][order(start)]
    i <- findInterval(bp, s$start + 1L)
    ok <- i >= 1L & bp <= s$end[pmax(i, 1L)]
    ifelse(ok, s$state[pmax(i, 1L)], NA_integer_)
  }, integer(length(bp)))
  matrix(states, nrow = length(bp), dimnames = list(NULL, lines))
}

write_rqtl <- function(grid, states, path) {
  head <- c("id", "", "", colnames(states))
  rows <- cbind(grid$marker, sub("^chr", "", grid$chrom), sprintf("%.4f", grid$cM), states)
  fwrite(as.data.table(rbind(head, rows)), path, col.names = FALSE, na = "NA", quote = FALSE)
}

write_vcf <- function(grid, states, donor, meta, path) {
  gt <- c("0/0", "0/1", "1/1")[states + 1L]
  gt[is.na(gt)] <- "./."
  fixed <- c("#CHROM", "POS", "ID", "REF", "ALT", "QUAL", "FILTER", "INFO")
  header <- c(
    "##fileformat=VCFv4.2", grep("^##contig=", meta, value = TRUE),
    sprintf(paste0(
      "##FORMAT=<ID=GT,Number=1,Type=String,Description=\"Ancestry dosage on the site's alleles from RTIGER: ",
      "0/0 B73/B73, 0/1 het, 1/1 %s/%s; not the line's bases\">"
    ), donor, donor),
    paste(c(fixed, if (ncol(states)) c("FORMAT", colnames(states))), collapse = "\t")
  )
  writeLines(header, path)
  # a donor without lines: the sites only, no FORMAT column
  body <- data.table(grid$chrom, grid$bp, grid$marker, grid$ref, grid$alt, ".", ".", ".")
  if (ncol(states)) body <- cbind(body, "GT", as.data.table(matrix(gt, nrow = nrow(states))))
  fwrite(body, path, sep = "\t", col.names = FALSE, append = TRUE)
}

main <- function(argv = commandArgs(trailingOnly = TRUE)) {
  a <- parse_args(argv)
  stopifnot(length(a$donors) == length(a$segments))

  union <- read_sites(a$union)
  map <- if (is.null(a$map)) load_map("v5") else fread(a$map)
  sites <- union$sites
  sites[, cM := bp_to_cm(map)(sub("^chr", "", chrom), bp)]
  grid <- thin_grid(sites, as.numeric(a$`min-cm`))
  grid[, marker := sprintf("%s_%d", chrom, bp)]
  log_info("%d union sites -> %d grid markers >= %s cM apart", nrow(sites), nrow(grid), a$`min-cm`)
  fwrite(grid[, .(marker, chrom, bp, cM)], sprintf("%s.grid.tsv", a$prefix), sep = "\t")

  for (k in seq_along(a$donors)) {
    donor <- a$donors[k]
    seg <- fread(a$segments[k], sep = "\t", colClasses = list(character = c("#chrom", "line")))
    setnames(seg, "#chrom", "chrom")
    states <- read_at_grid(seg, grid$bp)
    write_rqtl(grid, states, sprintf("%s.%s.rqtl.csv", donor, a$prefix))
    write_vcf(grid, states, donor, union$meta, sprintf("%s.%s.ancestry.vcf", donor, a$prefix))
    log_info("%s: %d lines, %d of %d calls missing", donor, ncol(states), sum(is.na(states)), length(states))
  }
}

if (sys.nframe() == 0L) main()
