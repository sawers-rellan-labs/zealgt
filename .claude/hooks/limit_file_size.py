#!/usr/bin/env python3
# PostToolUse hook on Write/Edit: refuse pipeline files over their line limit, and our code in the template's utils folder.
import json, os, re, sys
call = json.load(sys.stdin).get("tool_input", {})
path = os.path.relpath(call.get("file_path", ""), os.environ.get("CLAUDE_PROJECT_DIR", "."))
limits = [
    (r"^workflows/[^/]+\.nf$", 80),
    (r"^subworkflows/local/(?!utils_nfcore_)[^/]+/main\.nf$", 100),
    (r"^modules/local/.+/main\.nf$", 80),
]
problem = None
if re.match(r"^subworkflows/local/utils_nfcore_[^/]+/", path):
    problem = "the template's utils folder holds template code and the samplesheet-to-channel step only"
elif re.search(r"\.groovy$", path):
    problem = "no Groovy function files"
else:
    for pattern, limit in limits:
        if re.match(pattern, path) and os.path.exists(path):
            n = sum(1 for _ in open(path))
            if n > limit:
                problem = f"{path} has {n} lines, limit {limit}"
            break
if problem:
    print(f"limit_file_size.py: {problem} (CLAUDE.md, Code). Split the stage or move logic where it belongs.", file=sys.stderr)
    sys.exit(2)
