#!/usr/bin/env bash
set -eu
cd "$(git rev-parse --show-toplevel)"
exec env -u ANTHROPIC_API_KEY claude -p "$(cat /home/omen/Documents/Project/bend-loops/prompts/proposer-policy.md)

OBJECTIVE CONTRACT: ${LOOP_OBJECTIVE:-?}
STATE: ${LOOP_STATE:-?}" --allowedTools 'Read,Write,Edit,Bash,Glob,Grep'
