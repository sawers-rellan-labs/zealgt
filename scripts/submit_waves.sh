#!/bin/bash
# A production run as a Slurm chain (docs/runs/demultiplex_production.md, docs/runs/alignment_mexicana35.md): one hpc_prod
# head job per wave sheet <WAVES>/<step>_<NN>.csv from <first wave> on, each starting only after the previous one succeeded.
# Usage, on hazel from the checkout to run (its path goes to the head jobs as ZEALGT_REPO):
#   bash scripts/submit_waves.sh <step> <first wave NN> [nextflow args for every wave, e.g. -stub]
#   OUTDIR=<dir> (default /rsstu/users/r/rrellan/BZea/ZEAL/<step>); RESUME=<session id> resumes the first wave only
#   WAVES=<dir> of wave sheets (default meta/waves); MEM=<head job memory> (default 8G); NXF_OPTS reaches the head jobs
# --no-requeue: a head job requeued after a node failure would restart its wave without -resume
set -eo pipefail
STEP="${1:?step: demultiplex or alignment}"; shift
FIRST="${1:?first wave number, e.g. 01}"; shift
REPO=$(cd "$(dirname "$0")/.." && pwd)
OUTDIR=${OUTDIR:-/rsstu/users/r/rrellan/BZea/ZEAL/$STEP}
WAVES=$(cd "${WAVES:-$REPO/meta/waves}" && pwd)
sheets=$(ls "$WAVES"/"$STEP"_*.csv | awk -v first="$WAVES/${STEP}_$FIRST.csv" '$0 >= first')
[ -n "$sheets" ] || { echo "no wave sheet from ${STEP}_$FIRST.csv on" >&2; exit 2; }
prev=""
for sheet in $sheets; do
    resume=(); [ -z "$prev" ] && [ -n "$RESUME" ] && resume=(-resume "$RESUME")
    prev=$(sbatch --parsable --partition=compute --qos=normal --time=1-00:00:00 --mem="${MEM:-8G}" --no-requeue \
        --export=ALL,ZEALGT_REPO="$REPO" ${prev:+--dependency=afterok:$prev} "$REPO/scripts/submit_head_job.sbatch" hpc_prod \
        --step "$STEP" --input "$sheet" --outdir "$OUTDIR" "${resume[@]}" "$@")
    echo "$(basename "$sheet" .csv) job=$prev log=/share/maize/frodrig4/nf_work/zealgt_head_$prev.log"
done
