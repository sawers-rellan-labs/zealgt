# Running, resuming and rerunning

How runs of this pipeline reuse earlier work. Each fact gives its source: the Nextflow documentation
(`docs/cache-and-resume.mdx`, `docs/reference/config/unscoped.mdx` in the Nextflow repository) or a test on
Nextflow 26.04.6 (laptop, or hazel GPFS with tasks on Slurm compute nodes).

## Profiles and launch directories

- `hpc_dev`: development on heads of one library; launch directory `/share/maize/frodrig4/nf_work/zealgt_dev` (a second
  run at the same time: its own, `ZEALGT_LAUNCH=<dir>`);
  `work/` kept; outputs published as hard links.
- `hpc_prod`: whole libraries; launch directory `/share/maize/frodrig4/nf_work/zealgt_prod` (a second chain at the same
  time: its own, `ZEALGT_LAUNCH=<dir>`; a chain after another: `AFTER=<job id>` of its last wave); outputs (the FASTQs
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

## Head job memory (hazel)

Head jobs: 16 GB for production (`NXF_OPTS="-Xms1g -Xmx12g"`), 8 GB for tests (the default of
`scripts/submit_head_job.sbatch`); their peak always equals the request, so never raise it unless authentically OOM
(user, 2026-10-17).

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
- The `runOptions` binds stay (user, 2026-10-05): `autoMounts` binds only the folders of staged input files, so a
  path a task reaches otherwise (from a samplesheet, from `ext.args`, or through a symlink on `/share` into `/rsstu`)
  would no longer be visible. Removing them needs a stub run and an alignment run on hazel first.

## When a run fails

- Read the failing task's `.command.err` (also `.command.out`, `.command.sh`) in its task directory under `work/`; the
  head log names that directory.
- Fix on the laptop, then rerun with `-resume` from the same launch directory: finished steps come from the cache.
- One task alone, without the pipeline: `bash .command.run` in its task directory reruns it in place (tested on the
  laptop, local executor).
- Logs to report after every submission: the head log `/share/maize/frodrig4/nf_work/zealgt_head_<job id>.log`, the
  launch directory's `.nextflow.log`, and on failure the task's `.command.err`.

## Slurm jobs outlive their tasks (hazel)

- `squeue` / `sacct` can show more task jobs than `executor.queueSize`; Nextflow still caps its tasks. Its log states
  the cap (`Creating task monitor for executor 'slurm' > capacity: 40`), and a slot frees when the task writes
  `.exitcode` (`Task completed` in `.nextflow.log`).
- The Slurm job ends later, CPU idle: V21 alignment (head job 1103869, 1,057 jobs), Slurm `End` minus Nextflow's
  `Task completed`: < 1 min 529, 1-5 min 280, 5-30 min 202, > 30 min 46 (FGUMI_CLIP P4088, job 1104382: task 1 min, job
  58 min, TotalCPU 1 min 49 s). Up to 168 jobs at once against 40 tasks.
- Every process, 115 nodes, mostly at the run's busiest half hour, longest for the heavy writers (fixmate, sort, merge):
  likely file closes stalling on `/share` under load; not confirmed. Nextflow's wrapper does nothing after `.exitcode`
  (26.04.6: no scratch, no `sync`).
- Effects: disk budgets hold (a finished task writes nothing); idle allocations count against fair-share. Nothing to
  change on our side.
- To check a run: compare each job's `Task completed` time in `.nextflow.log` with `sacct -j <ids> -X --format=JobID,End`.

## Slurm job names (hazel)

- `hpc_dev` and `hpc_prod` name each task's job by its process and tag (`executor.jobName`), e.g.
  `CRISP_Zh.0030_P4_chr3`; VARIANT_CALLING tags carry the region (`conf/modules.config`).
- A job array (`array` in the profiles: `COUNT_UNION` in `hpc_dev`; alignment steps and the per-donor variant-calling
  steps in `hpc_prod`) keeps Nextflow's own long name
  for all its tasks, `executor.jobName` aside (`nf-ZEALGT_..._COUNT_UNION_(1)`, Milestone 9f test 6). An array also
  waits until it holds `array` tasks or its input ends. Which task is which: `.nextflow.log` (`Submitted process`, task
  name and tag) or the trace (`name`, `native_id` = array job ID and index).

## What reruns a step on `-resume`

- Reruns: a change to the step's script, inputs, container, the `ext` values its script uses, or its process or calling
  workflow name (docs). Tested: changing `ext.args` reruns the step.
- Reruns: every process after a newly added process with `eval` outputs (the nf-core versions topic): `.command.sh`
  numbers the eval outputs across the pipeline (`nxf_out_eval_37` became `_39`), so their scripts change (tested
  2026-10-08, job 1152864: the ancestry tasks reran after `UNION_SITE_COUNTS` was added; outputs identical).
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

## Stubs on hazel

Step 3 of the test order (`CLAUDE.md`) checks paths, containers, Slurm and the profiles, no logic, in minutes. A
pipeline stub cannot: its dependent steps run one after another, and Slurm starts each new job only at its next
scheduling pass (`SchedulerParameters=defer`, ~50 s), so the GENOTYPE stub (~20 steps) took 24 min (job 1270344) and
19 min with 10 s polling (1316875); the alignment stub (8 steps) 57 and 9 min (1271775, 1316876). Hence:

- **Process checks**: every process's stub runs alone from ready inputs, all at once, one Slurm wait in all.
  `tests/hazel/*.nf.test` (one per module, inputs from `tests/fixtures/`; the nf-core modules' own tests download
  theirs) run from one job: `sbatch --export=ALL,ZEALGT_REPO=<checkout> scripts/run_hazel_tests.sbatch`, with nf-test
  under the Nextflow image's java and `conf/stub_hazel.config`. 26 tests in 6 min (job 1317802); 12 at a time in 8 GB, ~0.5-0.6 GB each (jobs 1317265, 1317802). Parallel tasks cannot
  race: each task writes only in its own work directory. A process test applies settings under the module's own name
  only, not under its aliases (`COUNT_LINES`, `.*FASTQ_ALIGN_MINIBWA:SAMTOOLS_MERGE`).
- **The run's setup**, with `PARAMS=<the run's params file>` (and `PROFILE`) on the same job, beside the tests:
  `nextflow config` (config, profile), then `nextflow inspect` (every container; it does not check parameters).
  Parameters: the sheet check above and the run's own schema check in its first seconds. No `-preview`: with a
  workflow output block it never exits in Nextflow 26.04.6 (nextflow-io/nextflow#7836).
- **No chained pipeline stub**, also after profile changes: the process checks run under `hpc_prod` with the profile's
  settings (user, 2026-10-17; stub 1349205 cancelled). A pipeline stub, if ever run, as below.

1. **Check the sheet first** (seconds, no Nextflow):
   - every path is absolute, since Nextflow resolves `--input` from the launch directory (stub 1269132);
   - every file exists;
   - every donor keeps a BC1 pool and a line at or above `min_mean_coverage`. A donor without lines over the floor has
     no witness, and the union's join stops the run (stub 1269329).
2. **Poll Slurm every 10 s**: add `-stub -c <checkout>/conf/stub_hazel.config` to the head job's arguments (an
   absolute path: the head job runs in the launch directory). Tasks stay Slurm jobs with their containers, as in a real
   run. Running them inside the head job (`process.executor = 'local'`) does not work on hazel: Nextflow runs in its own
   Apptainer image there, and a task's Apptainer started inside it fails (`stat /bin/bash: no such file or directory`,
   stubs 1316854 and 1316855; `failed to resolve session directory`, srun test 1316867).

## Laptop runs

- Launch from `agent/run/` (gitignored): `cd agent/run && nextflow run ../.. -profile test ...`; the launch directory
  gets `.nextflow.log*`, `.nextflow/` and `work/`, so the repository root stays clean.

## The DAG

- Take it from a stub run on the laptop: `-profile test -stub -with-dag dag.dot` (seconds; `.mmd` and `.svg` work too).
  Not with `-preview`: on 26.04.6 it logs success but never exits (operators wait for process output that preview
  never makes), and the DAG written on its abort has unindexed nodes (`v-1`) that crash the Mermaid renderer (tested
  2026-10-03).
