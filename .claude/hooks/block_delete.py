#!/usr/bin/env python3
# PreToolUse hook: block deletion commands in Bash, also inside ssh/sbatch arguments. Exit 2 = deny with the message.
import json, re, sys
cmd = json.load(sys.stdin).get("tool_input", {}).get("command", "")
patterns = [
    r"(^|[\s;&|(`'\"])rm\s",            # rm, rm -r, rm -rf
    r"(^|[\s;&|(`'\"])rmdir\s",
    r"find\b.*\s-delete\b",
    r"find\b.*-exec\s+rm\b",
    r"git\s+clean\b",
    r"rsync\b.*--delete",
    r"(^|[\s;&|(`'\"])unlink\s",
    r"(^|[\s;&|(`'\"])shred\s",
    r"\btruncate\s",
    r">\s*/rsstu/",                      # redirect that would clobber a file on the permanent partition
    r"nextflow\s+clean\b",
    r"\bmv\s+[^|;&]*\s/rsstu/users/r/rrellan/BZea/(BC1_dna_raw|BC2S3_batch_2_dna_raw|ZEAL/store)\b",
]
hit = [p for p in patterns if re.search(p, cmd)]
if hit:
    print("blocked by .claude/hooks/block_delete.py: deletion/clobbering commands are not allowed in this session "
          f"(matched {hit[0]!r}). Only Nextflow's cleanup = true may remove work/ files. Ask the user.", file=sys.stderr)
    sys.exit(2)
