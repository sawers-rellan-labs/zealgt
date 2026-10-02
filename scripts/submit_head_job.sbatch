#!/bin/bash
# Nextflow head job on hazel: sbatch scripts/submit_head_job.sbatch <run> <nextflow run args...>
# Launch directory /share/maize/frodrig4/nf_work/<run>; every console line is timestamped.
# Pulling missing images needs internet: sbatch --partition=xfer --export=ALL,NXF_OFFLINE=false ...
#SBATCH --job-name=zealgt_head
#SBATCH --account=maize_cpu
#SBATCH --partition=compute_partners
#SBATCH --qos=short
#SBATCH --time=02:00:00
#SBATCH --cpus-per-task=1
#SBATCH --mem=8G
#SBATCH --output=/share/maize/frodrig4/nf_work/zealgt_head_%j.log
set -eo pipefail
RUN="$1"; shift
REPO=/rsstu/users/r/rrellan/BZea/ZEAL/zealgt
NXF_PREFIX=/share/maize/frodrig4/conda/zealgt/nextflow-e6dd1f03
export NXF_OFFLINE="${NXF_OFFLINE:-true}" NXF_ANSI_LOG=false NXF_PLUGINS_DIR="$NXF_PREFIX/share/nextflow/plugins"
export PATH="$NXF_PREFIX/bin:/usr/local/apps/apptainer/1.4.2-1/bin:$PATH"
mkdir -p "/share/maize/frodrig4/nf_work/$RUN"
cd "/share/maize/frodrig4/nf_work/$RUN"
echo "$(date '+%F %T') job=$SLURM_JOB_ID run=$RUN commit=$(git -C "$REPO" rev-parse --short HEAD) offline=$NXF_OFFLINE args: $*"
set +e
nextflow run "$REPO" "$@" 2>&1 | awk '{ print strftime("%F %T"), $0; fflush() }'
rc=${PIPESTATUS[0]}
echo "$(date '+%F %T') nextflow exit=$rc"
exit "$rc"
