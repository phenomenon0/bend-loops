#!/usr/bin/env bash
set -eu
cd "$(git rev-parse --show-toplevel)"
exec env -u ANTHROPIC_API_KEY claude -p "$(cat /home/omen/Documents/Project/bend-loops/prompts/judge-policy.md)

CONTRACT: ${LOOP_OBJECTIVE:-?}

DIFF:
$(git diff | head -c 60000)" --allowedTools 'Read,Glob,Grep'
