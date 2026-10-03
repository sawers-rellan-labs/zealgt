#!/usr/bin/env python3
# PreToolUse hook: refuse slow commands (tests, reviews, pipeline runs, polls) unless run in the background. Exit 2 = deny.
import json, re, sys
call = json.load(sys.stdin).get("tool_input", {})
cmd = call.get("command", "")
slow = [
    r"\bnf-test\s+test\b",
    r"\bcoderabbit\s+review\b|\bcr\s+review\b",
    r"\bnextflow\b(\s+-\S+(\s+\S+)?)*\s+run\b",
    r"\bdocker\s+run\b",
    r"\bpoll_job\.sh\b",
    r"(^|[\s;&|(])sleep\s",
]
hit = [p for p in slow if re.search(p, cmd)]
if hit and not call.get("run_in_background"):
    print("blocked by .claude/hooks/require_background.py: this command waits; run it with run_in_background or in a "
          f"subagent (matched {hit[0]!r}).", file=sys.stderr)
    sys.exit(2)
