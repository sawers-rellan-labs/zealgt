# CLAUDE.md

## Project

`zealgt` takes the ZEAL maize samples from raw reads to genotypes on the NCSU hazel cluster (Nextflow, nf-core template):
the `ALIGNMENT` workflow stops at one CRAM per sample, the `VARIANT_CALLING` workflow reads those CRAMs and stops at
each line's counts at its donor's markers, then the `ANCESTRY` workflow reads those counts.

## Never delete

- Never run `rm`, `rmdir`, `find -delete`, `git clean`, `rsync --delete`, `nextflow clean`, `truncate` or a clobbering redirect; a hook blocks them.
- Scratch to remove goes on a list for the user.

## How we work

- Work through one milestone without stopping (one process added and tested, one template folder reviewed); show the result there and wait for the user's OK.
- Ask in between only for decisions that are the user's to make.
- Work follows `docs/milestones/`: an approved spec per milestone, then autonomous work, then a report.
- Anything that waits (tests, reviews, pipeline runs, hazel polls) runs in the background; longer self-contained work (a review-and-fix cycle, a hazel run with its polling) goes to a subagent.
- Short answers.

## Shell

- Anything longer than one line is a script in `agent/`, then run.
- `agent/` is gitignored scratch; never `git add -f` it.

## Code

- Flow control is channels, channel factories and operators (`map`, `join`, `branch`, `combine`); no procedural logic in `.nf` files.
- No code that checks files, tracks state, caches results or skips tasks: `-resume` and Nextflow's cache do that.
- A built-in directive or operator first; a custom Groovy function only when none fits, with the reason in the commit message.
- nf-core modules first; patch them only with `nf-core modules patch`.
- Established tools (bcftools, bedtools, samtools, ...) before own scripts; an own script only when none fits, with the reason in the commit message.
- Resources only in config, measured per process; modules read only `task.cpus` and `task.memory`.
- Comments: one line saying what the code does; history goes in commits.
- `workflows/<name>.nf`: the list of stage calls only, <= 100 lines.
- `subworkflows/local/<stage>/main.nf`: one stage's channel wiring, <= 100 lines; `modules/local/<tool>/main.nf`: one tool call, <= 100 lines.
- `subworkflows/local/utils_nfcore_zealgt_pipeline/`: template code plus the samplesheet-to-channel step only; no Groovy function files.
- Analysis steps (Python, R, bash) are command-line tools, not module templates; a module's script is one tool call.
- R code passes `lintr` and is formatted with `styler`.

## Testing

Before running or rerunning the pipeline, read `docs/running.md`. Steps in order; each passes before the next:

1. Tools: each tool alone on small fixtures (unit tests, reference outputs) before it goes into a module.
2. Wiring: the pipeline on stubs on the laptop, in seconds; gives the channel-level DAG. All laptop tests <= 5 min.
3. Hazel setup, minutes, no chain: the run's config and containers (`nextflow config`, `inspect`) and every
   process's stub run alone from ready inputs, all at once (`scripts/run_hazel_tests.sbatch`). Checks no logic.
4. Review: CodeRabbit on the commit range, beside step 3. Skipped for config, docs and one-line fixes with a test.
5. Slice: the pipeline on a real-data slice (a few samples, a few Mb) on the laptop, results checked; <= 15 min.
6. Resource profiling on hazel, at most 30 min per process. No runs on full libraries without the user's OK.

## Containers

- Every module has a container from the start; every command it runs, `gzip` included, is in that container.

## Logging

- Task scripts log to stderr with timestamps, with a progress line about once a minute.
- Logs meant for `tail -f` are line-buffered (`sed -l`, `stdbuf -oL`).

## Sources

- Quote documents only from raw text (`pdftotext`, `curl`), never from a WebFetch summary.
