#!/bin/bash
# Hazel setup check (CLAUDE.md test step 3): every tests/hazel stub test at once, tasks as Slurm jobs (hpc_prod)
# Usage, on hazel: sbatch --export=ALL,ZEALGT_REPO=<checkout> scripts/run_hazel_tests.sbatch [test files; default all]
# nf-test 0.9.5 (/share/maize/frodrig4/nf-test, unpacked from the release tarball) runs with the Nextflow image's java.
#SBATCH --job-name=zealgt_hazel_tests
#SBATCH --account=maize_cpu
#SBATCH --partition=compute_partners
#SBATCH --qos=short
#SBATCH --time=00:30:00
#SBATCH --cpus-per-task=4
#SBATCH --mem=32G
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
cd "$REPO" || exit 2
echo "$(date '+%F %T') job=$SLURM_JOB_ID node=$(hostname) commit=$(git rev-parse --short HEAD)"
[ $# -gt 0 ] || set -- tests/hazel/*.nf.test
# one nf-test per test file, each with its own work directory, all in the background; JVM heaps capped
pids=()
for t in "$@"; do
    n=$(basename "$t" .nf.test)
    ( s=$(date +%s)
      "$APPTAINER/bin/apptainer" exec -B "$BINDS" "$SIF" env NXF_OFFLINE=true NXF_PLUGINS_DIR="$NXF_DIR/plugins" \
          NXF_SECRETS_FILE="$NXF_DIR/secrets/store.json" NXF_OPTS="-Xms256m -Xmx1g" NFT_WORKDIR="$WORK/$n" \
          java -Xmx512m -jar "$NFT" test "$t" --config tests/hazel/nf-test.config --profile hpc_prod 2>&1 \
          | awk -v n="$n" '{ print strftime("%F %T"), "[" n "]", $0; fflush() }'
      rc=$?
      echo "$(date '+%F %T') [$n] exit=$rc wall=$(($(date +%s) - s))s"
      exit $rc ) &
    pids+=($!)
done
failed=0
for p in "${pids[@]}"; do wait "$p" || failed=$((failed + 1)); done
echo "$(date '+%F %T') done: $# tests, $failed failed"
[ "$failed" -eq 0 ]
