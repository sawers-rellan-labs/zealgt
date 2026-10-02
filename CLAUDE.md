# CLAUDE.md

## Project
`zealgt` takes the ZEAL maize samples from raw reads to genotypes on the NCSU hazel cluster (Nextflow, nf-core template):
the `ALIGNMENT` workflow stops at one CRAM per sample, then the `GENOTYPE` workflow reads those CRAMs.

## Never delete
- Never run `rm`, `rmdir`, `find -delete`, `git clean`, `rsync --delete`, `nextflow clean`, `truncate` or a clobbering redirect; a hook blocks them.
- Scratch to remove goes on a list for the user.

## How we work
- Work through one milestone without stopping (one process added and tested, one template folder reviewed); show the result there and wait for the user's OK.
- Ask in between only for decisions that are the user's to make.
- Short answers.

## Shell
- Anything longer than one line is a script in `agent/`, then run.
- `agent/` is gitignored scratch; never `git add -f` it.

## Code
- Flow control is channels, channel factories and operators (`map`, `join`, `branch`, `combine`); no procedural logic in `.nf` files.
- No code that checks files, tracks state, caches results or skips tasks: `-resume` and Nextflow's cache do that.
- A built-in directive or operator first; a custom Groovy function only when none fits, with the reason in the commit message.
- nf-core modules first; patch them only with `nf-core modules patch`.
- Resources only in config, measured per process; modules read only `task.cpus` and `task.memory`.
- Comments: one line saying what the code does; history goes in commits.

## Testing
- Wiring tests run on the laptop on fixtures, in minutes.
- Resource profiling runs on hazel, at most 30 min per process.
- No runs on full libraries without the user's OK.

## Containers
- Every module has a container from the start; every command it runs, `gzip` included, is in that container.

## Logging
- Task scripts log to stderr with timestamps, with a progress line about once a minute.
- Logs meant for `tail -f` are line-buffered (`sed -l`, `stdbuf -oL`).

## Sources
- Quote documents only from raw text (`pdftotext`, `curl`), never from a WebFetch summary.
