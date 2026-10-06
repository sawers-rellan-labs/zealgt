#!/usr/bin/env Rscript
# Each line's ancestry mosaic on one chromosome with nilHMM's RTIGER (math supplement, Text S6, "Ancestry inference").
#
# Markers: the donor's tier-A sites; per line, n_ref and n_alt are the bcftools mpileup AD of the site's REF and of
# the donor's ALT allele. Rigidity r = max(1, round(fraction x tier-A sites)); lines with fewer than 2r covered
# markers (>= 1 read) are dropped first, since RTIGER stops on them. States: 0 B73/B73, 1 het, 2 donor/donor.
#
# Usage: call_ancestry.R --tier-a TIER_A.vcf --counts LINE.vcf.gz [...] --rigidity-fraction F
#        --segments OUT.bed --dropped OUT.tsv [--seed S]
suppressPackageStartupMessages({
  library(data.table)
  library(nilHMM)
})

# a timestamped line on stderr
log_info <- function(...) {
  message(format(Sys.time(), "%Y-%m-%d %H:%M:%S"), " INFO call_ancestry: ", sprintf(...))
}

parse_args <- function(argv) {
  flags <- grep("^--", argv)
  args <- Map(function(i, j) argv[seq_len(j - i - 1L) + i], flags, c(flags[-1], length(argv) + 1))
  names(args) <- sub("^--", "", argv[flags])
  args
}

# a VCF's records as a data.table with the #CHROM header's column names
read_vcf <- function(path) {
  con <- gzfile(path, "rt")
  on.exit(close(con))
  lines <- readLines(con)
  body <- lines[!startsWith(lines, "##")]
  cols <- sub("^#", "", strsplit(body[1], "\t", fixed = TRUE)[[1]])
  if (length(body) < 2L) {
    return(setnames(as.data.table(rep(list(character()), length(cols))), cols)[, POS := integer()])
  }
  v <- fread(text = body[-1], sep = "\t", header = FALSE, col.names = cols, colClasses = "character")
  v[, POS := as.integer(POS)]
}

# one line's REF and donor-ALT read counts at the tier-A sites (0 where mpileup wrote no record)
read_line_counts <- function(path, sites) {
  v <- read_vcf(path)
  name <- tail(names(v), 1L)
  if (!nrow(v)) {
    return(sites[, .(name = name, pos = POS, n_ref = 0L, n_alt = 0L)])
  }
  # AD's place in FORMAT per record: bcftools call writes GT:AD where no ALT read is seen, GT:PL:AD elsewhere
  ad_at <- vapply(strsplit(v$FORMAT, ":", fixed = TRUE), function(f) match("AD", f), 0L)
  cells <- strsplit(v[[name]], ":", fixed = TRUE)
  v[, ad := vapply(seq_along(cells), function(i) cells[[i]][ad_at[i]], "")]
  m <- v[sites, on = .(CHROM, POS), nomatch = NA]
  alleles <- strsplit(paste(m$REF, m$ALT, sep = ","), ",", fixed = TRUE)
  depths <- lapply(strsplit(m$ad, ",", fixed = TRUE), function(x) suppressWarnings(as.integer(x)))
  count_of <- function(allele, i) {
    k <- match(allele, alleles[[i]])
    d <- if (is.na(k)) NA_integer_ else depths[[i]][k]
    if (is.na(d)) 0L else d
  }
  data.table(
    name = name, pos = m$POS,
    n_ref = vapply(seq_len(nrow(m)), function(i) count_of(m$i.REF[i], i), 0L),
    n_alt = vapply(seq_len(nrow(m)), function(i) count_of(m$i.ALT[i], i), 0L)
  )
}

main <- function(argv = commandArgs(trailingOnly = TRUE)) {
  a <- parse_args(argv)
  seed <- as.integer(if (is.null(a$seed)) 1L else a$seed)

  sites <- read_vcf(a$`tier-a`)[, .(CHROM, POS, REF, ALT)]
  rigidity <- max(1L, as.integer(round(as.numeric(a$`rigidity-fraction`) * nrow(sites))))
  log_info("%d tier-A sites; rigidity %d, lines need >= %d covered markers", nrow(sites), rigidity, 2L * rigidity)

  counts <- rbindlist(lapply(a$counts, read_line_counts, sites = sites))
  covered <- counts[, .(covered_markers = sum(n_ref + n_alt >= 1L)), by = .(line = name)]
  covered[, cut := 2L * rigidity]
  dropped <- covered[covered_markers < cut]
  fwrite(dropped[order(line)], a$dropped, sep = "\t")
  kept <- counts[!name %in% dropped$line]
  log_info("%d lines counted, %d dropped under the cut, %d to RTIGER", nrow(covered), nrow(dropped), uniqueN(kept$name))

  bed <- data.table(chrom = character(), start = integer(), end = integer(), line = character(), state = integer())
  if (nrow(kept)) {
    chrom <- sites$CHROM[1]
    # one thread: nilHMM 0.3.1 rtiger stops on "C stack usage too close to the limit" with threads > 1 (nilhmm#31)
    log_info("RTIGER on %d lines x %d markers", uniqueN(kept$name), nrow(sites))
    seg <- as.data.table(call_ancestry(
      kept[, .(name, chr = 1L, pos, n_ref, n_alt)],
      caller = "rtiger", rigidity = rigidity, threads = 1L, seed = seed
    ))
    bed <- seg[, .(chrom = chrom, start = start_bp - 1L, end = end_bp, line = name, state)]
    log_info("%d segments", nrow(bed))
  }
  writeLines("#chrom\tstart\tend\tline\tstate", a$segments)
  fwrite(bed[order(line, start)], a$segments, sep = "\t", append = TRUE)
}

if (sys.nframe() == 0L) main()
