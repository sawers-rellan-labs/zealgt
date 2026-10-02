# Running, resuming and rerunning

How runs of this pipeline reuse earlier work. Each fact gives its source: the Nextflow documentation
(`docs/cache-and-resume.mdx`, `docs/reference/config/unscoped.mdx` in the Nextflow repository) or a test on
Nextflow 26.04.6 (laptop, or hazel GPFS with tasks on Slurm compute nodes).

## Profiles and launch directories
- `hpc_dev`: development on heads of one library; launch directory always `/share/maize/frodrig4/nf_work/zealgt_dev`;
  `work/` kept; each stage's result published as hard links.
- `hpc_prod`: whole libraries; launch directory always `/share/maize/frodrig4/nf_work/zealgt_prod`; only CRAMs and QC
  published; `cleanup = true`; head job on the normal QOS.
- Start: `sbatch scripts/submit_head_job.sbatch hpc_dev <nextflow run args>` (production: see the script's header).
- One fixed launch directory per profile: the task cache lives in `<launch directory>/.nextflow/cache`, and resuming
  needs that cache and `work/` intact (docs). A new directory per attempt starts every run cold.

## What reruns a step on `-resume`
- Reruns: a change to the step's script, inputs, container, the `ext` values its script uses, or its process or calling
  workflow name (docs). Tested: changing `ext.args` reruns the step.
- Does not rerun: a change to cpus or memory, even when the script uses `${task.cpus}` (tested). So a resumed run after
  a resource change returns the result made with the old resources.
- Nothing changed: every step comes from the cache (tested, also on hazel across compute nodes in the standard cache
  mode, inputs on `/share` and `/rsstu`; `cache = 'lenient'` not needed).
- `-resume` serves both failure recovery and development iteration (docs).

## Rerun from a given step
`-resume` plus `cache = false` for that step, in a small config passed with `-c`:
```
process { withName: 'FQTK' { cache = false } }
```
Steps before it come from the cache; the step and every step after it run again (tested). Use it to measure a resource
change: edit the resources in `conf/hpc_dev.config` or `conf/hpc_prod.config`, then rerun the step this way.

## Cleanup and published files
- `cleanup = true` deletes the files of a run in `work/` when the run succeeds and prevents resuming that run (docs);
  a failed run keeps its `work/` (tested). A run that took every step from the cache leaves `work/` as it was (tested).
- Hard-linked published files (`publish_dir_mode = 'link'`, output on `/share`) keep their content when cleanup deletes
  `work/` (tested on hazel); symlinks would break.
