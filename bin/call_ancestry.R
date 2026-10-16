#!/usr/bin/env Rscript
# Each line's ancestry mosaic with nilHMM's RTIGER (math supplement, Text S6, "Ancestry inference"), one fit over the
# chromosomes of the markers given (one region, or all of a donor's regions).
#
# Markers: the union sites gap filling called ALT for the donor; per line, n_ref and n_alt are the bcftools mpileup
# AD of the site's REF and of the donor's ALT allele, summed over the count files (one per region). Rigidity
# r = max(1, round(Mb x the median line's covered markers (>= 1 read) per Mb of the markers' span)); lines with fewer
# than 2r covered markers on any chromosome are dropped first, since RTIGER stops on them. States: 0 B73/B73, 1 het,
# 2 donor/donor. Line checks (curve rule, docs/decisions.md 2026-10-11): per called line, its donor (state 1-2)
# segments, their bp, and the reads and ALT % of its markers inside the segments of each state.
#
# Usage: call_ancestry.R --markers MARKERS.vcf [...] --counts LINE.vcf [...] --rigidity-mb MB
#        --segments OUT.bed --dropped OUT.tsv --line-checks OUT.tsv [--seed S]
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

# one line's REF and donor-ALT read counts at the markers (0 where mpileup wrote no record)
read_line_counts <- function(path, sites) {
  v <- read_vcf(path)
  name <- tail(names(v), 1L)
  if (!nrow(v)) {
    return(sites[, .(name = name, chrom = CHROM, pos = POS, n_ref = 0L, n_alt = 0L)])
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
    name = name, chrom = m$CHROM, pos = m$POS,
    n_ref = vapply(seq_len(nrow(m)), function(i) count_of(m$i.REF[i], i), 0L),
    n_alt = vapply(seq_len(nrow(m)), function(i) count_of(m$i.ALT[i], i), 0L)
  )
}

main <- function(argv = commandArgs(trailingOnly = TRUE)) {
  a <- parse_args(argv)
  seed <- as.integer(if (is.null(a$seed)) 1L else a$seed)

  sites <- rbindlist(lapply(a$markers, function(f) read_vcf(f)[, .(CHROM, POS, REF, ALT)]))
  chroms <- unique(sites$CHROM)

  # a count file holds one region's records; the others' sites are 0 in it, so a line's files sum to its counts
  counts <- rbindlist(lapply(a$counts, read_line_counts, sites = sites))
  counts <- counts[, .(n_ref = sum(n_ref), n_alt = sum(n_alt)), by = .(name, chrom, pos)]
  by_chrom <- counts[, .(covered = sum(n_ref + n_alt >= 1L)), by = .(name, chrom)]

  # rigidity from a window in Mb: the median line's covered markers per Mb of the markers' span, summed over chromosomes
  span_mb <- sites[, .(span = max(POS) - min(POS)), by = CHROM][, sum(span)] / 1e6
  per_mb <- if (nrow(by_chrom) && span_mb > 0) median(by_chrom[, .(n = sum(covered)), by = name]$n) / span_mb else 0
  rigidity <- max(1L, as.integer(round(as.numeric(a$`rigidity-mb`) * per_mb)))
  log_info(
    paste(
      "%d markers on %d chromosome(s), %.2f Mb; median line %.1f covered markers per Mb;",
      "rigidity %d (%s Mb), lines need >= %d covered markers on each"
    ),
    nrow(sites), length(chroms), span_mb, per_mb, rigidity, a$`rigidity-mb`, 2L * rigidity
  )

  # a line's covered markers on its least covered chromosome
  covered <- by_chrom[, .(covered_markers = min(covered)), by = .(line = name)]
  covered[, cut := 2L * rigidity]
  dropped <- covered[covered_markers < cut]
  fwrite(dropped[order(line)], a$dropped, sep = "\t")
  kept <- counts[!name %in% dropped$line]
  log_info("%d lines counted, %d dropped under the cut, %d to RTIGER", nrow(covered), nrow(dropped), uniqueN(kept$name))

  bed <- data.table(chrom = character(), start = integer(), end = integer(), line = character(), state = integer())
  if (nrow(kept)) {
    # one thread: nilHMM 0.3.1 rtiger stops on "C stack usage too close to the limit" with threads > 1 (nilhmm#31)
    log_info("RTIGER on %d lines x %d markers", uniqueN(kept$name), nrow(sites))
    seg <- as.data.table(call_ancestry(
      kept[, .(name, chr = match(chrom, chroms), pos, n_ref, n_alt)],
      caller = "rtiger", rigidity = rigidity, threads = 1L, seed = seed
    ))
    bed <- seg[, .(chrom = chroms[chr], start = start_bp - 1L, end = end_bp, line = name, state)]
    log_info("%d segments", nrow(bed))
  }
  writeLines("#chrom\tstart\tend\tline\tstate", a$segments)
  fwrite(bed[order(line, match(chrom, chroms), start)], a$segments, sep = "\t", append = TRUE)
  fwrite(check_lines(bed, kept), a$`line-checks`, sep = "\t", na = ".", quote = FALSE)
}

# per line: donor segments (states 1-2 after state 0 or a chromosome start), their bp, reads and ALT % per state
check_lines <- function(bed, counts) {
  if (!nrow(bed)) {
    return(data.table(
      line = character(), n_donor_segments = integer(), donor_bp = integer(),
      ref_reads = integer(), ref_alt_pct = numeric(), het_reads = integer(), het_alt_pct = numeric(),
      alt_reads = integer(), alt_alt_pct = numeric()
    ))
  }
  b <- bed[order(line, chrom, start)]
  segs <- b[, .(
    n_donor_segments = sum(state > 0L & shift(state, fill = 0L) == 0L),
    donor_bp = sum((end - start)[state > 0L])
  ), by = .(line, chrom)][, .(n_donor_segments = sum(n_donor_segments), donor_bp = sum(donor_bp)), by = line]
  # each marker read in the segment holding it (BED start < pos <= end)
  r <- counts[b,
    on = .(name = line, chrom, pos > start, pos <= end), nomatch = NULL,
    .(line = name, state, n_ref, n_alt)
  ]
  r <- r[, .(reads = sum(n_ref + n_alt), alt = sum(n_alt)), by = .(line, state)]
  r[, alt_pct := fifelse(reads > 0L, round(100 * alt / reads, 1), NA_real_)]
  w <- dcast(r, line ~ state, value.var = c("reads", "alt_pct"))
  for (k in 0:2) {
    for (v in c("reads", "alt_pct")) {
      if (!paste0(v, "_", k) %in% names(w)) w[, (paste0(v, "_", k)) := if (v == "reads") 0L else NA_real_]
    }
  }
  w <- w[segs, on = "line"]
  w[, .(line, n_donor_segments, donor_bp,
    ref_reads = nafill(reads_0, fill = 0L), ref_alt_pct = alt_pct_0,
    het_reads = nafill(reads_1, fill = 0L), het_alt_pct = alt_pct_1,
    alt_reads = nafill(reads_2, fill = 0L), alt_alt_pct = alt_pct_2
  )][order(line)]
}

if (sys.nframe() == 0L) main()
