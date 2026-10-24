#!/usr/bin/env Rscript
# Each line's ancestry mosaic with nilHMM's RTIGER (math supplement, Text S6, "Ancestry inference"), one fit over the
# chromosomes of the markers given (one region, or all of a donor's regions).
#
# Markers: the union sites gap filling called ALT for the donor; per line (a sample of the count VCFs), n_ref and n_alt
# are the bcftools mpileup AD of the site's REF and of the donor's ALT allele, summed over the count files (one per
# region). Rigidity
# r = max(1, round(Mb x the median line's covered markers (>= 1 read) per Mb of the markers' span)); lines with fewer
# than 2r covered markers on any chromosome are dropped first, since RTIGER stops on them. States: 0 B73/B73, 1 het,
# 2 donor/donor. Line checks (curve rule, docs/decisions.md 2026-10-11): per called line, its donor (state 1-2)
# segments, their bp, and the reads and ALT % of its markers inside the segments of each state. Markers per
# chromosome of the fit unit (--regions, else the markers' chromosomes; 0 where a chromosome has none) and the median
# line's covered markers there, logged and written; nothing is dropped for them (decisions.md 2026-10-24).
#
# Usage: call_ancestry.R --markers MARKERS.vcf [...] --counts DONOR.REGION.counts.vcf.gz [...] --rigidity-mb MB
#        --segments OUT.bed --dropped OUT.tsv --line-checks OUT.tsv --markers-per-chrom OUT.tsv
#        [--regions REGION ...] [--seed S]
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

# a count file's lines (its samples) and their REF and donor-ALT read counts at the markers it has records for
read_counts <- function(path, sites) {
  v <- read_vcf(path)
  lines <- setdiff(names(v), c("CHROM", "POS", "ID", "REF", "ALT", "QUAL", "FILTER", "INFO", "FORMAT"))
  m <- v[sites, on = .(CHROM, POS), nomatch = NULL]
  if (!nrow(m)) {
    return(list(names = lines, counts = data.table(
      name = character(), chrom = character(), pos = integer(), n_ref = integer(), n_alt = integer()
    )))
  }
  # AD's place in FORMAT per record: bcftools call writes GT:AD where no ALT read is seen, GT:PL:AD elsewhere
  ad_at <- vapply(strsplit(m$FORMAT, ":", fixed = TRUE), function(f) match("AD", f), 0L)
  alleles <- strsplit(paste(m$REF, m$ALT, sep = ","), ",", fixed = TRUE)
  k_ref <- mapply(match, m$i.REF, alleles, USE.NAMES = FALSE)
  k_alt <- mapply(match, m$i.ALT, alleles, USE.NAMES = FALSE)
  # a read count from AD by allele index; 0 where the allele or the count is missing
  count_of <- function(depths, k) {
    d <- vapply(seq_along(depths), function(i) if (is.na(k[i])) NA_integer_ else depths[[i]][k[i]], 0L)
    fifelse(is.na(d), 0L, d)
  }
  counts <- rbindlist(lapply(lines, function(name) {
    cells <- strsplit(m[[name]], ":", fixed = TRUE)
    ad <- vapply(seq_along(cells), function(i) cells[[i]][ad_at[i]], "")
    depths <- lapply(strsplit(ad, ",", fixed = TRUE), function(x) suppressWarnings(as.integer(x)))
    data.table(
      name = name, chrom = m$CHROM, pos = m$POS, n_ref = count_of(depths, k_ref), n_alt = count_of(depths, k_alt)
    )
  }))
  list(names = lines, counts = counts)
}

main <- function(argv = commandArgs(trailingOnly = TRUE)) {
  a <- parse_args(argv)
  seed <- as.integer(if (is.null(a$seed)) 1L else a$seed)

  sites <- rbindlist(lapply(a$markers, function(f) read_vcf(f)[, .(CHROM, POS, REF, ALT)]))
  chroms <- unique(sites$CHROM)

  # each count file's records (one region each), then every line at every marker once, 0 where no file has a record
  files <- lapply(a$counts, read_counts, sites = sites)
  seen <- rbindlist(lapply(files, `[[`, "counts"))
  seen <- seen[, .(n_ref = sum(n_ref), n_alt = sum(n_alt)), by = .(name, chrom, pos)]
  grid <- CJ(name = unique(unlist(lapply(files, `[[`, "names"))), k = seq_len(nrow(sites)), sorted = FALSE)
  counts <- seen[grid[, .(name, chrom = sites$CHROM[k], pos = sites$POS[k])], on = .(name, chrom, pos)]
  counts[, `:=`(n_ref = nafill(n_ref, fill = 0L), n_alt = nafill(n_alt, fill = 0L))]
  by_chrom <- counts[, .(covered = sum(n_ref + n_alt >= 1L)), by = .(name, chrom)]

  # markers and the median line's covered markers per chromosome of the fit unit, 0 where it has none
  n_sites <- sites[, .N, by = CHROM]
  med <- by_chrom[, .(m = median(covered)), by = chrom]
  per_chrom <- data.table(chrom = unique(c(sub(":.*$", "", a$regions), chroms)))
  per_chrom[, `:=`(
    markers = nafill(n_sites$N[match(chrom, n_sites$CHROM)], fill = 0L),
    median_line_covered = nafill(as.numeric(med$m[match(chrom, med$chrom)]), fill = 0)
  )]
  for (k in seq_len(nrow(per_chrom))) {
    log_info(
      "%s: %d markers, median line %g covered markers", per_chrom$chrom[k], per_chrom$markers[k],
      per_chrom$median_line_covered[k]
    )
  }
  fwrite(per_chrom, a$`markers-per-chrom`, sep = "\t")

  # rigidity from a window in Mb: the median line's covered markers per Mb of the markers' span, summed over chromosomes
  span_mb <- sites[, .(span = max(POS) - min(POS)), by = CHROM][, sum(span)] / 1e6
  per_mb <- if (nrow(by_chrom) && span_mb > 0) median(by_chrom[, .(n = sum(covered)), by = name]$n) / span_mb else 0
  rigidity <- max(1L, as.integer(round(as.numeric(a$`rigidity-mb`) * per_mb)))
  short <- sites[, .(span = (max(POS) - min(POS)) / 1e6), by = CHROM][span < 2 * as.numeric(a$`rigidity-mb`)]
  if (nrow(short)) {
    # lines need 2r covered markers on each chromosome: a span under two windows drops the median line
    log_info(
      "WARNING: %s span under 2 x %s Mb; most lines may fall under the cut", paste(short$CHROM, collapse = ","),
      a$`rigidity-mb`
    )
  }
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
