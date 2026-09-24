# Plan (DRAFT) — pipeline v2: one Nextflow pipeline from raw libraries to ancestry and imputed genotypes

Status: **proposal, 2026-09-24**, for discussion; nothing implemented. Storage section (§5) filled from the disk audit
(`nilhmm/bin/audit_du.sbatch`, job 946049, results in `ZEAL/results/audit_du_20260924/`).

## 0. First work in zealgt (user, 2026-09-24): no more demultiplexing of the libraries already in use
Demultiplexing is the most expensive step to repeat. In the nilhmm runs, pool 1B was demuxed ~9 times during the 09-11 → 09-14 gate runs,
and every other library was demuxed once but only its donor's samples were aligned, leaving ~2.8 TB of FASTQs for unaligned samples in
`work/` (§5). Nextflow did not prevent this: `workDir = ${params.outdir}/work` gave every new outdir an empty cache, demux FASTQs were not
published, and hash changes between tries reran DEMUX. These two tasks come before any other zealgt work.

### Task 1 — turn the existing demux FASTQs into CRAMs, once
Align every not-yet-aligned sample of the libraries that are already demuxed, from the FASTQs still in the nilhmm `work/` directories
(by `-resume` in the original launch directories, so the cached DEMUX tasks are reused, or by an alignment job reading those FASTQs
directly), with duplicate marking; write the CRAMs to the store.

| libraries demuxed | samples | aligned (2026-09-24) | to align | FASTQs now in |
|---|---|---|---|---|
| BC1 1B | 12 | 12 (`results/align_membench`) | 0 | `results/gate2/work` |
| BC1 4E, 4F, 4G | 36 | 4 (Zv.0490_P4) | 32 | `results/work` (launch `results/pool_run_4E4F4G`) |
| BC1 1A | 12 | 1 (S_1A_4) | 11 | `results/work` (launch `results/pool_run_1A`) |
| BC1 2A, 2B, 2F | 36 | 5 (Zx.0540_P3) | 31 | `results/work` (launch `results/pool_run_2A2B2F`) |
| BC1 2H, 3B–3E | 60 | Zx.0570_P2's | ~55 | `results/work` (launch `results/pool_run_2H3B3C3D3E`; other session's run — its decision) |
| BC2S3 batch-2 rows V22A–H, V23A–H, V24A–B | 216 wells | ~30 lines + checks | ~185 | `results/bc2s3_batch2/work` |
Scale: ~130 BC1 samples (~1 h × 8 cpu each, ~1,000 CPU-h) and ~185 lines (minutes each). **Until this is done and verified, those `work/`
directories are the only copy of the demuxed reads and must not be cleaned.** Done = every sample of these libraries has a verified,
non-empty CRAM in the store; then the FASTQs can go (§5, cleanup group A–C).

### Task 2 — make repeated demultiplexing impossible by construction
- **Development starts from CRAMs.** Development entries take a sample sheet of existing CRAMs; `read_demultiplexing` is not part of them.
- **Demux registry in the store.** A library is registered as done when its demux QC table and all its sample CRAMs are in the store.
  `read_demultiplexing` refuses a registered library unless it is named explicitly with `--force-demux <library>`.
- **One pass per library** for any library demuxed from now on: one task demuxes the library, aligns **all** its samples, marks
  duplicates and writes the CRAMs; FASTQs live only in that task's scratch and are deleted when it ends. `--samples` never restricts which
  samples of a demuxed library get aligned.
- **Reuse of existing outputs:** entries read existing CRAMs / tables through sample sheets; the workflow computes only what is missing
  in the store; CRAMs imported from nilhmm (made without duplicate marking) get a MARK_DUPLICATES-only step, not a realignment.
- **Raw libraries are read-only inputs.**

## 1. Why
The chr10 pilots ran as standalone sbatch scripts next to the `nilhmm/` pipeline. The same step was implemented more than once and the
copies drifted: B73 pools inside vs outside CRISP, `mpileup -I` present in one pileup and missing in another, a demux QC table overwritten
by every pool run, no duplicate removal anywhere. Each fix had to be applied in several places. One module per step removes that class
of error. The known issues this plan must settle are in §4.

## 2. Principles

### The rerun problem these principles address
In the nilhmm runs, a costly step (demultiplexing, whole-genome alignment) that had already completed ran again after an edit that could
not change its output: a comment, a cosmetic change to a module, or a resource reallocation. Each rerun left a new set of task
directories, so `work/` multiplied for menial reasons (the audit found ~3.2 TB there, §5).

