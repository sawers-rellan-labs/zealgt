---
name: hpc-debug-loop
description: How an agent operates on the hazel HPC cluster from the laptop - the edit/test/push/submit/report loop, how
  to connect, where things are, the cluster's rules, how to stop a run safely, and what never to do. Use for any hazel
  job, run or failure. How this pipeline's runs behave (resume, reruns, cleanup) is in docs/running.md, not here.
---

# HPC debug loop (hazel)

## The loop

1. **Edit on the laptop only.** Never edit files on hazel.
2. **Test on the laptop first** (fixtures, stubs, Docker): minutes, no queue, no cost; it catches wiring bugs.
   Hazel is only for what the laptop cannot test: real data, Slurm, Apptainer, resource numbers.
3. **Move code by git only**: commit, `git push`, then `ssh hazel 'git -C <checkout> pull'`. No scp, rsync or pasting of
   code; data and assets may go by `scp`. Every hazel run is then a commit. Do not pull while a run is active.
   **CodeRabbit per commit range, not per run:** before the first run on real sequencing files estimated at 15 min or more
   (task run time, without queue waits), review the code changed since the last review on the laptop and fix or answer
   every finding. Later runs of the same reviewed commit need no new review. Keep diffs small (a milestone or less) so a
   review takes minutes. Stubs and shorter runs need none.
4. **Submit as a Slurm job**; the workflow's head job runs inside Slurm too.
5. **On failure**: fix on the laptop and repeat from 2 (reading a failed run, resuming it: `docs/running.md`).
6. **Report to the user after every submission**: the job id and the log paths (which ones: `docs/running.md`).

## How to connect

- `ssh hazel '<one command>'`. The `Host hazel` entry in the user's `~/.ssh/config` (login.hpc.ncsu.edu, user frodrig4,
  `ControlMaster auto`, `ControlPersist 60m`) reuses the session the user authenticated; the agent never handles a password.
- Multi-line work is a script in `agent/` sent over stdin: `ssh hazel 'bash -s' < agent/<script>.sh` or
  `ssh hazel 'sbatch' < agent/<job>.sbatch`. Anything that must persist on hazel is in the repo and arrives by git.
- Directly over ssh only trivial commands: `git pull`, `squeue`, `sacct`, `seff`, `cat`/`tail` of logs, `ls`, `du`.
- Waiting for a job: poll in the background; never block the conversation. A job's real result is `sacct -j <id>`
  (State, ExitCode of the batch step), not the resource summary appended to its log.

## Where things are

- Checkout: `/rsstu/users/r/rrellan/BZea/ZEAL/zealgt` (permanent storage). Set `git config core.fileMode false` once after
  cloning (the `/rsstu` ACL strips exec bits).
- Scratch: `/share/maize/frodrig4` (files unread for 30 days are deleted); run directories: `docs/running.md`.
- Container images: the Apptainer cache set in `conf/hpc_shared.config`; Apptainer binary `/usr/local/apps/apptainer/1.4.2-1/bin`.

## The cluster's rules

- All computation through Slurm: `--account=maize_cpu --partition=compute_partners --qos=short` (at most 2 h).
  Longer jobs: `--partition=compute --qos=normal`. Downloads: `--partition=xfer` (internet access).
- Compute nodes have no internet access (DNS resolves, connections time out): images and anything else are downloaded
  beforehand by an xfer job. A missing image fails the task.
- A job is killed at 95 % of its `--mem`; size requests so the peak stays below that.
- Smallest compute nodes: 20 CPUs / 125 GB; keep any single task within 16 CPUs / 120 GB.
- Scripts run by jobs are called through their interpreter (`bash x.sh`, `python3 x.py`): exec bits do not survive on `/rsstu`.
- Quota (space and file count, limit 1 M files): `/usr/lpp/mmfs/bin/mmlsquota -g maize gpfsHPCcommon2`.

## Stopping a run

- `scancel --signal=INT --full <head job id>`: the workflow's head job cancels its own task jobs and exits. A plain
  `scancel <head>` leaves the task jobs running.
- Leftover task jobs: cancel by the exact job ids in that run's log. Never `scancel` by job name (other pipelines run on
  the same account).

## Never

- Delete anything (`rm`, `git clean`, workflow clean commands, ...): a hook blocks it. Scratch to remove goes on a list
  for the user.
- Run any computation, the workflow's head job included, on the login node.
