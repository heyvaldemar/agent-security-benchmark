#!/bin/bash
# watch.sh <commit sha> - wait for the e2e run on a commit and the Status run
# that follows it, then print every workflow run on that commit.
#
# One GraphQL call every two minutes. GraphQL has a quota of its own, so the
# watching does not spend the REST quota that `gh run watch` polls with.
sha="${1:?usage: watch.sh <commit sha>}"
q='query($sha:String!){repository(owner:"heyvaldemar",name:"agent-security-benchmark"){object(expression:$sha){... on Commit{checkSuites(last:12){nodes{status conclusion createdAt updatedAt workflowRun{databaseId event workflow{name}}}}}}}}'
for _ in $(seq 1 40); do
  out=$(gh api graphql -f query="$q" -f sha="$sha" --jq '.data.repository.object.checkSuites.nodes[] | select(.workflowRun != null) | [.workflowRun.databaseId, .workflowRun.workflow.name, .workflowRun.event, .status, (.conclusion // "-"), .createdAt, .updatedAt] | @tsv' 2>/dev/null)
  e2e=$(printf '%s\n' "$out" | awk -F'\t' '$2=="Benchmark e2e"{print $4}' | tail -1)
  st=$(printf '%s\n' "$out" | awk -F'\t' '$2=="Status" && $3=="workflow_run"{print $4}' | tail -1)
  if [ "$e2e" = "COMPLETED" ] && [ "$st" = "COMPLETED" ]; then break; fi
  sleep 120
done
date -u +%Y-%m-%dT%H:%M:%SZ
printf '%s\n' "$out"