The cause is how `-resume` decides: it reuses a task only if the task's **hash** is unchanged, and the hash covers the process's script
text after variable substitution, its inputs, and its environment (conda / container).

| change | reruns the task? | why |
|---|---|---|
| comment **inside** the `script:` block (bash `#`) | **yes** | it is part of the script text |
| comment **outside** it (Groovy `//` above the block) | no | not part of the script |
| `cpus` / `memory` / `time` changed, script uses `${task.cpus}` / `${task.memory}` (e.g. `-@ ${task.cpus}`, `-Xmx`) | **yes** | the value is substituted into the script text |
| the same resource change, script does not reference it | no | directives alone are not hashed |
| an input file touched (new mtime), same content | **yes** by default | default cache mode includes mtime |
| the same, with `cache 'lenient'` | no | path + size only |
| any edit, when the task's output already sits in its `storeDir` | no | the task is skipped whatever changed |

### Principles
1. **One module per step**, used by every entry; no standalone copies of a module's command.
2. **Separate entries per stage** (the existing `--entry` dispatcher): editing a downstream module never puts upstream tasks at risk.
3. **Costly, reusable outputs live in a permanent store (`storeDir`), not in `work/`**: CRAMs, per-pool demux QC. A task whose stored
   output exists is skipped whatever changed in the module; rerunning it is a deliberate act (delete the stored output).
4. **Hash hygiene** (from the table above):
   - comments and notes outside the `script:` block (Groovy `//`), never as bash `#` inside it;
   - threads and memory read from Slurm at run time (`-@ \$SLURM_CPUS_PER_TASK`), not `${task.cpus}` / `${task.memory}` in the script,
     so reallocating resources does not change the task hash;
   - `cache 'lenient'` (path + size, not mtime) on processes with large inputs.
5. **Temporaries die inside the task** (merged witness pool, sort temp, demux FASTQs if merged with ALIGN; see §5).
6. Tools: minibwa, samtools, bcftools, CRISP, nilHMM, PHG — the ones in use; environments prebuilt and referenced by prefix.

