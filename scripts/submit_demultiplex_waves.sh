#!/bin/bash
# Production demultiplexing as a Slurm chain (docs/runs/demultiplex_production.md): one hpc_prod head job per wave sheet
# meta/waves/demultiplex_<NN>.csv from <first wave> on, each starting only after the previous one succeeded.
# Usage, on hazel from the checkout to run (its path goes to the head jobs as ZEALGT_REPO):
#   bash scripts/submit_demultiplex_waves.sh <first wave NN> [nextflow args for every wave, e.g. -stub]
#   OUTDIR=<dir> (default /rsstu/users/r/rrellan/BZea/ZEAL/demultiplex); RESUME=<session id> resumes the first wave only
set -eo pipefail
FIRST="${1:?first wave number, e.g. 01}"; shift
REPO=$(cd "$(dirname "$0")/.." && pwd)
OUTDIR=${OUTDIR:-/rsstu/users/r/rrellan/BZea/ZEAL/demultiplex}
sheets=$(ls "$REPO"/meta/waves/demultiplex_*.csv | awk -v first="$REPO/meta/waves/demultiplex_$FIRST.csv" '$0 >= first')
[ -n "$sheets" ] || { echo "no wave sheet from demultiplex_$FIRST.csv on" >&2; exit 2; }
prev=""
for sheet in $sheets; do
    resume=(); [ -z "$prev" ] && [ -n "$RESUME" ] && resume=(-resume "$RESUME")
    prev=$(sbatch --parsable --partition=compute --qos=normal --time=1-00:00:00 --export=ALL,ZEALGT_REPO="$REPO" \
        ${prev:+--dependency=afterok:$prev} "$REPO/scripts/submit_head_job.sbatch" hpc_prod \
        --step demultiplex --input "$sheet" --outdir "$OUTDIR" "${resume[@]}" "$@")
    echo "$(basename "$sheet" .csv) job=$prev log=/share/maize/frodrig4/nf_work/zealgt_head_$prev.log"
done
