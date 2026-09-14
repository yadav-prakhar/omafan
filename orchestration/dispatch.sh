#!/usr/bin/env bash
# orchestration/dispatch.sh — orchestrator tool: run one OpenCode worker per ticket.
#
# Usage:  orchestration/dispatch.sh T01:opencode-go/mimo-v2.5 \
#                                   T02:opencode-go/deepseek-v4.1-flash \
#                                   T09:opencode-go/glm-5.3-flash:high
#
# Each spec is TICKET:MODEL[:VARIANT]. Sessions run in parallel; logs land in
# orchestration/logs/<TICKET>.log and a one-line verdict per ticket in
# orchestration/logs/_summary.txt. Never dispatched with a ticket whose files are
# owned by another in-flight ticket.
set -uo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo"
mkdir -p orchestration/logs
: > orchestration/logs/_summary.txt

pids=()
tickets=()

run_one() {
    local spec="$1"
    local ticket="${spec%%:*}"
    local rest="${spec#*:}"
    local model="${rest%%:*}"
    local variant=""
    if [[ "$rest" == *:* ]]; then variant="${rest#*:}"; fi

    local args=(run --model "$model")
    if [[ -n "$variant" ]]; then args+=(--variant "$variant"); fi

    local prompt
    prompt="Read orchestration/instructions/WORKER.md, then PRD.md, DESIGN.md, PLAN.md and
orchestration/tickets/${ticket}.md. Implement ticket ${ticket} exactly as specified: create or edit
only the files that ticket says you own, run the gates it names, and finish with the report format from
WORKER.md. Do not run git, do not use sudo, do not install anything."

    echo "=== dispatch ${ticket} model=${model} variant=${variant:-default} at $(date -Is)" \
        >> "orchestration/logs/${ticket}.log"
    opencode "${args[@]}" "$prompt" >> "orchestration/logs/${ticket}.log" 2>&1
    local rc=$?
    echo "${ticket} model=${model} exit=${rc}" >> orchestration/logs/_summary.txt
}

for spec in "$@"; do
    ticket="${spec%%:*}"
    tickets+=("$ticket")
    run_one "$spec" &
    pids+=($!)
done

rc=0
for pid in "${pids[@]}"; do
    wait "$pid" || rc=1
done

echo "--- summary ---"
cat orchestration/logs/_summary.txt
exit "$rc"
