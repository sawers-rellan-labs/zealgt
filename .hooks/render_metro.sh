#!/usr/bin/env bash
# Re-render the SVG of each changed metro map (docs/images/<map>.mmd -> <map>.svg)
set -euo pipefail
for mmd in "$@"; do
    nf-metro render "$mmd" -o "${mmd%.mmd}.svg" --responsive --embed-font --validate > /dev/null
done
