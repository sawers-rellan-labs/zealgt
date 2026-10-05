# Running, resuming and rerunning

How runs of this pipeline reuse earlier work. Each fact gives its source: the Nextflow documentation
(`docs/cache-and-resume.mdx`, `docs/reference/config/unscoped.mdx` in the Nextflow repository) or a test on
Nextflow 26.04.6 (laptop, or hazel GPFS with tasks on Slurm compute nodes).

## Profiles and launch directories

- `hpc_dev`: development on heads of one library; launch directory always `/share/maize/frodrig4/nf_work/zealgt_dev`;
  `work/` kept; outputs published as hard links.
- `hpc_prod`: whole libraries; launch directory always `/share/maize/frodrig4/nf_work/zealgt_prod`; outputs (the FASTQs
  of `demultiplex`, the CRAMs and QC of `alignment`) copied; `cleanup = true`; head job on the normal QOS.
- Start: `sbatch scripts/submit_head_job.sbatch hpc_dev --step <demultiplex|alignment> <nextflow run args>` (production:
  see the script's header). `alignment` reads the `samplesheets/<input name>.csv` a `demultiplex` run published, or some of its
  rows; the two runs share the launch directory and its cache.
- Compute nodes have no internet: the head job sets `NXF_OFFLINE=true`; a run that must download images runs its head
  job on the xfer partition with `NXF_OFFLINE=false` (see the script's header); Nextflow then pulls them into the cache.
- Nextflow runs from the official image `/share/maize/frodrig4/apptainer/nextflow_26.04.6.sif` with the host's Slurm
  client bound in; plugins and the secrets file are in `/share/maize/frodrig4/nextflow_home` (the image's own
  `NXF_HOME` is read-only). After a scratch purge, pull both again from an xfer job (`--partition=xfer`):
  `apptainer pull <sif> docker://nextflow/nextflow:26.04.6`, then
  `apptainer exec -B /share/maize/frodrig4 --env NXF_OFFLINE=false,NXF_PLUGINS_DIR=/share/maize/frodrig4/nextflow_home/plugins <sif> nextflow plugin install nf-schema@2.5.1`.
- Stop a run: `scancel --signal=INT --batch <head job id>`; the head job passes INT to Nextflow, which cancels its tasks.
- One fixed launch directory per profile: the task cache lives in `<launch directory>/.nextflow/cache`, and resuming
  needs that cache and `work/` intact (docs). A new directory per attempt starts every run cold.

## Container bindings (hazel)

Two layers of Apptainer containers, each seeing only the host paths bound into it (`-B`):

- Head job: `scripts/submit_head_job.sbatch` runs the Nextflow image with `BINDS`: the host Slurm client (`sbatch`,
  `squeue`, `scancel`, its libraries and config cache), munge and SSSD (user lookups), Apptainer itself (to start and
  pull task images) and the data roots `/share/maize/frodrig4` and `/rsstu/users/r/rrellan`.
- Tasks: each task's `.command.run` calls `apptainer exec --no-home --pid` with (seen on hazel, job 1097636):
  1. the launch directory (`work/`), from `apptainer.autoMounts = true` (`conf/hpc_shared.config`);
  2. the folders of the task's input files, also from `autoMounts`;
  3. `/share/maize/frodrig4,/rsstu/users/r/rrellan/BZea`, from `apptainer.runOptions` (`conf/hpc_shared.config`).
- When 2 and 3 name the same folder, Apptainer prints `WARNING: While bind mounting '<dir>:<dir>': destination is
already in the mount point list` in the task's `.command.err`, skips the duplicate, and the task runs normally
  (job 1097636).

## When a run fails

- Read the failing task's `.command.err` (also `.command.out`, `.command.sh`) in its task directory under `work/`; the
  head log names that directory.
- Fix on the laptop, then rerun with `-resume` from the same launch directory: finished steps come from the cache.
- One task alone, without the pipeline: `bash .command.run` in its task directory reruns it in place (tested on the
  laptop, local executor).
- Logs to report after every submission: the head log `/share/maize/frodrig4/nf_work/zealgt_head_<job id>.log`, the
  launch directory's `.nextflow.log`, and on failure the task's `.command.err`.

## What reruns a step on `-resume`

- Reruns: a change to the step's script, inputs, container, the `ext` values its script uses, or its process or calling
  workflow name (docs). Tested: changing `ext.args` reruns the step.
- Does not rerun: a change to cpus or memory, even when the script uses `${task.cpus}` (tested). So a resumed run after
  a resource change returns the result made with the old resources.
- Does not rerun: an edit to a script in `bin/` or in a module's `resources/usr/bin/` (tested 2026-10-04): the step
  returns the result made with the old script. A script passed as a `path` input is hashed by content, so an edit
  reruns the step (tested 2026-10-04).
- `bin/` scripts must be executable (docs), and the `/rsstu` checkout strips exec bits: a tool called from `bin/` fails
  on hazel. Call tools through their interpreter (`python3 ${tool}`) or put them in the container.
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

## Laptop runs

- Launch from `agent/run/` (gitignored): `cd agent/run && nextflow run ../.. -profile test ...`; the launch directory
  gets `.nextflow.log*`, `.nextflow/` and `work/`, so the repository root stays clean.

## The DAG

- Take it from a stub run on the laptop: `-profile test -stub -with-dag dag.dot` (seconds; `.mmd` and `.svg` work too).
  Not with `-preview`: on 26.04.6 it logs success but never exits (operators wait for process output that preview
  never makes), and the DAG written on its abort has unindexed nodes (`v-1`) that crash the Mermaid renderer (tested
  2026-10-03).
