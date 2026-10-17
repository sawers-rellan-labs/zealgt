#!/bin/bash
# Hazel setup check (CLAUDE.md test step 3): every tests/hazel stub test at once, tasks as Slurm jobs (hpc_prod);
# with PARAMS=<params file of a run> also the run's config and containers, beside the tests.
# Usage, on hazel: sbatch --export=ALL,ZEALGT_REPO=<checkout>[,PARAMS=<params.yaml>,PROFILE=<hpc_dev|hpc_prod>]
#                  scripts/run_hazel_tests.sbatch [test files; default all]
# nf-test 0.9.5 (/share/maize/frodrig4/nf-test, unpacked from the release tarball) runs with the Nextflow image's java.
#SBATCH --job-name=zealgt_hazel_tests
#SBATCH --account=maize_cpu
#SBATCH --partition=compute_partners
#SBATCH --qos=short
#SBATCH --time=00:30:00
#SBATCH --cpus-per-task=4
#SBATCH --mem=16G
#SBATCH --output=/share/maize/frodrig4/nf_work/zealgt_hazel_tests_%j.log
set -o pipefail
REPO=${ZEALGT_REPO:-/rsstu/users/r/rrellan/BZea/ZEAL/zealgt}
WORK=/share/maize/frodrig4/nf_work/zealgt_hazel_tests/$SLURM_JOB_ID
NFT=/share/maize/frodrig4/nf-test/nf-test.jar
# as scripts/submit_head_job.sbatch: Nextflow image, its plugins and secrets on /share, binds for Slurm and the data
SIF=/share/maize/frodrig4/apptainer/nextflow_26.04.6.sif
NXF_DIR=/share/maize/frodrig4/nextflow_home
APPTAINER=/usr/local/apps/apptainer/1.4.2-1
BINDS=/usr/bin/sbatch,/usr/bin/squeue,/usr/bin/scancel,/usr/lib64/slurm,/var/spool/slurmd/conf-cache
BINDS=$BINDS,/usr/lib64/libmunge.so.2,/run/munge,/usr/lib64/libnss_sss.so.2,/var/lib/sss/pipes
BINDS=$BINDS,/share/maize/frodrig4,/rsstu/users/r/rrellan,$APPTAINER
export APPTAINERENV_PREPEND_PATH="$APPTAINER/bin"
nxf() { "$APPTAINER/bin/apptainer" exec -B "$BINDS" "$SIF" env NXF_OFFLINE=true NXF_PLUGINS_DIR="$NXF_DIR/plugins" \
    NXF_SECRETS_FILE="$NXF_DIR/secrets/store.json" NXF_OPTS="-Xms256m -Xmx1g" "$@"; }
stamp() { awk -v n="$1" '{ print strftime("%F %T"), "[" n "]", $0; fflush() }'; }
cd "$REPO" || exit 2
echo "$(date '+%F %T') job=$SLURM_JOB_ID node=$(hostname) commit=$(git rev-parse --short HEAD) params=${PARAMS:-none}"
[ $# -gt 0 ] || set -- tests/hazel/*.nf.test
pids=()
# the run's setup: config, then every container; no -preview: it never exits with a workflow output block
# (nextflow-io/nextflow#7836); parameters are checked by the sheet check and in the run's first seconds
if [ -n "$PARAMS" ]; then
    mkdir -p "$WORK/setup"
    ( cd "$WORK/setup" || exit 2
      nxf nextflow -q config "$REPO" -profile "${PROFILE:-hpc_prod}" > config.txt &&
      nxf nextflow -q inspect "$REPO" -profile "${PROFILE:-hpc_prod}" -params-file "$PARAMS" > inspect.json &&
      echo "config ok; $(grep -c '"container"' inspect.json) containers"
      rc=$?
      echo "exit=$rc"
      exit $rc ) 2>&1 | stamp setup &
    pids+=($!)
fi
# one nf-test per test file, each with its own work directory, all in the background
for t in "$@"; do
    n=$(basename "$t" .nf.test)
    ( s=$(date +%s)
      nxf env NFT_WORKDIR="$WORK/$n" java -Xmx512m -jar "$NFT" test "$t" --config tests/hazel/nf-test.config \
          --profile hpc_prod 2>&1 | stamp "$n"
      rc=$?
      echo "$(date '+%F %T') [$n] exit=$rc wall=$(($(date +%s) - s))s"
      exit $rc ) &
    pids+=($!)
done
failed=0
for p in "${pids[@]}"; do wait "$p" || failed=$((failed + 1)); done
echo "$(date '+%F %T') done: ${#pids[@]} checks (${PARAMS:+setup + }$# tests), $failed failed"
[ "$failed" -eq 0 ]
