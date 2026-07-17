#!/usr/bin/env bash

set -euo pipefail

: "${GITHUB_REPOSITORY:?Set GITHUB_REPOSITORY}"
: "${GH_TOKEN:?Set GH_TOKEN}"

workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT

index_file="$workdir/index.json"
pairs_file="$workdir/pairs.jsonl"

github_command() {
  local attempt output status delay reset now
  for attempt in $(seq 1 8); do
    set +e
    output=$("$@" 2>&1)
    status=$?
    set -e
    if ((status == 0)); then
      [[ -z $output ]] || printf '%s\n' "$output"
      return 0
    fi

    if [[ $output == *"rate limit"* || $output == *"API rate limit exceeded"* ]]; then
      reset=$(gh api rate_limit --jq '.resources.core.reset' 2>/dev/null || true)
      now=$(date +%s)
      if [[ $reset =~ ^[0-9]+$ ]] && ((reset > now)); then
        delay=$((reset - now + 5))
      else
        delay=$((attempt * 60))
      fi
    else
      delay=$((attempt * 15))
    fi
    printf '%s\nRetrying in %ss.\n' "$output" "$delay" >&2
    sleep "$delay"
  done
  printf '%s\n' "$output" >&2
  return "$status"
}

github_command gh release download nix-cache-index --pattern index.json --dir "$workdir"
: > "$pairs_file"
export GITHUB_REPOSITORY pairs_file

jq --raw-output '
  .objects | to_entries[] |
  select(.key | endswith(".narinfo")) |
  [.key, .value.tag, .value.asset] | @tsv
' "$index_file" | xargs -P 24 -n 3 bash -c '
  narinfo=$1
  tag=$2
  asset=$3
  nar=$(curl --fail --silent --show-error --location \
    "https://github.com/$GITHUB_REPOSITORY/releases/download/$tag/$asset" |
    sed -n "s|^URL: |/|p")
  if [[ ! $nar =~ ^/nar/[A-Za-z0-9][A-Za-z0-9._-]*\.nar(\.(zst|xz|bz2|gz))?$ ]]; then
    echo "Invalid NAR URL in $narinfo: $nar" >&2
    exit 1
  fi
  jq --null-input --compact-output --arg narinfo "$narinfo" --arg nar "$nar" \
    "{narinfo: \$narinfo, nar: \$nar}" >> "$pairs_file"
' _

jq --slurpfile pairs "$pairs_file" '
  reduce $pairs[] as $pair (.;
    if .objects[$pair.nar] != null
    then .objects[$pair.narinfo].nar = $pair.nar
    else del(.objects[$pair.narinfo])
    end
  ) |
  .objects as $objects |
  .roots |= with_entries(.value |= map(select(. as $path | $objects[$path] != null))) |
  [.roots[]?[]] | unique | map({key: ., value: true}) | from_entries as $live |
  .objects |= with_entries(select($live[.key]))
' "$index_file" > "$workdir/index.repaired.json"

before=$(jq '.objects | length' "$index_file")
after=$(jq '.objects | length' "$workdir/index.repaired.json")
mv "$workdir/index.repaired.json" "$index_file"
github_command gh release upload nix-cache-index "$index_file#index.json" --clobber
echo "Repaired cache index: $before -> $after objects."
