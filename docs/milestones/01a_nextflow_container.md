# Milestone 1a: Nextflow from a container on hazel

The head job runs Nextflow 26.04.6 from an Apptainer image instead of the conda env `nextflow-e6dd1f03`
(`../decisions.md`, "Nextflow from a container on hazel"). An image is one file; the conda env is 7,601.

## Image

- `docker://nextflow/nextflow:26.04.6` (official, amd64; Amazon Linux base, glibc to check against hazel's 2.34).
- Pulled once by an xfer job into `/share/maize/frodrig4/apptainer/nextflow_26.04.6.sif`.
- `NXF_HOME` (plugins, `nf-schema@2.5.1`) on `/share/maize/frodrig4/nextflow_home`; the image's own is read-only.
  The xfer job installs the plugin; the head job stays `NXF_OFFLINE=true`.

## What the head job needs inside the container (hazel facts, 2026-10-02)

- Slurm client 25.11.8: `/usr/bin/{sbatch,squeue,scancel,sacct,scontrol}`, library `/usr/lib64/slurm/`.
- Slurm config: `SLURM_CONF=/etc/slurm/slurm.conf`, but `/etc/slurm` does not exist on the login node (configless
  Slurm); where a compute node keeps it is the first thing to check.
- Munge: socket `/run/munge/munge.socket.2`.
- Paths at the same place as on the host: `/share`, `/rsstu`, `$HOME` (task scripts run on the host).
- `apptainer` only for pulling missing task images; the xfer head job binds `/usr/local/apps/apptainer/1.4.2-1`.

## Choices this spec settles

- Official image, not our own build. Rejected: building one (another recipe to keep).
- Slurm and munge bound from the host. Rejected: Slurm installed in the image (must match the cluster's version and
  config exactly).
- Rejected: conda env (7,601 files per env) and hazel's modules (`nextflow/25` is older than 26.04.6).

## Tests (hazel, each a short job)

1. xfer job: pull the image; `nextflow -version` in it; install `nf-schema@2.5.1` into `NXF_HOME`.
2. Compute job: inside the container, `sbatch --wrap hostname`, `squeue`, `sacct` and `scancel` work.
3. Stub run: `submit_head_job.sbatch hpc_dev -stub` on the M1 stub inputs; every task is submitted and completes.
4. Stop: `scancel --signal=INT --full <head>` during a stub run cancels its task jobs.

## Changes

- `scripts/submit_head_job.sbatch`: `apptainer exec` with the binds above, instead of `NXF_PREFIX`.
- `docs/running.md`: the image, `NXF_HOME`, and how to pull them again.

## Done when

- Tests 1-4 pass; the head job uses no conda env.
- Then `/share/maize/frodrig4/conda/zealgt/` goes on the cleanup list, after checking that no run uses it.