## 3. Stages (entries) and modules
| # | entry | modules | per | main output (store) |
|---|---|---|---|---|
| 1 | `read_demultiplexing` | DEMUX (cutadapt exact inline, `-e 0 --no-indels`), DEMUX_QC | pool | per-sample FASTQ (transient), `demux_qc/<pool>.tsv` (store, one file per pool) |
| 2 | `read_alignment` | ALIGN (minibwa -x sr) → **MARK_DUPLICATES** → CRAM (MAPQ 20, `-F 0x904`, duplicates flagged or removed) → MOSDEPTH | sample (BC1 sample, BC2S3 line, B73 pool) | `cram/<sample>.cram` (store) |
| 2b | `sample_quality_control` | QC_PANEL_COUNTS (`mpileup -I` at a blind QC panel, one task per sample) → COVERAGE_QC → RELATEDNESS_QC → DONOR_CONTENT_QC | sample / cohort | `sample_qc.tsv`: pass/fail + reason per sample; discovery and every caller read it |
| 3 | `variant_discovery` | WITNESS_POOL → CRISP (BC1 samples + witness only) → WITNESS_VETO → B73_CONTROL_COUNTS (`mpileup -I`) → POOLED_LIKELIHOOD_TIERS | donor × chr | `step4/<donor>.sites.tsv.gz` |
| 4 | `marker_union` | MARKER_UNION (tier-A sites of the donor set; multi-allelic dropped) | donor set × chr | `union/<set>_<chr>.tsv.gz` |
| 5 | `donor_allele_calling` | UNION_SITE_COUNTS (`mpileup -I -T union`, one task per sample) → JOINT_POOLED_LIKELIHOOD → GAP_FILLING (`dhd_bayes`) | sample / donor set × chr | donor allele table |
| 6 | `ancestry_inference` | LINE_ALLELE_COUNTS → RTIGER (design BC2S3, rigidity 500) | donor × chr | ancestry segments per line |
| 7 | `genotype_imputation` | DONOR_FOUNDER (gVCF → pseudo-assembly) → PHG_DATABASE → PHG_IMPUTATION (pairwise: B73 + donor, that donor's lines; F = 0, stay 0.99999) → RASTERIZE | donor × chr | genotypes at the union sites |
| 8 | `reporting` | CHROMOSOME_PAINTING, summary tables, KS / single-locus checks | donor × chr | paintings, tables |

### Stage 2b — sample QC before discovery (proposal, 2026-09-24)
Discovery assumes every BC1 sample and every line belongs to its recorded donor; a pollination error, seed mix-up or contaminated
pool breaks that silently (a wrong BC1 sample adds false alleles; a wrong line adds reads to the witness). The check must therefore run
before discovery and must not depend on any donor's discovered sites.
- **Blind QC panel:** lowcopy ranges ∩ teosinte-vs-B73 variants detected by wideseq, defined without any donor assumption. Positions only
  (panel genotypes are imputed). Caveat: distal taxa, huehuetenangensis most, are thin in the panels (1 Zh individual in Schnable 2023).
- **Coverage QC** (as in zealhmm `scripts/zeal_paired_cohort_coverage_qc.R`): covered panel markers per sample × chromosome; ladder of
  floors (RTIGER's 2 × rigidity, 10, 100); one table applied to every caller. λ per sample from mosdepth alongside.
- **Relatedness QC:** lines (λ 0.05–1.6) from genotype likelihoods or one random read per site (pseudo-haploid), no hard calls; BC1
  samples from their per-site ALT fractions (correlation of centered frequency vectors). Centered kinship (VanRaden, as in zealhmm
  `zeal_mlm_taxon.R`); a sample is flagged when its kinship to its own donor's samples/lines falls outside the within-donor distribution,
  or when it is closer to another donor. Expected signal: lines are ~87.5% B73, so relatedness comes from teosinte alleles; same-donor
  lines share H_d segments.
- **Donor-content QC:** fraction of panel sites with ALT reads vs the 12.5% expectation — catches B73 contamination (selfing, seed mix),
  which kinship alone does not separate from a line that carries little donor genome.
- Flagged samples are excluded from discovery and from the witness; the table records why.
- Open: the relatedness method for mixed pool/line samples; flag thresholds; whether Zh needs its own panel (e.g. from its assembly).

Donor sets for stages 4–5 are named in a run card (`docs/runs/<run>.md`: purpose, donors with BC1 count / lines / coverage, exclusions),
and each entry checks the run card before starting.

## 4. Known issues and where each is settled
| # | issue (found 2026-09-20 → 24) | settled in | decision needed |
|---|---|---|---|
| 1 | No duplicate removal (BC1, lines, B73 pools). Pooled-caller benchmark and GATK best practices remove/mark PCR duplicates [1, 2]; CRISP paper silent [3] | stage 2 MARK_DUPLICATES | **decided 2026-09-24: `samtools markdup -d 2500`** (optical distance for NovaSeq patterned flow cells), in the alignment stream (`fixmate -m` → `sort` → `markdup`); imported nilhmm CRAMs: collate → fixmate → sort → markdup, same tool. Picard only if library-complexity metrics are wanted |
| 1b | No read groups: CRAMs lack @RG; a header-only RG made GATK count zero reads silently (09-21) | stage 2 | **decided 2026-09-24:** RG in every read, at alignment (`minibwa -R` if supported, else `samtools addreplacerg` inline before `fixmate`); imported CRAMs get it in the MARK_DUPLICATES pass. ID = sample (sample.lane if split), SM = Sample_Id, LB = library (BC1 pool / batch-2 row), PL = ILLUMINA, PU = flowcell.lane. Merged pools (witness) keep one RG. GATK is not used; if ever, the RG is already there. Fields that matter: **SM** (bcftools mpileup sample names) and **one RG per merged pool** (CRISP splits a file by RG). LB is written but no step depends on it: duplicate marking runs per sample CRAM (one library each), merged pools are not deduplicated |
| 2 | CRISP run with `--filterreads 0` (its mismatch filter off; the CRISP paper used ≤ 3 mismatches, MAPQ ≥ 20, base quality ≥ 17 [3]) | stage 3 CRISP | turn it back on? |
| 3 | Insertion records at a SNP position overwrite its counts (ALT → 0) unless `mpileup -I` | one COUNTS helper used by stages 3, 5, 6 | make the helper skip indel records itself |
| 4 | Demux QC table overwritten by every pool run | stage 1 DEMUX_QC | one file per pool (store) |
| 5 | Witness veto depends on witness depth (10 lines at 0.4x kept 20% of records) | stage 3 VETO | keep "≥ 1 ALT read" or make it depth-aware |
| 6 | Tiers depend on the count source (CRISP vs mpileup disagreed at ~15% of own tier-A sites) | stages 3 vs 5 | which counts define tiers |
| 7 | RTIGER rigidity fixed at 500 vs a density-scaled rule | stage 6 | confirm 500 |
| 8 | Marker union / donor allele calling / gap filling / ancestry inference exist only as standalone scripts (`PHG/bin/`) | stages 4–6 | port as modules |

## 5. Storage, caching and cleanup (from the disk audit, 2026-09-24, job 946049)
Measured (`du -sk` / `--inodes`, one array task per directory; table `ZEAL/results/audit_du_20260924/tasks/`):

| location | size | files |
|---|---|---|
| `results/work/` (Nextflow, `--outdir ZEAL/results` runs) | 1,903 GB | 1,482 |
| `results/gate2/work/` | 1,015 GB | 1,064 |
| `results/bc2s3_batch2/work/` | 279 GB | 2,047 |
| `results/demux/` | 81 GB | 37 |
| `ZEAL/reference/` | 65 GB | 263 |
| `results/align_membench/` (pool-1B CRAMs) | 41 GB | 25 |
| `results/cram/` | 22 GB | 21 |
| `results/b73_control/` | 22 GB | 26 |
| `/share/maize/frodrig4/tmp` | 22 GB | 652 |
| `results/qcset_designB/`, `results/pilot_1B_chr10/` | 17 GB, 16 GB | 5.6K, 6.0K |
| `ZEAL/envs/`, `/share/maize/frodrig4/conda` | 15 GB, 12 GB | 49K, 160K |
| all other `results/*` (pilots, benchmarks, logs, PHG DBs 0.2–1.2 GB each) | < 10 GB each | |
| `results/stub/` | 0.3 GB | 106K |

Findings: ~3.2 of ~3.6 TB is Nextflow `work/` (few, huge files: demux FASTQs + alignment intermediates of the pool, gate-2 and
batch-2 runs), because `nextflow.config` sets `workDir = "${params.outdir}/work"` on the persistent partition. Published results are
small. The large file counts are environments and the stub run, not data.

Rules proposed for v2:
1. `workDir` on `/share/maize/frodrig4/nf_work/<run>` (2 TB, not persistent; 22 GB used today). Results published to `/rsstu`.
2. CRAMs, per-pool demux QC and step-4 tables in a `storeDir` on `/rsstu` (`ZEAL/store/{cram,demux_qc,step4}`), never in `work/`.
3. Demux FASTQs never outlive their alignment: one DEMUX+ALIGN task per library, all samples aligned, FASTQs in the task's scratch only
   (§0, Task 2); 3–4 libraries at a time fit the 2 TB scratch.
4. After each successful run: `nextflow clean -f -but <last>` and a size report; stub runs always cleaned.
5. Existing `work/` (3.2 TB): before deleting, confirm every CRAM / table the project uses is published outside `work/`
   (`results/cram`, `results/align_membench`, `results/bc2s3_batch2/cram`, the pilot dirs) — decision and check pending, nothing deleted.

## 6. Supervision
Per run: own launch dir and `workDir`; a post-run check (work size, failed tasks, published outputs); monitors, not sleep loops; long runs
watched with the session kept open (`/loop`), acting only as the run card allows.

## 7. Open decisions (summary)
1–7 of §4; storage rules of §5; which existing CRAMs and tables are reused vs regenerated after MARKDUP.

## References
1. Huang HW, Mullikin JC, Hansen NF. Evaluation of variant detection software for pooled next-generation sequence data.
   *BMC Bioinformatics* 2015;16:235. doi:10.1186/s12859-015-0624-y
2. Van der Auwera GA, Carneiro MO, Hartl C, Poplin R, et al. From FastQ data to high-confidence variant calls: the Genome Analysis
   Toolkit best practices pipeline. *Curr Protoc Bioinformatics* 2013;43:11.10.1–11.10.33. doi:10.1002/0471250953.bi1110s43
3. Bansal V. A statistical method for the detection of variants from next-generation resequencing of DNA pools.
   *Bioinformatics* 2010;26(12):i318–i324. PMC2881398
4. Danecek P, et al. Twelve years of SAMtools and BCFtools. *GigaScience* 2021;10(2):giab008. (not re-checked this session)
