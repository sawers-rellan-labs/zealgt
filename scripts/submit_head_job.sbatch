#!/bin/bash
# Nextflow head job: sbatch scripts/submit_head_job.sbatch <hpc_dev|hpc_prod> <nextflow run args...>
# One fixed launch directory per profile (nf_work/zealgt_dev, nf_work/zealgt_prod), so -resume always finds the cache.
# Production outlives the short QOS: sbatch --partition=compute --qos=normal --time=3-00:00:00 scripts/submit_head_job.sbatch hpc_prod ...
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
PROFILE="$1"; shift
case "$PROFILE" in
    hpc_dev)  LAUNCH=/share/maize/frodrig4/nf_work/zealgt_dev ;;
    hpc_prod) LAUNCH=/share/maize/frodrig4/nf_work/zealgt_prod
              [ "$SLURM_JOB_QOS" != short ] || { echo "hpc_prod needs a head job on the normal QOS (see line 4)" >&2; exit 2; } ;;
    *)        echo "first argument: hpc_dev or hpc_prod" >&2; exit 2 ;;
esac
REPO=/rsstu/users/r/rrellan/BZea/ZEAL/zealgt
# Nextflow image; its own NXF_HOME is read-only, so plugins and the secrets file live on /share (docs/running.md)
SIF=/share/maize/frodrig4/apptainer/nextflow_26.04.6.sif
NXF_DIR=/share/maize/frodrig4/nextflow_home
APPTAINER=/usr/local/apps/apptainer/1.4.2-1
# host Slurm client with its config cache, munge and SSSD user lookups; the data paths; apptainer to pull task images
BINDS=/usr/bin/sbatch,/usr/bin/squeue,/usr/bin/scancel,/usr/lib64/slurm,/var/spool/slurmd/conf-cache
BINDS=$BINDS,/usr/lib64/libmunge.so.2,/run/munge,/usr/lib64/libnss_sss.so.2,/var/lib/sss/pipes
BINDS=$BINDS,/share/maize/frodrig4,/rsstu/users/r/rrellan,$APPTAINER
export NXF_OFFLINE="${NXF_OFFLINE:-true}" APPTAINERENV_PREPEND_PATH="$APPTAINER/bin"
mkdir -p "$LAUNCH"
cd "$LAUNCH"
echo "$(date '+%F %T') job=$SLURM_JOB_ID profile=$PROFILE qos=$SLURM_JOB_QOS commit=$(git -C "$REPO" rev-parse --short HEAD) offline=$NXF_OFFLINE args: $*"
set +e
"$APPTAINER/bin/apptainer" exec -B "$BINDS" "$SIF" env NXF_OFFLINE="$NXF_OFFLINE" \
    NXF_PLUGINS_DIR="$NXF_DIR/plugins" NXF_SECRETS_FILE="$NXF_DIR/secrets/store.json" nextflow run "$REPO" -profile "$PROFILE" "$@" 2>&1 | awk '{ print strftime("%F %T"), $0; fflush() }'
rc=${PIPESTATUS[0]}
echo "$(date '+%F %T') nextflow exit=$rc"
exit "$rc"
