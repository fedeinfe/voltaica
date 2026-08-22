#!/bin/bash
# Prints the best codesigning identity for a given team, or "-" for ad-hoc.
# Development certificates carry the user id in their common name, not the team, so the team has
# to be read out of the certificate's OU.
set -uo pipefail
TEAM="${1:-68438RG5HP}"

best=""
best_rank=99
while IFS= read -r line; do
  name=$(printf '%s' "$line" | sed -n 's/.*"\(.*\)".*/\1/p')
  [[ -z "$name" ]] && continue
  ou=$(security find-certificate -c "$name" -p 2>/dev/null \
       | openssl x509 -noout -subject 2>/dev/null \
       | tr ',' '\n' | sed -n 's/.*OU=\(.*\)/\1/p' | tr -d ' ' | head -1)
  [[ "$ou" != "$TEAM" ]] && continue
  case "$name" in
    "Developer ID Application"*) rank=0 ;;
    "Apple Development"*) rank=1 ;;
    "Apple Distribution"*) rank=2 ;;
    *) rank=3 ;;
  esac
  if [[ $rank -lt $best_rank ]]; then best_rank=$rank; best="$name"; fi
done < <(security find-identity -v -p codesigning 2>/dev/null)

printf '%s' "${best:--}"
